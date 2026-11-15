import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';

/// Floating pill bottom navigation with five items.
///
/// The wardrobe item carries a small handle: holding it drops a menu straight
/// out of the bar — same surface, no scrim, no separate panel — and the finger
/// can slide onto a row and lift to pick it. Holding for 220 ms is enough, so
/// the menu feels like a peek rather than a long commitment. A plain tap still
/// opens the catalog.
class HomeBottomNav extends StatefulWidget {
  const HomeBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.onWardrobeLongPress,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  /// Called when a row of the wardrobe hold-menu is picked. Null on screens
  /// that are not inside the shell, where there is nothing to switch.
  final void Function({int initialTab, bool favoritesOnly})?
  onWardrobeLongPress;

  @override
  State<HomeBottomNav> createState() => _HomeBottomNavState();
}

/// One row of the hold-menu: which wardrobe page it opens.
typedef _MenuChoice = ({
  IconData icon,
  String label,
  int tab,
  bool favoritesOnly,
});

class _HomeBottomNavState extends State<HomeBottomNav> {
  static const _items = <({IconData icon, String label})>[
    (icon: Icons.home_outlined, label: 'Home'),
    (icon: Icons.checkroom_outlined, label: 'Wardrobe'),
    (icon: Icons.qr_code_scanner, label: 'Scan'),
    (icon: Icons.calendar_month_outlined, label: 'Planner'),
    (icon: Icons.person_outline, label: 'Profile'),
  ];

  static const _choices = <_MenuChoice>[
    (
      icon: Icons.style_outlined,
      label: 'Kombinasi',
      tab: 1,
      favoritesOnly: false,
    ),
    (
      icon: Icons.favorite_border,
      label: 'Favorit',
      tab: 1,
      favoritesOnly: true,
    ),
  ];

  /// Shorter than the 500 ms platform default: the menu is a peek.
  static const _holdDelay = Duration(milliseconds: 220);
  static const _rowHeight = 46.0;
  static const _menuWidth = 196.0;
  static const _menuPad = 6.0;

  /// How far the menu's bottom edge tucks into the pill. Deep enough to cover
  /// the pill's top edge and its shadow, so the menu reads as a bulge of the
  /// bar rather than a card floating above it.
  static const _menuOverlap = 12.0;

  final _barKey = GlobalKey();
  final _itemKey = GlobalKey();
  final _hover = ValueNotifier<int?>(null);

  OverlayEntry? _menu;
  Rect? _menuRect;

  @override
  void dispose() {
    _menu?.remove();
    _menu = null;
    _hover.dispose();
    super.dispose();
  }

  void _openMenu() {
    final bar = _barKey.currentContext?.findRenderObject() as RenderBox?;
    final item = _itemKey.currentContext?.findRenderObject() as RenderBox?;
    if (bar == null || item == null || _menu != null) return;

    final barTop = bar.localToGlobal(Offset.zero).dy;
    final anchor = item.localToGlobal(item.size.center(Offset.zero));
    final width = MediaQuery.sizeOf(context).width;
    final height = _choices.length * _rowHeight + _menuPad * 2;
    final left = (anchor.dx - _menuWidth / 2).clamp(
      16.0,
      (width - _menuWidth - 16.0).clamp(16.0, double.infinity),
    );

    _menuRect = Rect.fromLTWH(
      left,
      barTop + _menuOverlap - height,
      _menuWidth,
      height,
    );
    _hover.value = null;

    _menu = OverlayEntry(
      builder: (context) => Positioned.fromRect(
        rect: _menuRect!,
        // The finger is tracked by the long-press gesture itself, so the menu
        // never competes for pointer events.
        child: IgnorePointer(
          child: ValueListenableBuilder<int?>(
            valueListenable: _hover,
            builder: (context, hovered, _) => _HoldMenu(
              choices: _choices,
              hovered: hovered,
              rowHeight: _rowHeight,
              pad: _menuPad,
            ),
          ),
        ),
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(_menu!);
  }

  int? _rowAt(Offset global) {
    final rect = _menuRect;
    if (rect == null || !rect.contains(global)) return null;
    final index = ((global.dy - rect.top - _menuPad) / _rowHeight).floor();
    return index >= 0 && index < _choices.length ? index : null;
  }

  void _moveHold(Offset global) => _hover.value = _rowAt(global);

  void _endHold(Offset global) {
    final index = _rowAt(global);
    _removeMenu();
    if (index == null) {
      // Lifted without aiming at a row: that was a tap on the wardrobe item.
      widget.onTap(1);
      return;
    }
    final choice = _choices[index];
    widget.onWardrobeLongPress?.call(
      initialTab: choice.tab,
      favoritesOnly: choice.favoritesOnly,
    );
  }

  void _removeMenu() {
    _menu?.remove();
    _menu = null;
    _menuRect = null;
    _hover.value = null;
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    return Container(
      key: _barKey,
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: const BorderRadius.all(Radius.circular(32)),
        boxShadow: const [AppDecorations.cardShadow],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          for (var i = 0; i < _items.length; i++)
            Flexible(
              child: _NavButton(
                key: i == 1 ? _itemKey : null,
                icon: _items[i].icon,
                label: _items[i].label,
                selected: i == widget.currentIndex,
                isScan: i == 2,
                onTap: () => widget.onTap(i),
                onHoldStart: i == 1 && widget.onWardrobeLongPress != null
                    ? _openMenu
                    : null,
                onHoldMove: _moveHold,
                onHoldEnd: _endHold,
                onHoldCancel: _removeMenu,
              ),
            ),
        ],
      ),
    );
  }
}

/// The menu itself: a flat-bottomed card that continues the pill's surface.
class _HoldMenu extends StatelessWidget {
  const _HoldMenu({
    required this.choices,
    required this.hovered,
    required this.rowHeight,
    required this.pad,
  });

  final List<_MenuChoice> choices;
  final int? hovered;
  final double rowHeight;
  final double pad;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    // Same fill as the pill and no shadow of its own: the bar's shadow is the
    // only one on screen, so the two shapes read as one piece.
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.symmetric(vertical: pad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < choices.length; i++)
            SizedBox(
              height: rowHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: _MenuRow(
                  icon: choices[i].icon,
                  label: choices[i].label,
                  highlighted: hovered == i,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One row of the wardrobe hold-menu.
class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.label,
    required this.highlighted,
  });

  final IconData icon;
  final String label;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    // The scan red, same as the centre action: the row under the finger has to
    // be unmistakable while the menu is only a peek.
    final ink = highlighted ? palette.onAction : palette.ink;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 90),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: highlighted ? palette.action : Colors.transparent,
        borderRadius: AppRadius.field,
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: ink),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.titleMedium!.copyWith(
                fontWeight: FontWeight.w600,
                color: ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.isScan,
    required this.onTap,
    this.onHoldStart,
    this.onHoldMove,
    this.onHoldEnd,
    this.onHoldCancel,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool isScan;
  final VoidCallback onTap;

  /// Hold handlers: start opens the menu, move tracks the finger, end commits
  /// and cancel drops it. All null when the item has no hold behaviour.
  final VoidCallback? onHoldStart;
  final void Function(Offset globalPosition)? onHoldMove;
  final void Function(Offset globalPosition)? onHoldEnd;
  final VoidCallback? onHoldCancel;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    if (isScan) {
      return IconButton(
        tooltip: label,
        onPressed: onTap,
        icon: Icon(icon, size: 22, color: palette.onAction),
        style: IconButton.styleFrom(backgroundColor: palette.action),
      );
    }
    final color = selected ? palette.ink : palette.inkMuted;
    final button = InkWell(
      onTap: onTap,
      borderRadius: const BorderRadius.all(Radius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  height: 15 / 11,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (onHoldStart == null) return button;
    // A custom hold delay needs the recognizer itself: GestureDetector's
    // onLongPress is locked to the platform's 500 ms.
    return RawGestureDetector(
      gestures: {
        LongPressGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
              () => LongPressGestureRecognizer(
                duration: _HomeBottomNavState._holdDelay,
              ),
              (recognizer) {
                recognizer.onLongPressStart = (_) => onHoldStart!();
                recognizer.onLongPressMoveUpdate = (details) {
                  onHoldMove?.call(details.globalPosition);
                };
                recognizer.onLongPressEnd = (details) {
                  onHoldEnd?.call(details.globalPosition);
                };
                recognizer.onLongPressCancel = () {
                  onHoldCancel?.call();
                };
              },
            ),
      },
      child: button,
    );
  }
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';

/// Floating pill bottom navigation with five items.
///
/// The center scan button opens the add-item stub route; all other taps
/// switch the selected index.
class HomeBottomNav extends StatelessWidget {
  const HomeBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  static const _items = <({IconData icon, String label})>[
    (icon: Icons.home_outlined, label: 'Home'),
    (icon: Icons.checkroom_outlined, label: 'Wardrobe'),
    (icon: Icons.qr_code_scanner, label: 'Scan'),
    (icon: Icons.calendar_month_outlined, label: 'Planner'),
    (icon: Icons.person_outline, label: 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    return Container(
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
                icon: _items[i].icon,
                label: _items[i].label,
                selected: i == currentIndex,
                isScan: i == 2,
                onTap: () => onTap(i),
              ),
            ),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.isScan,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool isScan;
  final VoidCallback onTap;

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
    return InkWell(
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
  }
}

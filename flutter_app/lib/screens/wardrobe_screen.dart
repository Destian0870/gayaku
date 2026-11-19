import 'package:flutter/material.dart';

import '../logic/outfit_matcher.dart';
import '../models/wardrobe.dart';
import '../navigation.dart';
import '../services/wardrobe_service.dart';
import '../state/outfit_store.dart';
import '../state/wardrobe_store.dart';
import '../state/wardrobe_sync.dart';
import '../theme/app_theme.dart';
import '../widgets/home_bottom_nav.dart';
import '../widgets/note.dart';
import '../widgets/placeholder_image.dart';
import '../widgets/wardrobe_item_card.dart';
import 'outfit_builder_screen.dart';
import 'wardrobe_item_detail_screen.dart';

/// Wardrobe hub with two tabs: the item catalog and the saved combinations.
///
/// The catalog is the SQLite-backed [wardrobeItems] store (docs/adr/0004);
/// search and filters stay local, and combinations are still session-only.
class WardrobeScreen extends StatefulWidget {
  const WardrobeScreen({
    super.key,
    this.items,
    this.initialTab = 0,
    this.initialFavoritesOnly = false,
    this.showNav = true,
  });

  /// Overrides the store with a fixed catalog, for tests. Null — the app's
  /// case — follows [wardrobeItems], so a scanned garment shows up here as
  /// soon as it is saved.
  final List<WardrobeItem>? items;
  final int initialTab;
  final bool initialFavoritesOnly;

  /// False inside `NavShell`, which draws the one shared bar.
  final bool showNav;

  @override
  State<WardrobeScreen> createState() => _WardrobeScreenState();
}

class _WardrobeScreenState extends State<WardrobeScreen> {
  final _search = TextEditingController();
  String _category = wardrobeCategories.first;
  String _query = '';
  Set<String> _occasions = {};
  int _minFormality = 1;
  late int _tab;
  late bool _favoritesOnly;

  /// Ids picked by a long press; non-empty means the catalog is selecting.
  final Set<String> _selected = {};

  bool get _selecting => _selected.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab;
    _favoritesOnly = widget.initialFavoritesOnly;
  }

  @override
  void didUpdateWidget(covariant WardrobeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialTab != oldWidget.initialTab) {
      _tab = widget.initialTab;
    }
    if (widget.initialFavoritesOnly != oldWidget.initialFavoritesOnly) {
      _favoritesOnly = widget.initialFavoritesOnly;
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool get _filtering =>
      _occasions.isNotEmpty ||
      _minFormality > 1 ||
      _category != wardrobeCategories.first;

  /// The line under the title: what the list below actually holds, plus the
  /// filters that are on — a count alone looks wrong once two are active.
  String _subtitle(List<SavedOutfit> outfits) {
    if (_tab == 1) {
      final count = _favoritesOnly
          ? outfits.where((outfit) => outfit.favorite).length
          : outfits.length;
      return 'Total $count kombinasi${_favoritesOnly ? ' favorit' : ''}';
    }
    final noun = _category == wardrobeCategories.first
        ? 'items'
        : _category.toLowerCase();
    final filters = <String>[
      ...(_occasions.toList()..sort()).map(
        (occasion) => occasion.toLowerCase(),
      ),
      if (_minFormality > 1) 'formalitas $_minFormality',
    ];
    final suffix = filters.isEmpty ? '' : ' ${filters.join(' ')}';
    return 'Total ${_visible.length} $noun$suffix';
  }

  Future<void> _openBuilder({SavedOutfit? existing}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            OutfitBuilderScreen(existing: existing, catalog: _catalog),
      ),
    );
  }

  /// The catalog in play: the injected override, else the live store.
  List<WardrobeItem> get _catalog => widget.items ?? wardrobeItems.value;

  /// Occasions present in the catalog, so the filter never offers a dead option.
  List<String> get _availableOccasions =>
      {for (final item in _catalog) ...item.occasions}.toList()..sort();

  Future<void> _openFilters() async {
    final result =
        await showModalBottomSheet<
          ({Set<String> occasions, int minFormality, String category})
        >(
          context: context,
          backgroundColor: AppColors.of(context).sheet,
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheet),
          builder: (context) => _FilterSheet(
            occasions: _availableOccasions,
            selected: _occasions,
            minFormality: _minFormality,
            category: _category,
          ),
        );
    if (result == null) return;
    setState(() {
      _occasions = result.occasions;
      _minFormality = result.minFormality;
      _category = result.category;
    });
  }

  Future<void> _confirmDelete(SavedOutfit outfit) async {
    final palette = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: palette.sheet,
        title: Text(
          'Hapus kombinasi?',
          style: textTheme.titleLarge!.copyWith(
            fontWeight: FontWeight.w600,
            color: palette.ink,
          ),
        ),
        content: Text(
          '"${outfit.name}" akan dihapus dari daftar.',
          style: textTheme.labelLarge!.copyWith(
            fontWeight: FontWeight.w500,
            color: palette.inkMuted,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Batal',
              style: textTheme.labelLarge!.copyWith(
                fontWeight: FontWeight.w600,
                color: palette.ink,
              ),
            ),
          ),
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: OutlinedButton.styleFrom(
              foregroundColor: palette.actionInk,
              side: BorderSide(color: palette.actionInk),
              shape: const RoundedRectangleBorder(borderRadius: AppRadius.chip),
            ),
            child: Text(
              'Hapus',
              style: textTheme.labelLarge!.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    if (ok ?? false) {
      await _run(() => deleteOutfit(outfit.id));
    }
  }

  /// Runs one backend call and shows its message when it fails, so a rejected
  /// write never leaves the row looking saved.
  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } on OutfitException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  void _toggle(WardrobeItem item) {
    setState(() {
      if (!_selected.remove(item.id)) _selected.add(item.id);
    });
  }

  void _clearSelection() => setState(_selected.clear);

  /// Long press: select the tile and preview it, with the actions the current
  /// selection allows — edit only makes sense for exactly one garment.
  Future<void> _preview(WardrobeItem item) async {
    setState(() => _selected.add(item.id));
    final action = await showModalBottomSheet<_ItemAction>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.of(context).sheet,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheet),
      builder: (_) =>
          _ItemPreviewSheet(item: item, selectedCount: _selected.length),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _ItemAction.edit:
        await _editOne(item);
      case _ItemAction.delete:
        await _deleteSelected();
      case _ItemAction.selectMore:
        break;
    }
  }

  Future<void> _editOne(WardrobeItem item) async {
    final edited = await showModalBottomSheet<WardrobeItem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.of(context).sheet,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheet),
      builder: (_) => WardrobeEditSheet(item: item),
    );
    if (edited == null || !mounted) return;
    try {
      await saveWardrobeItem(edited);
      if (!mounted) return;
      _clearSelection();
      showNote(context, 'Perubahan tersimpan');
    } on WardrobeException catch (e) {
      if (mounted) showNote(context, e.message);
    }
  }

  /// Deletes every selected garment that no combination still lists; the ones
  /// in use are reported instead of silently breaking a saved look.
  Future<void> _deleteSelected() async {
    final inUse = <String>{
      for (final outfit in savedOutfits.value) ...outfit.itemIds,
    };
    final targets = _selected.toList();
    final free = targets.where((id) => !inUse.contains(id)).toList();
    if (free.isEmpty) {
      showNote(
        context,
        'Item ini masih dipakai di kombinasi. Hapus kombinasinya dulu.',
      );
      return;
    }

    final palette = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: palette.sheet,
        title: Text(
          free.length == 1 ? 'Hapus baju?' : 'Hapus ${free.length} baju?',
          style: textTheme.titleLarge!.copyWith(
            fontWeight: FontWeight.w600,
            color: palette.ink,
          ),
        ),
        content: Text(
          free.length == 1
              ? 'Item terpilih akan dihapus dari lemarimu.'
              : '${free.length} item terpilih akan dihapus dari lemarimu.',
          style: textTheme.labelLarge!.copyWith(
            fontWeight: FontWeight.w500,
            color: palette.inkMuted,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              'Batal',
              style: textTheme.labelLarge!.copyWith(
                fontWeight: FontWeight.w600,
                color: palette.ink,
              ),
            ),
          ),
          OutlinedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: OutlinedButton.styleFrom(
              foregroundColor: palette.actionInk,
              side: BorderSide(color: palette.actionInk),
              shape: const RoundedRectangleBorder(borderRadius: AppRadius.chip),
            ),
            child: Text(
              'Hapus',
              style: textTheme.labelLarge!.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    var removed = 0;
    try {
      for (final id in free) {
        await removeWardrobeItem(id);
        removed++;
      }
    } on WardrobeException catch (e) {
      if (mounted) showNote(context, e.message);
    }
    if (!mounted) return;
    _clearSelection();
    final skipped = targets.length - free.length;
    showNote(
      context,
      '$removed baju dihapus'
      '${skipped > 0 ? ', $skipped dilewati karena masih dipakai kombinasi' : ''}',
    );
  }

  List<WardrobeItem> get _visible {
    final query = _query.trim().toLowerCase();
    return _catalog.where((item) {
      if (_category != wardrobeCategories.first && item.category != _category) {
        return false;
      }
      if (item.formality < _minFormality) return false;
      if (_occasions.isNotEmpty && !item.occasions.any(_occasions.contains)) {
        return false;
      }
      if (query.isEmpty) return true;
      return '${item.name} ${item.brand} ${item.category} ${item.colorName}'
          .toLowerCase()
          .contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    // The store is the normal path; a test may still hand in a fixed list.
    if (widget.items != null) return _scaffold(context);
    return ValueListenableBuilder<List<WardrobeItem>>(
      valueListenable: wardrobeItems,
      builder: (context, _, _) => _scaffold(context),
    );
  }

  Widget _scaffold(BuildContext context) {
    final palette = AppColors.of(context);
    return Scaffold(
      backgroundColor: palette.canvas,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ValueListenableBuilder<List<SavedOutfit>>(
                      valueListenable: savedOutfits,
                      builder: (context, outfits, _) => _Header(
                        subtitle: _subtitle(outfits),
                        // One + for both tabs: scan a garment on the catalog,
                        // build a combination on the saved ones.
                        onAdd: _tab == 0
                            ? () => openNavDestination(context, 2)
                            : () => _openBuilder(),
                        addTooltip: _tab == 0 ? 'Add item' : 'Buat Kombinasi',
                      ),
                    ),
                    const SizedBox(height: 16),
                    _TabToggle(
                      tab: _tab,
                      onChanged: (t) => setState(() {
                        _tab = t;
                        _selected.clear();
                      }),
                    ),
                    const SizedBox(height: 16),
                    if (_tab == 0) ..._catalogTab() else ..._outfitTab(),
                  ],
                ),
              ),
            ),
            if (widget.showNav)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: HomeBottomNav(
                  currentIndex: 1,
                  onTap: (index) => openNavDestination(context, index),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _catalogTab() {
    final palette = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    final items = _visible;
    return [
      _SearchRow(
        controller: _search,
        filtering: _filtering,
        onQuery: (value) => setState(() => _query = value),
        onFilter: _openFilters,
      ),
      if (_selecting) ...[
        const SizedBox(height: 12),
        _SelectionBar(
          count: _selected.length,
          onEdit: () {
            final item = _catalog
                .where((candidate) => candidate.id == _selected.first)
                .firstOrNull;
            if (item != null) _editOne(item);
          },
          onDelete: _deleteSelected,
          onClear: _clearSelection,
        ),
      ],
      const SizedBox(height: 16),
      if (items.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Center(
            child: Text(
              'Nothing in this category yet.',
              textAlign: TextAlign.center,
              style: textTheme.bodyLarge!.copyWith(
                fontWeight: FontWeight.w400,
                color: palette.inkMuted,
              ),
            ),
          ),
        )
      else
        GridView.count(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 16,
          childAspectRatio: 0.75,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (final item in items)
              WardrobeItemCard(
                item: item,
                selected: _selected.contains(item.id),
                // While selecting, a tap adds or drops a garment instead of
                // leaving for the detail page.
                onTap: _selecting ? () => _toggle(item) : null,
                onLongPress: () => _preview(item),
              ),
          ],
        ),
    ];
  }

  List<Widget> _outfitTab() {
    final palette = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    return [
      _SavedOutfitFilters(
        favoritesOnly: _favoritesOnly,
        onFavoritesOnlyChanged: (value) =>
            setState(() => _favoritesOnly = value),
      ),
      const SizedBox(height: 16),
      ValueListenableBuilder(
        valueListenable: savedOutfits,
        builder: (context, outfits, _) {
          final visibleOutfits = _favoritesOnly
              ? outfits.where((outfit) => outfit.favorite).toList()
              : outfits;
          if (visibleOutfits.isEmpty) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  _favoritesOnly
                      ? 'Belum ada favorit tersimpan.'
                      : 'Belum ada kombinasi tersimpan.',
                  style: textTheme.bodyLarge!.copyWith(
                    fontWeight: FontWeight.w400,
                    color: palette.inkMuted,
                  ),
                ),
              ),
            );
          }
          return Column(
            children: [
              for (final outfit in _favoritesFirst(visibleOutfits)) ...[
                _SavedOutfitCard(
                  outfit: outfit,
                  catalog: _catalog,
                  onEdit: () => _openBuilder(existing: outfit),
                  onDelete: () => _confirmDelete(outfit),
                  onToggleFavorite: () =>
                      _run(() => toggleOutfitFavorite(outfit.id)),
                ),
                const SizedBox(height: 12),
              ],
            ],
          );
        },
      ),
    ];
  }

  /// Favourites first, otherwise the store's newest-first order.
  List<SavedOutfit> _favoritesFirst(List<SavedOutfit> outfits) => [
    ...outfits.where((o) => o.favorite),
    ...outfits.where((o) => !o.favorite),
  ];
}

class _SavedOutfitFilters extends StatelessWidget {
  const _SavedOutfitFilters({
    required this.favoritesOnly,
    required this.onFavoritesOnlyChanged,
  });

  final bool favoritesOnly;
  final ValueChanged<bool> onFavoritesOnlyChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _Chip(
          label: 'Semua',
          selected: !favoritesOnly,
          onTap: () => onFavoritesOnlyChanged(false),
        ),
        _Chip(
          label: 'Favorit',
          selected: favoritesOnly,
          onTap: () => onFavoritesOnlyChanged(true),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.subtitle,
    required this.onAdd,
    required this.addTooltip,
  });

  final String subtitle;
  final VoidCallback onAdd;
  final String addTooltip;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Wardrobe',
                style: textTheme.headlineLarge!.copyWith(
                  fontWeight: FontWeight.w700,
                  color: palette.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: textTheme.labelLarge!.copyWith(
                  fontWeight: FontWeight.w500,
                  color: palette.inkMuted,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: addTooltip,
          onPressed: onAdd,
          icon: const Icon(Icons.add, size: 22),
          color: palette.ink,
          style: IconButton.styleFrom(
            backgroundColor: palette.sheet,
            minimumSize: const Size(48, 48),
          ),
        ),
      ],
    );
  }
}

/// Segmented switch between the catalog and the saved combinations.
class _TabToggle extends StatelessWidget {
  const _TabToggle({required this.tab, required this.onChanged});

  final int tab;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final palette = AppColors.of(context);
    return Container(
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: palette.sheet,
        borderRadius: AppRadius.panel,
      ),
      // One indicator slides between the halves instead of two segments
      // repainting their own fill, so the switch reads as one control.
      child: Stack(
        children: [
          AnimatedAlign(
            alignment: tab == 0 ? Alignment.centerLeft : Alignment.centerRight,
            duration: AppMotion.route,
            curve: Curves.easeOutCubic,
            child: FractionallySizedBox(
              widthFactor: 0.5,
              heightFactor: 1,
              child: Container(
                decoration: BoxDecoration(
                  color: palette.action,
                  borderRadius: AppRadius.chip,
                ),
              ),
            ),
          ),
          Row(
            children: [
              _segment(palette, textTheme, 'Katalog', 0),
              _segment(palette, textTheme, 'Kombinasi', 1),
            ],
          ),
        ],
      ),
    );
  }

  Widget _segment(
    AppPalette palette,
    TextTheme textTheme,
    String label,
    int index,
  ) {
    final active = tab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(index),
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: AnimatedDefaultTextStyle(
            duration: AppMotion.state,
            style: textTheme.labelMedium!.copyWith(
              fontWeight: FontWeight.w600,
              color: active ? palette.onAction : palette.inkMuted,
            ),
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
      ),
    );
  }
}

class _SavedOutfitCard extends StatelessWidget {
  const _SavedOutfitCard({
    required this.outfit,
    required this.catalog,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleFavorite,
  });

  final SavedOutfit outfit;

  /// Catalog the saved ids resolve against; an id with no row is dropped.
  final List<WardrobeItem> catalog;

  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    final items = outfit.itemsOf(catalog);
    final percent = (outfitScore(items) * 100).round();
    final threshold = (outfit.threshold * 100).round();
    final meets = percent >= threshold;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: AppRadius.panel,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  outfit.name,
                  // Two lines: the three action buttons now share this row,
                  // so a user-named combination would otherwise ellipsize.
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleLarge!.copyWith(
                    fontWeight: FontWeight.w600,
                    color: palette.ink,
                  ),
                ),
              ),
              IconButton(
                tooltip: outfit.favorite
                    ? 'Hapus dari favorit'
                    : 'Tandai favorit',
                onPressed: onToggleFavorite,
                icon: Icon(
                  outfit.favorite ? Icons.favorite : Icons.favorite_border,
                  size: 18,
                ),
                color: outfit.favorite ? palette.actionInk : palette.ink,
                style: IconButton.styleFrom(
                  backgroundColor: palette.sheet,
                  minimumSize: const Size(40, 40),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Edit kombinasi',
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 18),
                color: palette.ink,
                style: IconButton.styleFrom(
                  backgroundColor: palette.sheet,
                  minimumSize: const Size(40, 40),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Hapus kombinasi',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, size: 18),
                color: palette.ink,
                style: IconButton.styleFrom(
                  backgroundColor: palette.sheet,
                  minimumSize: const Size(40, 40),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final item in items) ...[
                ClipRRect(
                  borderRadius: AppRadius.chip,
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: PlaceholderImage(
                      imagePath: item.imagePath,
                      icon: Icons.checkroom_outlined,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: meets ? palette.action : palette.accentTint,
                  borderRadius: AppRadius.chip,
                ),
                child: Text(
                  '$percent%',
                  style: textTheme.labelMedium!.copyWith(
                    fontWeight: FontWeight.w600,
                    color: meets ? palette.onAction : palette.ink,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Same number as before, now with a bar so the gap to the
                    // threshold is visible instead of being mental arithmetic.
                    ClipRRect(
                      borderRadius: AppRadius.pill,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween<double>(begin: 0, end: percent / 100),
                        duration: AppMotion.hero,
                        curve: Curves.easeOutCubic,
                        builder: (context, value, _) => LinearProgressIndicator(
                          value: value,
                          minHeight: 6,
                          backgroundColor: palette.surfaceMuted,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            meets ? palette.action : palette.accentInk,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      meets
                          ? 'Memenuhi batas $threshold%'
                          : 'Di bawah batas $threshold%',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.labelMedium!.copyWith(
                        fontWeight: FontWeight.w400,
                        color: palette.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SearchRow extends StatefulWidget {
  const _SearchRow({
    required this.controller,
    required this.filtering,
    required this.onQuery,
    required this.onFilter,
  });

  final TextEditingController controller;
  final bool filtering;
  final ValueChanged<String> onQuery;
  final VoidCallback onFilter;

  @override
  State<_SearchRow> createState() => _SearchRowState();
}

class _SearchRowState extends State<_SearchRow> {
  // The ring is the only cue that the field has the keyboard, so it has to
  // follow focus rather than a tap.
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _onFocusChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        Expanded(
          child: AnimatedContainer(
            duration: AppMotion.state,
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: palette.sheet,
              borderRadius: AppRadius.hero,
              border: Border.all(
                color: _focus.hasFocus ? palette.accentInk : palette.sheet,
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.search, size: 22, color: palette.inkMuted),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: widget.controller,
                    focusNode: _focus,
                    textInputAction: TextInputAction.search,
                    onChanged: widget.onQuery,
                    style: textTheme.labelLarge!.copyWith(
                      fontWeight: FontWeight.w500,
                      color: palette.ink,
                    ),
                    decoration: InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      hintText: 'Search your clothes...',
                      hintStyle: textTheme.labelLarge!.copyWith(
                        fontWeight: FontWeight.w500,
                        color: palette.inkMuted,
                      ),
                    ),
                  ),
                ),
                // Fades in only when there is something to clear.
                AnimatedSwitcher(
                  duration: AppMotion.state,
                  child: widget.controller.text.isEmpty
                      ? const SizedBox.shrink()
                      : IconButton(
                          key: const ValueKey('clear'),
                          tooltip: 'Clear search',
                          onPressed: () {
                            widget.controller.clear();
                            widget.onQuery('');
                          },
                          icon: const Icon(Icons.close, size: 18),
                          color: palette.inkMuted,
                        ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        IconButton(
          tooltip: 'Filter',
          onPressed: widget.onFilter,
          icon: const Icon(Icons.tune, size: 22),
          color: widget.filtering ? palette.onAction : palette.ink,
          style: IconButton.styleFrom(
            backgroundColor: widget.filtering ? palette.action : palette.sheet,
            minimumSize: const Size(52, 52),
            shape: const RoundedRectangleBorder(borderRadius: AppRadius.pill),
          ),
        ),
      ],
    );
  }
}

/// Occasion and formality filter. Pops the chosen filter, or null on dismiss.
class _FilterSheet extends StatefulWidget {
  const _FilterSheet({
    required this.occasions,
    required this.selected,
    required this.minFormality,
    required this.category,
  });

  final List<String> occasions;
  final Set<String> selected;
  final int minFormality;
  final String category;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late Set<String> _selected = {...widget.selected};
  late int _minFormality = widget.minFormality;
  late String _category = widget.category;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      // Category + occasions + formality outgrew a short screen, so the
      // sheet scrolls instead of clipping its own buttons.
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.accentTint,
                  borderRadius: AppRadius.pill,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Filter',
              style: textTheme.headlineSmall!.copyWith(
                fontWeight: FontWeight.w700,
                color: palette.ink,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Kategori',
              style: textTheme.labelLarge!.copyWith(
                fontWeight: FontWeight.w500,
                color: palette.inkMuted,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final category in wardrobeCategories)
                  _Chip(
                    label: category,
                    selected: _category == category,
                    onTap: () => setState(() => _category = category),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Acara',
              style: textTheme.labelLarge!.copyWith(
                fontWeight: FontWeight.w500,
                color: palette.inkMuted,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final occasion in widget.occasions)
                  _Chip(
                    label: occasion,
                    selected: _selected.contains(occasion),
                    onTap: () => setState(() {
                      if (_selected.contains(occasion)) {
                        _selected.remove(occasion);
                      } else {
                        _selected.add(occasion);
                      }
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Formalitas minimal',
                    style: textTheme.labelLarge!.copyWith(
                      fontWeight: FontWeight.w500,
                      color: palette.inkMuted,
                    ),
                  ),
                ),
                Text(
                  '$_minFormality/5',
                  style: textTheme.labelLarge!.copyWith(
                    fontWeight: FontWeight.w600,
                    color: palette.ink,
                  ),
                ),
              ],
            ),
            Slider(
              value: _minFormality.toDouble(),
              min: 1,
              max: 5,
              divisions: 4,
              activeColor: palette.actionInk,
              inactiveColor: palette.accentTint,
              label: '$_minFormality',
              onChanged: (v) => setState(() => _minFormality = v.round()),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() {
                      _selected = {};
                      _minFormality = 1;
                      _category = wardrobeCategories.first;
                    }),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: palette.ink,
                      side: BorderSide(color: palette.inkMuted),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: const RoundedRectangleBorder(
                        borderRadius: AppRadius.panel,
                      ),
                    ),
                    child: Text(
                      'Reset',
                      style: textTheme.labelLarge!.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop((
                      occasions: _selected,
                      minFormality: _minFormality,
                      category: _category,
                    )),
                    style: FilledButton.styleFrom(
                      backgroundColor: palette.action,
                      foregroundColor: palette.onAction,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: const RoundedRectangleBorder(
                        borderRadius: AppRadius.panel,
                      ),
                    ),
                    child: Text(
                      'Terapkan',
                      style: textTheme.labelLarge!.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppMotion.state,
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? palette.action : palette.surfaceMuted,
          borderRadius: AppRadius.pill,
        ),
        child: Text(
          label,
          style: textTheme.labelLarge!.copyWith(
            fontWeight: FontWeight.w500,
            color: selected ? palette.onAction : palette.inkMuted,
          ),
        ),
      ),
    );
  }
}

/// What the preview sheet asks the catalog to do next.
enum _ItemAction { edit, delete, selectMore }

/// Above the grid while garments are selected: how many, plus the actions that
/// count allows — edit needs exactly one, delete takes the lot.
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.count,
    required this.onEdit,
    required this.onDelete,
    required this.onClear,
  });

  final int count;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: AppRadius.panel,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$count dipilih',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.labelLarge!.copyWith(
                fontWeight: FontWeight.w600,
                color: palette.ink,
              ),
            ),
          ),
          if (count == 1)
            IconButton(
              key: const ValueKey('selection-edit'),
              tooltip: 'Edit baju',
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 20),
              color: palette.ink,
              style: IconButton.styleFrom(
                backgroundColor: palette.sheet,
                minimumSize: const Size(44, 44),
              ),
            ),
          const SizedBox(width: 8),
          IconButton(
            key: const ValueKey('selection-delete'),
            tooltip: count == 1 ? 'Hapus baju' : 'Hapus $count baju',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline, size: 20),
            color: palette.ink,
            style: IconButton.styleFrom(
              backgroundColor: palette.sheet,
              minimumSize: const Size(44, 44),
            ),
          ),
          IconButton(
            tooltip: 'Batalkan pilihan',
            onPressed: onClear,
            icon: const Icon(Icons.close, size: 18),
            color: palette.inkMuted,
          ),
        ],
      ),
    );
  }
}

/// Long-press preview: the photo big, the attributes, and the two actions the
/// current selection allows.
class _ItemPreviewSheet extends StatelessWidget {
  const _ItemPreviewSheet({required this.item, required this.selectedCount});

  final WardrobeItem item;
  final int selectedCount;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    final single = selectedCount == 1;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.accentTint,
                  borderRadius: AppRadius.pill,
                ),
              ),
            ),
            const SizedBox(height: 16),
            AspectRatio(
              aspectRatio: 1.15,
              child: ClipRRect(
                borderRadius: AppRadius.hero,
                child: PlaceholderImage(
                  imagePath: item.imagePath,
                  icon: Icons.checkroom_outlined,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              item.name,
              style: textTheme.headlineSmall!.copyWith(
                fontWeight: FontWeight.w700,
                color: palette.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              item.brand.isEmpty
                  ? item.category
                  : '${item.category} • ${item.brand}',
              style: textTheme.labelLarge!.copyWith(
                fontWeight: FontWeight.w500,
                color: palette.inkMuted,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (item.colorName.isNotEmpty) _Tag(item.colorName),
                _Tag('Formalitas ${item.formality}/5'),
                for (final occasion in item.occasions) _Tag(occasion),
              ],
            ),
            const SizedBox(height: 20),
            if (!single)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  '$selectedCount item dipilih. Edit hanya untuk satu item.',
                  style: textTheme.labelMedium!.copyWith(
                    fontWeight: FontWeight.w400,
                    color: palette.inkMuted,
                  ),
                ),
              ),
            Row(
              children: [
                if (single) ...[
                  Expanded(
                    child: FilledButton.icon(
                      key: const ValueKey('preview-edit'),
                      onPressed: () =>
                          Navigator.of(context).pop(_ItemAction.edit),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: Text(
                        'Edit',
                        style: textTheme.labelLarge!.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: palette.action,
                        foregroundColor: palette.onAction,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: const RoundedRectangleBorder(
                          borderRadius: AppRadius.panel,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: OutlinedButton.icon(
                    key: const ValueKey('preview-delete'),
                    onPressed: () =>
                        Navigator.of(context).pop(_ItemAction.delete),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: Text(
                      single ? 'Hapus' : 'Hapus $selectedCount',
                      style: textTheme.labelLarge!.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: palette.actionInk,
                      side: BorderSide(color: palette.actionInk),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: const RoundedRectangleBorder(
                        borderRadius: AppRadius.panel,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: () =>
                    Navigator.of(context).pop(_ItemAction.selectMore),
                child: Text(
                  single ? 'Pilih item lain' : 'Lanjut pilih item lain',
                  style: textTheme.labelLarge!.copyWith(
                    fontWeight: FontWeight.w600,
                    color: palette.inkMuted,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Read-only attribute pill on the preview sheet.
class _Tag extends StatelessWidget {
  const _Tag(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: palette.surfaceMuted,
        borderRadius: AppRadius.pill,
      ),
      child: Text(
        label,
        style: textTheme.labelMedium!.copyWith(
          fontWeight: FontWeight.w500,
          color: palette.ink,
        ),
      ),
    );
  }
}

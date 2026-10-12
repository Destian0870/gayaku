import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../logic/outfit_matcher.dart';
import '../models/wardrobe.dart';
import '../navigation.dart';
import '../state/outfit_store.dart';
import '../theme/app_theme.dart';
import '../widgets/home_bottom_nav.dart';
import '../widgets/placeholder_image.dart';
import '../widgets/wardrobe_item_card.dart';
import 'outfit_builder_screen.dart';

/// Wardrobe hub with two tabs: the item catalog and the saved combinations.
///
/// UI only — chips, search and combinations live in local state / an in-memory
/// store; nothing is persisted.
class WardrobeScreen extends StatefulWidget {
  const WardrobeScreen({super.key, this.items = wardrobeItems});

  final List<WardrobeItem> items;

  @override
  State<WardrobeScreen> createState() => _WardrobeScreenState();
}

class _WardrobeScreenState extends State<WardrobeScreen> {
  String _category = wardrobeCategories.first;
  int _tab = 0;

  Future<void> _openBuilder({SavedOutfit? existing}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OutfitBuilderScreen(existing: existing),
      ),
    );
  }

  Future<void> _confirmDelete(SavedOutfit outfit) async {
    final palette = AppColors.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: palette.canvas,
        title: Text(
          'Hapus kombinasi?',
          style: GoogleFonts.bricolageGrotesque(
            fontSize: 24,
            height: 30 / 24,
            fontWeight: FontWeight.bold,
            color: palette.ink,
          ),
        ),
        content: Text(
          '"${outfit.name}" akan dihapus dari daftar.',
          style: GoogleFonts.inter(
            fontSize: 16,
            height: 23 / 16,
            color: palette.inkMuted,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (ok ?? false) deleteOutfit(outfit.id);
  }

  List<WardrobeItem> get _visible => _category == wardrobeCategories.first
      ? widget.items
      : widget.items.where((i) => i.category == _category).toList();

  @override
  Widget build(BuildContext context) {
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
                    _Header(itemCount: widget.items.length),
                    const SizedBox(height: 16),
                    ValueListenableBuilder(
                      valueListenable: savedOutfits,
                      builder: (context, outfits, _) => _TabToggle(
                        tab: _tab,
                        outfitCount: outfits.length,
                        onChanged: (t) => setState(() => _tab = t),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_tab == 0) ..._catalogTab() else ..._outfitTab(),
                  ],
                ),
              ),
            ),
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
    final items = _visible;
    return [
      const _SearchRow(),
      const SizedBox(height: 16),
      _CategoryChips(
        selected: _category,
        onSelected: (c) => setState(() => _category = c),
      ),
      const SizedBox(height: 16),
      if (items.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Center(
            child: Text(
              'Nothing in this category yet.',
              style: GoogleFonts.inter(
                fontSize: 16,
                height: 23 / 16,
                color: palette.inkMuted,
              ),
            ),
          ),
        )
      else
        GridView.count(
          crossAxisCount: 2,
          crossAxisSpacing: 14,
          mainAxisSpacing: 16,
          childAspectRatio: 0.75,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [for (final item in items) WardrobeItemCard(item: item)],
        ),
    ];
  }

  List<Widget> _outfitTab() {
    final palette = AppColors.of(context);
    return [
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: () => _openBuilder(),
          icon: const Icon(Icons.add, size: 18),
          label: Text(
            'Buat Kombinasi',
            style: GoogleFonts.inter(
              fontSize: 13,
              height: 18 / 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: palette.ink,
            foregroundColor: palette.canvas,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(24)),
            ),
          ),
        ),
      ),
      const SizedBox(height: 16),
      ValueListenableBuilder(
        valueListenable: savedOutfits,
        builder: (context, outfits, _) {
          if (outfits.isEmpty) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  'Belum ada kombinasi tersimpan.',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    height: 23 / 16,
                    color: palette.inkMuted,
                  ),
                ),
              ),
            );
          }
          return Column(
            children: [
              for (final outfit in outfits) ...[
                _SavedOutfitCard(
                  outfit: outfit,
                  onEdit: () => _openBuilder(existing: outfit),
                  onDelete: () => _confirmDelete(outfit),
                ),
                const SizedBox(height: 12),
              ],
            ],
          );
        },
      ),
    ];
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.itemCount});

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Wardrobe',
                style: GoogleFonts.bricolageGrotesque(
                  fontSize: 32,
                  height: 38 / 32,
                  fontWeight: FontWeight.bold,
                  color: palette.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Total $itemCount items',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  height: 15 / 11,
                  color: palette.inkMuted,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Add item',
          onPressed: () => showComingSoon(context, 'Add item'),
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
  const _TabToggle({
    required this.tab,
    required this.outfitCount,
    required this.onChanged,
  });

  final int tab;
  final int outfitCount;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: palette.sheet,
        borderRadius: const BorderRadius.all(Radius.circular(24)),
      ),
      child: Row(
        children: [
          _segment(palette, 'Katalog', 0),
          _segment(palette, 'Kombinasi ($outfitCount)', 1),
        ],
      ),
    );
  }

  Widget _segment(AppPalette palette, String label, int index) {
    final active = tab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(index),
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: active ? palette.action : Colors.transparent,
            borderRadius: const BorderRadius.all(Radius.circular(12)),
          ),
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 13,
              height: 18 / 13,
              fontWeight: active ? FontWeight.w600 : FontWeight.w500,
              color: active ? palette.onAction : palette.inkMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _SavedOutfitCard extends StatelessWidget {
  const _SavedOutfitCard({
    required this.outfit,
    required this.onEdit,
    required this.onDelete,
  });

  final SavedOutfit outfit;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final items = outfit.items;
    final percent = (outfitScore(items) * 100).round();
    final threshold = (outfit.threshold * 100).round();
    final meets = percent >= threshold;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.sheet,
        borderRadius: const BorderRadius.all(Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: palette.ink.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  outfit.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.bricolageGrotesque(
                    fontSize: 20,
                    height: 26 / 20,
                    fontWeight: FontWeight.bold,
                    color: palette.ink,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Edit kombinasi',
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 18),
                color: palette.ink,
                style: IconButton.styleFrom(
                  backgroundColor: palette.surface,
                  minimumSize: const Size(38, 38),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'Hapus kombinasi',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, size: 18),
                color: palette.ink,
                style: IconButton.styleFrom(
                  backgroundColor: palette.surface,
                  minimumSize: const Size(38, 38),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final item in items) ...[
                ClipRRect(
                  borderRadius: const BorderRadius.all(Radius.circular(12)),
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
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: meets ? palette.ink : palette.surface,
                  borderRadius: const BorderRadius.all(Radius.circular(12)),
                ),
                child: Text(
                  '$percent%',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    height: 15 / 11,
                    fontWeight: FontWeight.w600,
                    color: meets ? palette.canvas : palette.ink,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  meets
                      ? 'Memenuhi batas $threshold%'
                      : 'Di bawah batas $threshold%',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    height: 15 / 11,
                    color: palette.inkMuted,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SearchRow extends StatelessWidget {
  const _SearchRow();

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: palette.sheet,
              borderRadius: const BorderRadius.all(Radius.circular(32)),
              border: Border.all(color: palette.surface),
            ),
            child: Row(
              children: [
                Icon(Icons.search, size: 22, color: palette.inkMuted),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    textInputAction: TextInputAction.search,
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      height: 23 / 16,
                      color: palette.ink,
                    ),
                    decoration: InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      hintText: 'Search your clothes...',
                      hintStyle: GoogleFonts.inter(
                        fontSize: 16,
                        height: 23 / 16,
                        color: palette.inkMuted,
                      ),
                    ),
                    onSubmitted: (value) => showComingSoon(
                      context,
                      value.trim().isEmpty ? 'Search' : 'Search "$value"',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        IconButton(
          tooltip: 'Filter',
          onPressed: () => showComingSoon(context, 'Filter'),
          icon: const Icon(Icons.tune, size: 22),
          color: palette.ink,
          style: IconButton.styleFrom(
            backgroundColor: palette.sheet,
            minimumSize: const Size(52, 52),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(16)),
            ),
          ),
        ),
      ],
    );
  }
}

class _CategoryChips extends StatelessWidget {
  const _CategoryChips({required this.selected, required this.onSelected});

  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: wardrobeCategories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final label = wardrobeCategories[index];
          final active = label == selected;
          return GestureDetector(
            onTap: () => onSelected(label),
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: active ? palette.action : palette.sheet,
                borderRadius: const BorderRadius.all(Radius.circular(12)),
                border: active ? null : Border.all(color: palette.surface),
              ),
              child: Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  height: 18 / 13,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                  color: active ? palette.onAction : palette.inkMuted,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../logic/outfit_matcher.dart';
import '../models/wardrobe.dart';
import '../state/outfit_store.dart';
import '../theme/app_theme.dart';
import '../widgets/placeholder_image.dart';

/// Detail of one wardrobe item plus the pieces it pairs with.
///
/// UI only: the ranking comes from [outfitFor] (color harmony, formality,
/// occasion). Nothing is persisted and no API is called.
class WardrobeItemDetailScreen extends StatelessWidget {
  const WardrobeItemDetailScreen({
    super.key,
    required this.item,
    this.catalog = wardrobeItems,
  });

  final WardrobeItem item;
  final List<WardrobeItem> catalog;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final matches = outfitFor(item, catalog);
    final alternatives = recommendMatches(item, catalog).length - matches.length;

    return Scaffold(
      backgroundColor: palette.canvas,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TopBar(name: item.name),
              const SizedBox(height: 16),
              _Hero(item: item),
              const SizedBox(height: 16),
              _AttributeRow(item: item),
              const SizedBox(height: 24),
              _SectionTitle(
                title: 'Cocok Dipadukan Dengan',
                subtitle: matches.isEmpty
                    ? 'Belum ada item lain di lemarimu.'
                    : 'Diurutkan dari harmoni warna, formalitas, dan acara.',
              ),
              const SizedBox(height: 14),
              for (final match in matches) ...[
                _MatchCard(match: match),
                const SizedBox(height: 12),
              ],
              if (alternatives > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '+$alternatives pilihan lain dengan skor lebih rendah',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      height: 15 / 11,
                      color: palette.inkMuted,
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              _CombineButton(item: item, matches: matches),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    return Row(
      children: [
        IconButton(
          tooltip: 'Kembali',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back, size: 22),
          color: palette.ink,
          style: IconButton.styleFrom(
            backgroundColor: palette.sheet,
            minimumSize: const Size(44, 44),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            name,
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
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.item});

  final WardrobeItem item;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.sheet,
        borderRadius: const BorderRadius.all(Radius.circular(32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.all(Radius.circular(16)),
            child: SizedBox(
              height: 220,
              width: double.infinity,
              child: PlaceholderImage(
                imagePath: item.imagePath,
                icon: Icons.checkroom_outlined,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: GoogleFonts.bricolageGrotesque(
                    fontSize: 24,
                    height: 30 / 24,
                    fontWeight: FontWeight.bold,
                    color: palette.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.brand.isEmpty
                      ? item.category
                      : '${item.category} • ${item.brand}',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    height: 15 / 11,
                    color: palette.inkMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Color swatch, formality dots and occasion pills for the selected item.
class _AttributeRow extends StatelessWidget {
  const _AttributeRow({required this.item});

  final WardrobeItem item;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        if (item.colorName.isNotEmpty)
          _Pill(
            leading: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: item.color,
                shape: BoxShape.circle,
                border: Border.all(color: palette.surface),
              ),
            ),
            label: item.colorName,
          ),
        _Pill(
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 1; i <= 5; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 2),
                  child: Icon(
                    Icons.circle,
                    size: 7,
                    color: i <= item.formality
                        ? palette.accentInk
                        : palette.surface,
                  ),
                ),
            ],
          ),
          label: 'Formalitas ${item.formality}/5',
        ),
        for (final occasion in item.occasions)
          _Pill(label: occasion, filled: true),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, this.leading, this.filled = false});

  final String label;
  final Widget? leading;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: filled ? palette.action : palette.sheet,
        borderRadius: const BorderRadius.all(Radius.circular(999)),
        border: filled ? null : Border.all(color: palette.surface),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 8)],
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              height: 15 / 11,
              fontWeight: FontWeight.w500,
              color: filled ? palette.onAction : palette.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.bricolageGrotesque(
            fontSize: 24,
            height: 30 / 24,
            fontWeight: FontWeight.bold,
            color: palette.ink,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: GoogleFonts.inter(
            fontSize: 11,
            height: 15 / 11,
            color: palette.inkMuted,
          ),
        ),
      ],
    );
  }
}

/// One recommended partner: thumbnail, name, reason chips, score badge.
class _MatchCard extends StatelessWidget {
  const _MatchCard({required this.match});

  final MatchSuggestion match;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final item = match.item;
    return Container(
      padding: const EdgeInsets.all(10),
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
      child: Row(
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.all(Radius.circular(16)),
            child: SizedBox(
              width: 72,
              height: 72,
              child: PlaceholderImage(
                imagePath: item.imagePath,
                icon: Icons.checkroom_outlined,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.bricolageGrotesque(
                    fontSize: 20,
                    height: 26 / 20,
                    fontWeight: FontWeight.bold,
                    color: palette.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${item.category} • ${item.colorName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    height: 15 / 11,
                    color: palette.inkMuted,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final reason in match.reasons)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: palette.surface,
                          borderRadius: const BorderRadius.all(
                            Radius.circular(12),
                          ),
                        ),
                        child: Text(
                          reason,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            height: 15 / 11,
                            color: palette.ink,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${match.percent}%',
            style: GoogleFonts.bricolageGrotesque(
              fontSize: 11,
              height: 15 / 11,
              fontWeight: FontWeight.bold,
              color: palette.action,
            ),
          ),
        ],
      ),
    );
  }
}

class _CombineButton extends StatelessWidget {
  const _CombineButton({required this.item, required this.matches});

  final WardrobeItem item;
  final List<MatchSuggestion> matches;

  /// Stores the base item plus its recommended partners as a saved combination.
  void _save(BuildContext context) {
    if (matches.isEmpty) {
      showNote(context, 'Belum ada item untuk dikombinasikan');
      return;
    }
    saveOutfit(
      SavedOutfit(
        id: newOutfitId(),
        name: 'Setelan ${item.name}',
        itemNames: [item.name, ...matches.map((m) => m.item.name)],
        threshold: 0.80,
      ),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Kombinasi tersimpan di tab Kombinasi')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: () => _save(context),
        icon: const Icon(Icons.bookmark_add_outlined, size: 18),
        label: Text(
          'Simpan Kombinasi',
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
    );
  }
}

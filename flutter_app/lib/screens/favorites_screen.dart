import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/wardrobe.dart';
import '../navigation.dart';
import '../theme/app_theme.dart';
import '../widgets/home_bottom_nav.dart';
import '../widgets/placeholder_image.dart';
import 'outfit_detail_screen.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  static const filters = ['All', 'Casual', 'Office'];
  var selectedFilter = 'All';
  var selectedSort = LookSortOption.newest;
  var savedLooks = favoriteLooks;

  List<Look> get visibleLooks {
    final filtered = selectedFilter == 'All'
        ? [...savedLooks]
        : savedLooks
            .where((look) => look.styleTag == selectedFilter)
            .toList();
    filtered.sort((a, b) => switch (selectedSort) {
          LookSortOption.newest => (b.savedAt ?? DateTime(0))
              .compareTo(a.savedAt ?? DateTime(0)),
          LookSortOption.oldest => (a.savedAt ?? DateTime(0))
              .compareTo(b.savedAt ?? DateTime(0)),
          LookSortOption.titleAscending =>
            a.title.toLowerCase().compareTo(b.title.toLowerCase()),
          LookSortOption.titleDescending =>
            b.title.toLowerCase().compareTo(a.title.toLowerCase()),
        });
    return filtered;
  }

  String get selectedSortLabel => switch (selectedSort) {
        LookSortOption.newest => 'Newest',
        LookSortOption.oldest => 'Oldest',
        LookSortOption.titleAscending => 'A-Z',
        LookSortOption.titleDescending => 'Z-A',
      };

  void removeFavorite(Look look) {
    setState(() {
      savedLooks = savedLooks
          .where((favorite) => favorite.id != look.id)
          .toList(growable: false);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${look.title} removed from favorites'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> openLook(Look look) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => OutfitDetailScreen(look: look),
      ),
    );
  }

  void showSortOptions() {
    showModalBottomSheet<LookSortOption>(
      context: context,
      backgroundColor: AppColors.warmBackground,
      showDragHandle: true,
      builder: (sheetContext) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sort Favorite Looks',
              style: GoogleFonts.playfairDisplay(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppColors.espresso,
              ),
            ),
            const SizedBox(height: 14),
            const _SortSectionLabel(label: 'Saved time'),
            _SortOptionTile(
              label: 'Newest first',
              icon: Icons.schedule,
              selected: selectedSort == LookSortOption.newest,
              onTap: () => Navigator.of(sheetContext)
                  .pop(LookSortOption.newest),
            ),
            _SortOptionTile(
              label: 'Oldest first',
              icon: Icons.history,
              selected: selectedSort == LookSortOption.oldest,
              onTap: () => Navigator.of(sheetContext)
                  .pop(LookSortOption.oldest),
            ),
            const SizedBox(height: 8),
            const _SortSectionLabel(label: 'Title'),
            _SortOptionTile(
              label: 'A-Z',
              icon: Icons.sort_by_alpha,
              selected: selectedSort == LookSortOption.titleAscending,
              onTap: () => Navigator.of(sheetContext)
                  .pop(LookSortOption.titleAscending),
            ),
            _SortOptionTile(
              label: 'Z-A',
              icon: Icons.sort_by_alpha,
              selected: selectedSort == LookSortOption.titleDescending,
              onTap: () => Navigator.of(sheetContext)
                  .pop(LookSortOption.titleDescending),
            ),
          ],
        ),
      ),
    ).then((sort) {
      if (sort != null && mounted) setState(() => selectedSort = sort);
    });
  }

  @override
  Widget build(BuildContext context) {
    final looks = visibleLooks;
    return Scaffold(
      backgroundColor: AppColors.warmBackground,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                    sliver: SliverToBoxAdapter(
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            tooltip: 'Back',
                            icon: const Icon(Icons.arrow_back),
                            color: AppColors.espresso,
                            style: IconButton.styleFrom(
                              backgroundColor: AppColors.white,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Favorite Looks',
                              style: GoogleFonts.playfairDisplay(
                                fontSize: 25,
                                fontWeight: FontWeight.bold,
                                color: AppColors.espresso,
                              ),
                            ),
                          ),
                          Text(
                            '${looks.length} looks',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: AppColors.taupe,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    sliver: SliverToBoxAdapter(
                      child: _FilterBar(
                        selectedFilter: selectedFilter,
                        onFilterChanged: (filter) =>
                            setState(() => selectedFilter = filter),
                        selectedSortLabel: selectedSortLabel,
                        onSortTap: showSortOptions,
                      ),
                    ),
                  ),
                  if (looks.isEmpty)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: _EmptyLooks(),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                      sliver: SliverList.builder(
                        itemCount: looks.length,
                        itemBuilder: (context, index) {
                          final look = looks[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: _LookCard(
                              look: look,
                              onTap: () => openLook(look),
                              onFavoriteTap: () => removeFavorite(look),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: HomeBottomNav(
                currentIndex: 0,
                onTap: (index) => openNavDestination(context, index),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.selectedFilter,
    required this.onFilterChanged,
    required this.selectedSortLabel,
    required this.onSortTap,
  });

  final String selectedFilter;
  final ValueChanged<String> onFilterChanged;
  final String selectedSortLabel;
  final VoidCallback onSortTap;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final filter in _FavoritesScreenState.filters)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(filter),
                  selected: selectedFilter == filter,
                  onSelected: (_) => onFilterChanged(filter),
                  selectedColor: AppColors.tan,
                  backgroundColor: AppColors.white,
                  labelStyle: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: selectedFilter == filter
                        ? AppColors.white
                        : AppColors.espresso,
                  ),
                  side: BorderSide.none,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
              ),
            IconButton(
              onPressed: onSortTap,
              tooltip: 'Sort favorites',
              icon: const Icon(Icons.tune, size: 19),
              color: AppColors.espresso,
              style: IconButton.styleFrom(
                backgroundColor: AppColors.white,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              selectedSortLabel,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.taupe,
              ),
            ),
          ],
        ),
      );
}

class _SortSectionLabel extends StatelessWidget {
  const _SortSectionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 12, bottom: 4),
        child: Text(
          label.toUpperCase(),
          style: GoogleFonts.inter(
            fontSize: 11,
            letterSpacing: 1,
            fontWeight: FontWeight.w600,
            color: AppColors.taupe,
          ),
        ),
      );
}

class _SortOptionTile extends StatelessWidget {
  const _SortOptionTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.white : AppColors.beige,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Material(
          color: selected ? AppColors.white : AppColors.beige,
          borderRadius: BorderRadius.circular(18),
          child: ListTile(
            onTap: onTap,
            leading: Icon(icon, color: AppColors.tan),
            title: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.espresso,
              ),
            ),
            trailing: Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? AppColors.tan : AppColors.taupe,
            ),
          ),
        ),
      );
}

class _LookCard extends StatelessWidget {
  const _LookCard({
    required this.look,
    required this.onTap,
    required this.onFavoriteTap,
  });

  final Look look;
  final VoidCallback onTap;
  final VoidCallback onFavoriteTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.all(Radius.circular(30)),
            boxShadow: [AppDecorations.cardShadow],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 260,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    PlaceholderImage(
                      imagePath: look.imagePath,
                      icon: Icons.checkroom,
                      color: AppColors.imageSurface,
                    ),
                    Positioned(
                      top: 14,
                      left: 14,
                      child: _Tag(label: look.styleTag),
                    ),
                    Positioned(
                      top: 10,
                      right: 10,
                      child: IconButton(
                        onPressed: onFavoriteTap,
                        tooltip: 'Remove favorite',
                        icon: const Icon(Icons.favorite, size: 19),
                        color: AppColors.tan,
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.warmBackground,
                        ),
                      ),
                    ),
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 14,
                      child: Text(
                        look.subtitle,
                        style: GoogleFonts.inter(
                          color: AppColors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          shadows: const [
                            Shadow(color: AppColors.espresso, blurRadius: 8),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 17),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        look.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppColors.espresso,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '${look.colorHarmony}% match',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.tan,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.warmBackground.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.espresso,
          ),
        ),
      );
}

class _EmptyLooks extends StatelessWidget {
  const _EmptyLooks();

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.favorite_border, size: 48, color: AppColors.tan),
              const SizedBox(height: 14),
              Text(
                'No favorite looks yet',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 21,
                  fontWeight: FontWeight.bold,
                  color: AppColors.espresso,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Save a complete outfit recommendation to see it here.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 13, color: AppColors.taupe),
              ),
            ],
          ),
        ),
      );
}

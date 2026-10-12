import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/wardrobe.dart';
import '../theme/app_theme.dart';
import 'placeholder_image.dart';

/// Horizontal list of recently added garments plus a "View all" link.
class RecentlyAdded extends StatelessWidget {
  const RecentlyAdded({super.key, this.items = recentItems});

  final List<WardrobeItem> items;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Recently Added',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.bricolageGrotesque(
                  fontSize: 24,
                  height: 30 / 24,
                  fontWeight: FontWeight.bold,
                  color: palette.ink,
                ),
              ),
            ),
            TextButton(
              onPressed: () => showComingSoon(context, 'Wardrobe'),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'View all',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  height: 18 / 13,
                  fontWeight: FontWeight.w600,
                  color: palette.action,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 190,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final item = items[index];
              return GestureDetector(
                onTap: () => showComingSoon(context, item.name),
                child: SizedBox(
                  width: 130,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: const BorderRadius.all(
                            Radius.circular(16),
                          ),
                          child: SizedBox(
                            width: double.infinity,
                            child: PlaceholderImage(
                              imagePath: item.imagePath,
                              icon: Icons.image_outlined,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          height: 23 / 16,
                          fontWeight: FontWeight.w600,
                          color: palette.ink,
                        ),
                      ),
                      Text(
                        item.category,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          height: 18 / 13,
                          color: palette.inkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

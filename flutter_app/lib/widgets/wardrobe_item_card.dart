import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/wardrobe.dart';
import '../screens/wardrobe_item_detail_screen.dart';
import '../theme/app_theme.dart';
import 'placeholder_image.dart';

/// Grid tile: photo over `Name` and `Category • Brand`.
class WardrobeItemCard extends StatelessWidget {
  const WardrobeItemCard({super.key, required this.item});

  final WardrobeItem item;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => WardrobeItemDetailScreen(item: item),
        ),
      ),
      child: Container(
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.all(Radius.circular(16)),
                child: SizedBox(
                  width: double.infinity,
                  child: PlaceholderImage(
                    imagePath: item.imagePath,
                    icon: Icons.checkroom_outlined,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
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
              item.brand.isEmpty
                  ? item.category
                  : '${item.category} • ${item.brand}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 11,
                height: 15 / 11,
                color: palette.inkMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

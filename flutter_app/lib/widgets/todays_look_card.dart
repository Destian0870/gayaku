import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/wardrobe.dart';
import '../theme/app_theme.dart';
import 'placeholder_image.dart';

/// Featured outfit card with a style-tag pill over the photo and a
/// decorative check button.
class TodaysLookCard extends StatelessWidget {
  const TodaysLookCard({super.key, this.look = todaysLook});

  final Look look;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    return GestureDetector(
      onTap: () => showComingSoon(context, 'Outfit details'),
      child: Card(
        margin: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(32),
              ),
              child: SizedBox(
                height: 190,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    PlaceholderImage(
                      imagePath: look.imagePath,
                      icon: Icons.checkroom_outlined,
                    ),
                    Positioned(
                      top: 12,
                      left: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: palette.canvas,
                          borderRadius: const BorderRadius.all(
                            Radius.circular(999),
                          ),
                        ),
                        child: Text(
                          look.styleTag,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            height: 15 / 11,
                            fontWeight: FontWeight.w600,
                            color: palette.ink,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 12,
                      right: 12,
                      child: IconButton(
                        onPressed: () =>
                            showComingSoon(context, 'Outfit details'),
                        icon: const Icon(Icons.check, size: 18),
                        color: palette.onAction,
                        style: IconButton.styleFrom(
                          backgroundColor: palette.action,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    look.title,
                    style: GoogleFonts.bricolageGrotesque(
                      fontSize: 20,
                      height: 26 / 20,
                      fontWeight: FontWeight.bold,
                      color: palette.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    look.subtitle,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      height: 18 / 13,
                      color: palette.inkMuted,
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
}

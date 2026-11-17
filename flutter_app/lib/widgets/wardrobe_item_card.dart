import 'package:flutter/material.dart';

import '../models/wardrobe.dart';
import '../screens/wardrobe_item_detail_screen.dart';
import '../state/wardrobe_store.dart';
import '../theme/app_theme.dart';
import 'placeholder_image.dart';

/// Grid tile: photo over `Name` and `Category • Brand`.
///
/// A plain tap opens the detail page; the catalog can override that with
/// [onTap] while it is selecting, and [onLongPress] starts the selection with
/// a preview of this garment.
class WardrobeItemCard extends StatelessWidget {
  const WardrobeItemCard({
    super.key,
    required this.item,
    this.catalog,
    this.selected = false,
    this.onTap,
    this.onLongPress,
  });

  final WardrobeItem item;

  /// Passed to the detail page so it ranks real partners, not the demo set.
  final List<WardrobeItem>? catalog;

  /// Draws the selection ring and check badge.
  final bool selected;

  /// Null — the default — pushes the detail page.
  final VoidCallback? onTap;

  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    return GestureDetector(
      onTap:
          onTap ??
          () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => WardrobeItemDetailScreen(
                item: item,
                catalog: catalog ?? wardrobeItems.value,
              ),
            ),
          ),
      onLongPress: onLongPress,
      // Flat tile, same shape as the Recently Added strip on Home: the photo
      // carries the card, the caption sits on the canvas under it.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: AppRadius.field,
                  child: SizedBox(
                    width: double.infinity,
                    child: PlaceholderImage(
                      imagePath: item.imagePath,
                      icon: Icons.checkroom_outlined,
                    ),
                  ),
                ),
                if (selected)
                  IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: AppRadius.field,
                        border: Border.all(color: palette.actionInk, width: 2),
                      ),
                    ),
                  ),
                if (selected)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: palette.action,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.check,
                        size: 16,
                        color: palette.onAction,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            item.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.titleMedium!.copyWith(
              fontWeight: FontWeight.w600,
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
            style: textTheme.labelMedium!.copyWith(
              fontWeight: FontWeight.w400,
              color: palette.inkMuted,
            ),
          ),
        ],
      ),
    );
  }
}

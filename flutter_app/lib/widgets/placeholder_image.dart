import 'dart:io';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Beige placeholder box with a centered icon, layered behind the garment
/// photo so the layout works before photo assets are supplied.
///
/// [imagePath] is either a Supabase URL, a bundled asset, or a local file.
/// Missing/invalid images fall back to the placeholder via `errorBuilder`.
class PlaceholderImage extends StatelessWidget {
  const PlaceholderImage({
    super.key,
    required this.imagePath,
    required this.icon,
    this.fit = BoxFit.cover,
    this.color,
  });

  final String imagePath;

  final IconData icon;
  final BoxFit fit;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final uri = Uri.tryParse(imagePath);
    final isNetworkImage =
        uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
    return Container(
      color: color ?? palette.surface,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(child: Icon(icon, size: 28, color: palette.accentInk)),
          if (isNetworkImage)
            Image.network(
              imagePath,
              fit: fit,
              loadingBuilder: (context, child, progress) =>
                  progress == null ? child : const SizedBox.shrink(),
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            )
          else if (File(imagePath).isAbsolute)
            Image.file(
              File(imagePath),
              fit: fit,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            )
          else
            Image.asset(
              imagePath,
              fit: fit,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
        ],
      ),
    );
  }
}

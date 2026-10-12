import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';
import 'placeholder_image.dart';

/// Time-of-day greeting plus the user name and a notification bell.
class GreetingHeader extends StatelessWidget {
  const GreetingHeader({super.key});

  static String greetingFor(DateTime now) {
    final hour = now.hour;
    if (hour < 12) return 'Good Morning,';
    if (hour < 17) return 'Good Afternoon,';
    return 'Good Evening,';
  }

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
                greetingFor(DateTime.now()),
                style: GoogleFonts.inter(
                  fontSize: 13,
                  height: 18 / 13,
                  color: palette.inkMuted,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Isabella',
                style: GoogleFonts.bricolageGrotesque(
                  fontSize: 32,
                  height: 38 / 32,
                  fontWeight: FontWeight.bold,
                  color: palette.ink,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () => showComingSoon(context, 'Notifications'),
          icon: const Icon(Icons.notifications_outlined, size: 22),
          color: palette.ink,
          style: IconButton.styleFrom(backgroundColor: palette.surface),
        ),
      ],
    );
  }
}

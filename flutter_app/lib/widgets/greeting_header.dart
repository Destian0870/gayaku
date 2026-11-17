import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';

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
              // ValueListenableBuilder akan otomatis mendeteksi perubahan nama seketika!
              ValueListenableBuilder<String>(
                valueListenable: globalUserName,
                builder: (context, currentName, child) {
                  return Text(
                    currentName.isNotEmpty ? currentName : 'User',
                    style: GoogleFonts.bricolageGrotesque(
                      fontSize: 32,
                      height: 38 / 32,
                      fontWeight: FontWeight.bold,
                      color: palette.ink,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

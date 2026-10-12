import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../navigation.dart';
import '../theme/app_theme.dart';
import '../widgets/home_bottom_nav.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

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
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // --- APP BAR / HEADER ---
                    Row(
                      children: [
                        IconButton(
                          icon: Icon(Icons.arrow_back, size: 22, color: palette.ink),
                          onPressed: () => Navigator.maybePop(context),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Settings',
                          style: GoogleFonts.bricolageGrotesque(
                            fontSize: 20,
                            height: 26 / 20,
                            fontWeight: FontWeight.bold,
                            color: palette.ink,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // --- PROFILE HEADER ---
                    Row(
                      children: [
                        Stack(
                          children: [
                            Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: palette.surface,
                              ),
                              child: Center(
                                child: Text(
                                  'I',
                                  style: GoogleFonts.bricolageGrotesque(
                                    fontSize: 32,
                                    height: 38 / 32,
                                    color: palette.accentInk,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.all(5),
                                decoration: BoxDecoration(
                                  color: palette.accent,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: palette.canvas,
                                    width: 2,
                                  ),
                                ),
                                child: Icon(
                                  Icons.edit,
                                  size: 18,
                                  color: palette.onAccent,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Isabella',
                              style: GoogleFonts.bricolageGrotesque(
                                fontSize: 32,
                                height: 38 / 32,
                                fontWeight: FontWeight.bold,
                                color: palette.ink,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Premium Member',
                              style: TextStyle(
                                fontSize: 11,
                                height: 15 / 11,
                                color: palette.ink.withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),

                    // --- SECTION 1: PERSONALIZATION ---
                    _sectionTitle(palette, 'PERSONALIZATION'),
                    const SizedBox(height: 12),
                    _settingsTile(
                      palette,
                      icon: Icons.checkroom_outlined,
                      title: 'Style Profile',
                    ),
                    const SizedBox(height: 12),
                    _settingsTile(
                      palette,
                      icon: Icons.tune,
                      title: 'Preferences',
                    ),
                    const SizedBox(height: 24),

                    // --- SECTION 2: GENERAL ---
                    _sectionTitle(palette, 'GENERAL'),
                    const SizedBox(height: 12),
                    _settingsTile(
                      palette,
                      icon: Icons.person_outline,
                      title: 'Account',
                    ),
                    const SizedBox(height: 12),
                    _settingsTile(
                      palette,
                      icon: Icons.notifications_none_outlined,
                      title: 'Notifications',
                    ),
                    const SizedBox(height: 12),
                    _settingsTile(
                      palette,
                      icon: Icons.lock_outline,
                      title: 'Data & Privacy',
                    ),
                    const SizedBox(height: 36),

                    // --- TOMBOL LOG OUT ---
                    Center(
                      child: GestureDetector(
                        onTap: () {},
                        child: Text(
                          'Log Out',
                          style: TextStyle(
                            color: palette.action,
                            fontSize: 13,
                            height: 18 / 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: HomeBottomNav(
                currentIndex: 4,
                onTap: (index) => openNavDestination(context, index),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(AppPalette palette, String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 11,
        height: 15 / 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
        color: palette.inkMuted,
      ),
    );
  }

  Widget _settingsTile(
    AppPalette palette, {
    required IconData icon,
    required String title,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: palette.sheet,
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: palette.accentTint,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: palette.accentInk, size: 22),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 16,
            height: 23 / 16,
            fontWeight: FontWeight.w600,
            color: palette.ink,
          ),
        ),
        trailing: Icon(
          Icons.chevron_right,
          color: palette.inkMuted,
          size: 22,
        ),
        onTap: () {},
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}

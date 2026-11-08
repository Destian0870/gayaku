import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../navigation.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/home_bottom_nav.dart';
import 'login_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String _userName = '';

  @override
  void initState() {
    super.initState();
    // A signed-in user's name comes from the auth backend; the mockup name is
    // only a fallback for the demo backend.
    final user = authService.currentUser;
    _userName = (user?.displayName ?? '').trim().isNotEmpty
        ? user!.displayName.trim()
        : (user?.email ?? '').split('@').first;
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  // --- MODAL EDIT PROFILE ---
  void _showEditProfileBottomSheet(AppPalette palette) {
    final TextEditingController nameController = TextEditingController(
      text: _userName,
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: palette.sheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (modalContext) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 24,
            bottom: MediaQuery.of(modalContext).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Edit Profile',
                style: GoogleFonts.bricolageGrotesque(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: palette.ink,
                ),
              ),
              const SizedBox(height: 20),
              Center(
                child: Stack(
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: palette.surface,
                      ),
                      child: Center(
                        child: Text(
                          _userName.isNotEmpty
                              ? _userName[0].toUpperCase()
                              : 'I',
                          style: GoogleFonts.bricolageGrotesque(
                            fontSize: 36,
                            color: palette.accentInk,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: GestureDetector(
                        onTap: () {
                          Navigator.pop(modalContext);
                          _showSnackBar('Pilih foto dari galeri...');
                        },
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: palette.accent,
                            shape: BoxShape.circle,
                            border: Border.all(color: palette.canvas, width: 2),
                          ),
                          child: Icon(
                            Icons.camera_alt,
                            size: 16,
                            color: palette.onAccent,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Nama Pengguna',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: palette.inkMuted,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: palette.canvas,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
                style: TextStyle(color: palette.ink, fontSize: 16),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: palette.accent,
                    foregroundColor: palette.onAccent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  onPressed: () async {
                    final name = nameController.text.trim();
                    if (name.isEmpty) {
                      Navigator.pop(modalContext);
                      return;
                    }
                    try {
                      final updated = await authService.updateDisplayName(name);
                      if (!mounted || !modalContext.mounted) return;
                      setState(() => _userName = updated.displayName);
                      Navigator.pop(modalContext);
                      _showSnackBar('Profil berhasil diperbarui!');
                    } catch (_) {
                      if (!modalContext.mounted) return;
                      _showSnackBar('Gagal menyimpan profil.');
                    }
                  },
                  child: const Text(
                    'Simpan Perubahan',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // --- MODAL 2: ACCOUNT ---
  void _showAccountBottomSheet(AppPalette palette) {
    showModalBottomSheet(
      context: context,
      backgroundColor: palette.sheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (modalContext) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Account Info',
                style: GoogleFonts.bricolageGrotesque(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: palette.ink,
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: Icon(Icons.email_outlined, color: palette.accentInk),
                title: Text(
                  'Email',
                  style: TextStyle(fontSize: 12, color: palette.inkMuted),
                ),
                subtitle: Text(
                  authService.currentUser?.email ?? '',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: palette.ink,
                  ),
                ),
              ),
              const Divider(),
              ListTile(
                leading: Icon(
                  Icons.lock_reset_outlined,
                  color: palette.accentInk,
                ),
                title: Text(
                  'Ubah Kata Sandi',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: palette.ink,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  Navigator.pop(modalContext);
                  final email = authService.currentUser?.email ?? '';
                  if (email.isEmpty) return;
                  try {
                    await authService.requestPasswordReset(email);
                    if (!mounted) return;
                    _showSnackBar('Tautan ubah kata sandi dikirim ke $email.');
                  } catch (_) {
                    if (!mounted) return;
                    _showSnackBar('Gagal mengirim tautan ubah kata sandi.');
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

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
                          icon: Icon(
                            Icons.arrow_back,
                            size: 22,
                            color: palette.ink,
                          ),
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
                                  _userName.isNotEmpty
                                      ? _userName[0].toUpperCase()
                                      : 'I',
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
                              child: GestureDetector(
                                onTap: () =>
                                    _showEditProfileBottomSheet(palette),
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
                            ),
                          ],
                        ),
                        const SizedBox(width: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _userName,
                              style: GoogleFonts.bricolageGrotesque(
                                fontSize: 32,
                                height: 38 / 32,
                                fontWeight: FontWeight.bold,
                                color: palette.ink,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              authService.currentUser?.email ?? '',
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

                    // --- SECTION: GENERAL ---
                    _sectionTitle(palette, 'GENERAL'),
                    const SizedBox(height: 12),
                    _settingsTile(
                      palette,
                      icon: Icons.person_outline,
                      title: 'Account',
                      onTap: () => _showAccountBottomSheet(palette),
                    ),
                    const SizedBox(height: 36),

                    // --- TOMBOL LOG OUT ---
                    Center(
                      child: GestureDetector(
                        onTap: () {
                          showDialog(
                            context: context,
                            builder: (dialogContext) => AlertDialog(
                              title: const Text('Konfirmasi Log Out'),
                              content: const Text(
                                'Apakah Anda yakin ingin keluar dari akun?',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(dialogContext),
                                  child: const Text('Batal'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(dialogContext),
                                  child: const Text('Batal'),
                                ),
                                TextButton(
                                  onPressed: () async {
                                    await authService.signOut();
                                    if (!context.mounted) return;
                                    Navigator.pop(dialogContext);
                                    Navigator.pushAndRemoveUntil(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            const LoginScreen(),
                                      ),
                                      (route) => false,
                                    );
                                  },
                                  child: const Text(
                                    'Keluar',
                                    style: TextStyle(color: Colors.red),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
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
    required VoidCallback onTap,
  }) {
    return Material(
      color: palette.sheet,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
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
        trailing: Icon(Icons.chevron_right, color: palette.inkMuted, size: 22),
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}

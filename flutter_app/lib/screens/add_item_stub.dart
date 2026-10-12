import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/wardrobe.dart';
import '../theme/app_theme.dart';

class AddItemStub extends StatefulWidget {
  const AddItemStub({super.key});

  @override
  State<AddItemStub> createState() => _AddItemStubState();
}

class _AddItemStubState extends State<AddItemStub> {
  final _nameController = TextEditingController(text: 'Summer Blouse');
  var _category = 'Tops';
  var _color = 'Beige';
  var _isScanning = true;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _editCategory() async {
    final value = await _chooseValue('Category', [
      'Tops',
      'Bottoms',
      'Outerwear',
      'Shoes',
      'Accessories',
    ], _category);
    if (value != null) setState(() => _category = value);
  }

  Future<void> _editColor() async {
    final value = await _chooseValue('Color', [
      'Beige',
      'Black',
      'White',
      'Brown',
      'Blue',
      'Green',
    ], _color);
    if (value != null) setState(() => _color = value);
  }

  Future<String?> _chooseValue(
    String title,
    List<String> values,
    String selected,
  ) {
    final palette = AppColors.of(context);
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: palette.sheet,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(title, style: GoogleFonts.bricolageGrotesque(
                  fontSize: 24,
                  height: 30 / 24,
                  fontWeight: FontWeight.bold,
                  color: palette.ink,
                )),
              ),
            ),
            for (final value in values)
              ListTile(
                leading: Icon(
                  value == selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: value == selected
                      ? palette.accentInk
                      : palette.inkMuted,
                ),
                title: Text(
                  value,
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    height: 23 / 16,
                    color: palette.ink,
                  ),
                ),
                onTap: () => Navigator.of(context).pop(value),
              ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  void _saveItem() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add an item name first')),
      );
      return;
    }
    Navigator.of(context).pop(
      WardrobeItem(
        name: name,
        category: _category,
        imagePath: 'assets/images/scanned_item.jpg',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    return Scaffold(
      backgroundColor: palette.sheet,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Back',
                    icon: const Icon(Icons.arrow_back, size: 22),
                    color: palette.ink,
                    style: IconButton.styleFrom(
                      backgroundColor: palette.sheet,
                    ),
                  ),
                  const Expanded(
                    child: Center(child: _PageTitle()),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
              const SizedBox(height: 16),
              _ScannerFrame(
                isScanning: _isScanning,
                onCapture: () => setState(() => _isScanning = !_isScanning),
              ),
              const SizedBox(height: 28),
              Text(
                'AI DETECTED DETAILS',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  height: 15 / 11,
                  letterSpacing: 1.1,
                  color: palette.inkMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: palette.sheet,
                  borderRadius: const BorderRadius.all(Radius.circular(24)),
                  boxShadow: const [AppDecorations.panelShadow],
                ),
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Column(
                  children: [
                    _DetailRow(
                      icon: Icons.checkroom,
                      label: 'Category',
                      value: _category,
                      onEdit: _editCategory,
                    ),
                    const Divider(height: 1),
                    _DetailRow(
                      icon: Icons.palette_outlined,
                      label: 'Color',
                      value: _color,
                      onEdit: _editColor,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _nameController,
                style: GoogleFonts.inter(
                  fontSize: 16,
                  height: 23 / 16,
                  color: palette.ink,
                ),
                decoration: InputDecoration(
                  labelText: 'Item name',
                  labelStyle: GoogleFonts.inter(
                    fontSize: 13,
                    height: 18 / 13,
                    color: palette.inkMuted,
                  ),
                  filled: true,
                  fillColor: palette.sheet,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saveItem,
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text(
                    'Save to Wardrobe',
                    style: TextStyle(
                      fontSize: 13,
                      height: 18 / 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: palette.action,
                    foregroundColor: palette.onAction,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PageTitle extends StatelessWidget {
  const _PageTitle();

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    return Text(
      'Add New Item',
      style: GoogleFonts.bricolageGrotesque(
        fontSize: 20,
        height: 26 / 20,
        fontWeight: FontWeight.bold,
        color: palette.ink,
      ),
    );
  }
}

class _ScannerFrame extends StatelessWidget {
  const _ScannerFrame({required this.isScanning, required this.onCapture});

  final bool isScanning;
  final VoidCallback onCapture;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    return Container(
        height: 306,
        decoration: BoxDecoration(
          color: palette.surfaceMuted,
          borderRadius: BorderRadius.circular(32),
        ),
        padding: const EdgeInsets.all(20),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(
              decoration: BoxDecoration(
                color: palette.surfaceMuted,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: palette.sheet, width: 4),
              ),
              child: Center(
                child: Icon(
                  Icons.checkroom,
                  size: 150,
                  color: palette.accentInk,
                ),
              ),
            ),
            Align(
              alignment: Alignment.topCenter,
              child: Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                decoration: BoxDecoration(
                  color: palette.ink.withValues(alpha: 0.78),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  isScanning ? 'Scanning item...' : 'Ready to scan',
                  style: GoogleFonts.inter(
                    color: palette.onAction,
                    fontSize: 11,
                    height: 15 / 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: IconButton(
                onPressed: onCapture,
                tooltip: 'Capture item',
                icon: const Icon(Icons.camera_alt_outlined, size: 28),
                color: palette.ink,
                style: IconButton.styleFrom(
                  backgroundColor: palette.sheet,
                  minimumSize: const Size(68, 68),
                ),
              ),
            ),
            Positioned(
              left: 16,
              bottom: 18,
              child: Icon(Icons.flash_off_outlined, size: 22, color: palette.ink),
            ),
            Positioned(
              right: 16,
              bottom: 18,
              child: Icon(Icons.flip_camera_android_outlined,
                  size: 22, color: palette.ink),
            ),
          ],
        ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onEdit,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 13),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: palette.accentTint,
              child: Icon(icon, color: palette.accentInk, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: GoogleFonts.inter(
                    fontSize: 13,
                    height: 18 / 13,
                    color: palette.inkMuted,
                  )),
                  const SizedBox(height: 2),
                  Text(value, style: GoogleFonts.inter(
                    fontSize: 16,
                    height: 23 / 16,
                    fontWeight: FontWeight.w600,
                    color: palette.ink,
                  )),
                ],
              ),
            ),
            TextButton(
              onPressed: onEdit,
              child: Text(
                'Edit',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  height: 18 / 13,
                  color: palette.action,
                ),
              ),
            ),
          ],
        ),
    );
  }
}

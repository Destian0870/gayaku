import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../models/scan_result.dart';
import '../models/wardrobe.dart';

/// A wardrobe call that failed with a message the UI can show as-is.
class WardrobeException implements Exception {
  const WardrobeException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The only seam between the wardrobe screens and the backend.
abstract class WardrobeService {
  /// Owner's items, newest scan first.
  Future<List<WardrobeItem>> items();

  /// Stores the garment metadata. The cutout PNG stays on the device; only its
  /// file name reaches Postgres. [name] overrides the suggested name the user
  /// may have corrected on the review screen.
  Future<WardrobeItem> add(ScanResult scan, {String? name});

  Future<void> remove(String id);
}

/// Keeps items in memory for tests and for runs built without credentials.
///
/// ponytail: the cutout PNG is dropped — nothing reads it back. Replace by
/// passing real credentials to `flutter run` (see supabase/README.md).
class DemoWardrobeService implements WardrobeService {
  final _items = <WardrobeItem>[];
  var _seq = 0;

  @override
  Future<List<WardrobeItem>> items() async =>
      List.unmodifiable(_items.reversed);

  @override
  Future<WardrobeItem> add(ScanResult scan, {String? name}) async {
    final item = WardrobeItem(
      id: 'demo-${++_seq}',
      name: _name(scan, name),
      label: scan.label,
      category: scan.category.id,
      imagePath: '',
      colorName: scan.colorName,
      color: scan.dominantColor,
      formality: scan.formality,
      confidence: scan.confidence,
    );
    _items.add(item);
    return item;
  }

  @override
  Future<void> remove(String id) async =>
      _items.removeWhere((item) => item.id == id);
}

/// Postgres only. `wardrobe_items` holds the scan metadata plus the file name
/// of the cutout, which lives in this device's documents dir.
class SupabaseWardrobeService implements WardrobeService {
  SupabaseWardrobeService(this._client);

  final sb.SupabaseClient _client;

  static const _table = 'wardrobe_items';
  static const _dir = 'cutouts';

  @override
  Future<List<WardrobeItem>> items() async {
    final rows = await _guard(
      () => _client.from(_table).select().order('created_at', ascending: false),
    );
    final dir = await _cutoutDir();
    return rows.map((row) => _toItem(row, dir)).toList();
  }

  @override
  Future<WardrobeItem> add(ScanResult scan, {String? name}) async {
    final dir = await _cutoutDir();
    final file = '${DateTime.now().microsecondsSinceEpoch}.png';
    await File('$dir/$file').writeAsBytes(scan.cutoutPng, flush: true);

    try {
      final row = await _guard(
        () => _client
            .from(_table)
            .insert({
              'name': _name(scan, name),
              'label': scan.label,
              'category': scan.category.id,
              'color_name': scan.colorName,
              'dominant_color': scan.dominantHex,
              'formality': scan.formality,
              'confidence': scan.confidence,
              'image_file': file,
            })
            .select()
            .single(),
      );
      return _toItem(row, dir);
    } catch (_) {
      // No row means the local cutout is orphaned; drop it.
      File('$dir/$file').delete().ignore();
      rethrow;
    }
  }

  @override
  Future<void> remove(String id) async {
    final row = await _guard(
      () =>
          _client.from(_table).select('image_file').eq('id', id).maybeSingle(),
    );
    await _guard(() => _client.from(_table).delete().eq('id', id));

    final file = row?['image_file'] as String?;
    if (file != null && file.isNotEmpty) {
      File('${await _cutoutDir()}/$file').delete().ignore();
    }
  }

  /// Absolute path of a stored cutout; empty when the row has no file.
  Future<String> _cutoutDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/$_dir');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir.path;
  }

  WardrobeItem _toItem(Map<String, dynamic> row, String dir) {
    final file = row['image_file'] as String? ?? '';
    final formality = (row['formality'] as num?)?.toInt() ?? 3;
    return WardrobeItem(
      id: row['id'] as String,
      name: row['name'] as String,
      label: row['label'] as String? ?? '',
      category: row['category'] as String,
      imagePath: file.isEmpty ? '' : '$dir/$file',
      colorName: row['color_name'] as String? ?? '',
      color: _hexColor(row['dominant_color'] as String?),
      formality: formality,
      // ponytail: the scanner reports formality, not occasions, so the chip
      // filter is derived from it. Add an `occasions text[]` column when ML
      // starts emitting them.
      occasions: _occasionsFor(formality),
      confidence: (row['confidence'] as num?)?.toDouble(),
    );
  }

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on sb.PostgrestException catch (e) {
      throw WardrobeException(_friendly(e.message));
    }
  }

  static String _friendly(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('row-level security') || lower.contains('violates')) {
      return 'Tidak diizinkan menyimpan item ini.';
    }
    if (lower.contains('jwt') || lower.contains('expired')) {
      return 'Sesi habis, masuk ulang.';
    }
    return message;
  }
}

const _occasionByFormality = {
  1: ['Kasual', 'Sport'],
  2: ['Kasual', 'Sport'],
  3: ['Kasual', 'Smart-Casual'],
  4: ['Formal', 'Smart-Casual'],
  5: ['Formal'],
};

List<String> _occasionsFor(int formality) =>
    _occasionByFormality[formality.clamp(1, 5)]!;

String _name(ScanResult scan, String? override) {
  final name = (override ?? scan.suggestedName).trim();
  return name.isEmpty ? scan.label : name;
}

/// `#RRGGBB` back to a Color; a malformed value falls back to the app's tan.
Color _hexColor(String? value) {
  final digits = (value ?? '').replaceFirst('#', '');
  final parsed = digits.length == 6 ? int.tryParse(digits, radix: 16) : null;
  return parsed == null ? const Color(0xFFD3A277) : Color(0xFF000000 | parsed);
}

WardrobeService _wardrobe = DemoWardrobeService();

/// The wardrobe backend the screens talk to. Defaults to [DemoWardrobeService];
/// [main] swaps in [SupabaseWardrobeService] when credentials are compiled in.
WardrobeService get wardrobeService => _wardrobe;

/// Swaps the backend; called once from [main] before the first frame.
void useWardrobeService(WardrobeService service) => _wardrobe = service;

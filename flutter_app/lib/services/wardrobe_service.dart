import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../logic/garment_defaults.dart';
import '../logic/ids.dart';
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

  /// Stores what the scanner review screen built, including its cutout image.
  Future<WardrobeItem> save(WardrobeItem item);

  /// Stores a bare [ScanResult], writing its PNG first. Kept for callers that
  /// have no [WardrobeItem] yet (tests); the screens use [save].
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
  Future<WardrobeItem> save(WardrobeItem item) async {
    _items.add(item);
    return item;
  }

  @override
  Future<WardrobeItem> add(ScanResult scan, {String? name}) => save(
    WardrobeItem(
      id: 'demo-${++_seq}',
      name: _name(scan, name),
      label: scan.label,
      category: scan.category.id,
      subcategory: scan.label,
      imagePath: '',
      colorName: scan.colorName,
      color: scan.dominantColor,
      formality: scan.formality,
      occasions: defaultOccasions(scan.category.id),
      confidence: scan.confidence,
    ),
  );

  @override
  Future<void> remove(String id) async =>
      _items.removeWhere((item) => item.id == id);
}

/// Postgres and Supabase Storage. `wardrobe_items.image_url` is always the
/// complete public URL of the corresponding object in `cutouts`.
class SupabaseWardrobeService implements WardrobeService {
  SupabaseWardrobeService(this._client);

  final sb.SupabaseClient _client;

  static const _table = 'wardrobe_items';
  static const _dir = wardrobeCutoutDirName;

  @override
  Future<List<WardrobeItem>> items() async {
    final rows = await _guard(
      () => _client.from(_table).select().order('created_at', ascending: false),
    );
    final userId = _client.auth.currentUser?.id;
    return Future.wait(
      rows.map(
        (row) => _restoreLegacyImage(Map<String, dynamic>.from(row), userId),
      ),
    );
  }

  @override
  Future<WardrobeItem> save(WardrobeItem item) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw const WardrobeException(
        'Sesi login tidak ditemukan. Silakan masuk ulang.',
      );
    }
    final imageUrl = await _uploadImage(item.imagePath, userId);
    final row = await _guard(
      () => _client
          .from(_table)
          .insert({
            // Same id on the device and in Postgres (uuid v4), so the cached
            // row and its cloud row never drift.
            if (item.id.isNotEmpty) 'id': item.id,
            'name': item.name,
            'label': item.label.isEmpty ? (item.subcategory ?? '') : item.label,
            'category': item.category,
            'subcategory': item.subcategory ?? item.label,
            'brand': item.brand,
            'color_name': item.colorName,
            'dominant_color': _hex(item.color),
            'formality': item.formality,
            'occasions': item.occasions.isEmpty
                ? defaultOccasions(item.category)
                : item.occasions,
            'confidence': item.confidence,
            'image_url': imageUrl,
          })
          .select()
          .single(),
    );
    return _toItem(row);
  }

  @override
  Future<WardrobeItem> add(ScanResult scan, {String? name}) async {
    final dir = await _cutoutDir();
    final id = newWardrobeItemId();
    final file = '$id.png';
    await File('$dir/$file').writeAsBytes(scan.cutoutPng, flush: true);

    try {
      return await save(
        WardrobeItem(
          id: id,
          name: _name(scan, name),
          label: scan.label,
          category: scan.category.id,
          subcategory: scan.label,
          imagePath: '$dir/$file',
          colorName: scan.colorName,
          color: scan.dominantColor,
          formality: scan.formality,
          occasions: defaultOccasions(scan.category.id),
          confidence: scan.confidence,
        ),
      );
    } catch (_) {
      // No row means the local cutout is orphaned; drop it.
      File('$dir/$file').delete().ignore();
      rethrow;
    }
  }

  @override
  Future<void> remove(String id) async {
    final row = await _guard(
      () => _client.from(_table).select('image_url').eq('id', id).maybeSingle(),
    );
    await _guard(() => _client.from(_table).delete().eq('id', id));

    final imageUrl = row?['image_url'] as String?;
    final storagePath = _storagePathFromUrl(imageUrl);
    if (storagePath != null) {
      await _storageGuard(
        () => _client.storage.from(_bucket).remove([storagePath]),
      );
    }
  }

  static const _bucket = 'cutouts';

  Future<String> _uploadImage(String imagePath, String userId) async {
    final uri = Uri.tryParse(imagePath);
    final isUrl =
        uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
    if (imagePath.isEmpty || isUrl) {
      return imagePath;
    }
    final file = File(imagePath);
    if (!await file.exists()) {
      throw WardrobeException('File hasil scan tidak ditemukan: $imagePath');
    }
    final fileName = _basename(imagePath);
    final storagePath = '$userId/$fileName';
    try {
      await _client.storage
          .from(_bucket)
          .upload(
            storagePath,
            file,
            fileOptions: const sb.FileOptions(
              cacheControl: '3600',
              upsert: true,
              contentType: 'image/png',
            ),
          );
      final publicUrl = _client.storage.from(_bucket).getPublicUrl(storagePath);
      if (!publicUrl.startsWith('https://')) {
        throw const WardrobeException(
          'Supabase mengembalikan URL gambar yang tidak valid.',
        );
      }
      return publicUrl;
    } on sb.StorageException catch (e, stack) {
      debugPrint('Supabase Storage upload failed ($storagePath): ${e.message}');
      debugPrint('$stack');
      throw WardrobeException(_friendly(e.message));
    }
  }

  /// Absolute path of a temporary cutout; used only before upload.
  Future<String> _cutoutDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/$_dir');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir.path;
  }

  Future<WardrobeItem> _restoreLegacyImage(
    Map<String, dynamic> row,
    String? userId,
  ) async {
    final imageUrl = row['image_url'] as String? ?? '';
    if (imageUrl.isNotEmpty) return _toItem(row);

    final legacyName = row['image_file'] as String? ?? '';
    if (legacyName.isEmpty) {
      debugPrint('Wardrobe item ${row['id']} has no image_url.');
      return _toItem(row);
    }

    final docs = await getApplicationDocumentsDirectory();
    final candidates = [
      '${docs.path}/cutouts/$legacyName',
      '${docs.path}/garments/$legacyName',
    ];
    for (final path in candidates) {
      if (!await File(path).exists()) continue;
      if (userId == null) {
        row['image_url'] = path;
        return _toItem(row);
      }
      try {
        final restoredUrl = await _uploadImage(path, userId);
        await _guard(
          () => _client
              .from(_table)
              .update({'image_url': restoredUrl})
              .eq('id', row['id']),
        );
        row['image_url'] = restoredUrl;
        debugPrint('Restored legacy wardrobe image ${row['id']} from $path');
      } catch (error, stack) {
        debugPrint('Could not restore wardrobe image ${row['id']}: $error');
        debugPrint('$stack');
        row['image_url'] = path;
      }
      return _toItem(row);
    }

    debugPrint(
      'Wardrobe item ${row['id']} references missing local image $legacyName.',
    );
    return _toItem(row);
  }

  WardrobeItem _toItem(Map<String, dynamic> row) {
    final imageUrl = row['image_url'] as String? ?? '';
    final category = row['category'] as String;
    final subcategory = row['subcategory'] as String? ?? '';
    final occasions = (row['occasions'] as List?)?.cast<String>() ?? const [];
    return WardrobeItem(
      id: row['id'] as String,
      name: row['name'] as String,
      label: row['label'] as String? ?? '',
      category: category,
      subcategory: subcategory.isEmpty ? null : subcategory,
      brand: row['brand'] as String? ?? '',
      imagePath: imageUrl,
      colorName: row['color_name'] as String? ?? '',
      color: _hexColor(row['dominant_color'] as String?),
      formality: (row['formality'] as num?)?.toInt() ?? 3,
      // A row written before the `occasions` column falls back to the same
      // default the scanner applies, so old and new items match alike.
      occasions: occasions.isEmpty ? defaultOccasions(category) : occasions,
      confidence: (row['confidence'] as num?)?.toDouble(),
    );
  }

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on sb.PostgrestException catch (e) {
      debugPrint('Supabase database request failed: ${e.message}');
      throw WardrobeException(_friendly(e.message));
    }
  }

  Future<T> _storageGuard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on sb.StorageException catch (e, stack) {
      debugPrint('Supabase Storage request failed: ${e.message}');
      debugPrint('$stack');
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

String? _storagePathFromUrl(String? value) {
  if (value == null || value.isEmpty) return null;
  final uri = Uri.tryParse(value);
  if (uri == null) return null;
  final segments = uri.pathSegments;
  final bucketIndex = segments.indexOf('cutouts');
  if (bucketIndex == -1 || bucketIndex == segments.length - 1) return null;
  return segments.sublist(bucketIndex + 1).join('/');
}

String _name(ScanResult scan, String? override) {
  final name = (override ?? scan.suggestedName).trim();
  return name.isEmpty ? scan.label : name;
}

String _basename(String path) =>
    path.isEmpty ? '' : path.split(RegExp(r'[\\/]')).last;

/// Color to the `#RRGGBB` the dominant_color check accepts.
String _hex(Color color) {
  final value = color.toARGB32() & 0xFFFFFF;
  return '#${value.toRadixString(16).padLeft(6, '0').toUpperCase()}';
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

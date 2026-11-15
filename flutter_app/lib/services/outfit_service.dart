import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../logic/ids.dart';
import '../models/outfit.dart';

class OutfitException implements Exception {
  const OutfitException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract class OutfitService {
  Future<List<SavedOutfit>> outfits();

  Future<SavedOutfit> save(SavedOutfit outfit);

  Future<void> remove(String id);
}

abstract class PlannerService {
  Future<List<PlannerEntry>> entries();

  Future<PlannerEntry> save(PlannerEntry entry);

  Future<void> remove(DateTime day);
}

class DemoOutfitService implements OutfitService {
  final _outfits = <SavedOutfit>[];

  @override
  Future<List<SavedOutfit>> outfits() async => List.unmodifiable(_outfits);

  @override
  Future<SavedOutfit> save(SavedOutfit outfit) async {
    final toSave = outfit.id.isEmpty
        ? SavedOutfit(
            id: newWardrobeItemId(),
            name: outfit.name,
            itemIds: outfit.itemIds,
            threshold: outfit.threshold,
            favorite: outfit.favorite,
            createdAt: outfit.createdAt ?? DateTime.now(),
          )
        : outfit;

    _outfits
      ..removeWhere((o) => o.id == toSave.id)
      ..add(toSave);
    return toSave;
  }

  @override
  Future<void> remove(String id) async =>
      _outfits.removeWhere((o) => o.id == id);
}

class DemoPlannerService implements PlannerService {
  final _entries = <DateTime, PlannerEntry>{};

  @override
  Future<List<PlannerEntry>> entries() async => List.unmodifiable(
        _entries.values.toList()..sort((a, b) => a.day.compareTo(b.day)),
      );

  @override
  Future<PlannerEntry> save(PlannerEntry entry) async {
    _entries[_day(entry.day)] = entry;
    return entry;
  }

  @override
  Future<void> remove(DateTime day) async => _entries.remove(_day(day));
}

class SupabaseOutfitService implements OutfitService {
  SupabaseOutfitService(this._client);

  final sb.SupabaseClient _client;

  static const _table = 'outfit_looks';

  @override
  Future<List<SavedOutfit>> outfits() async {
    final rows = await _guard(
      () => _client.from(_table).select().order('created_at', ascending: false),
    );
    return rows.map(_toOutfit).toList();
  }

  Future<List<SavedOutfit>> favorites() async {
    final rows = await _guard(
      () => _client
          .from(_table)
          .select()
          .eq('favorite', true)
          .order('created_at', ascending: false),
    );
    return rows.map(_toOutfit).toList();
  }

  Future<SavedOutfit?> getById(String id) async {
    final row = await _guard(
      () => _client.from(_table).select().eq('id', id).maybeSingle(),
    );
    return row == null ? null : _toOutfit(row);
  }

  @override
  Future<SavedOutfit> save(SavedOutfit outfit) async {
    final id = outfit.id.isNotEmpty ? outfit.id : newWardrobeItemId();
    final row = await _guard(
      () => _client
          .from(_table)
          .upsert({
            'id': id,
            'name': outfit.name,
            'item_ids': outfit.itemIds,
            'threshold': outfit.threshold,
            'favorite': outfit.favorite,
          })
          .select()
          .single(),
    );
    return _toOutfit(row);
  }

  Future<void> setFavorite(String id, bool favorite) => _guard(
        () => _client.from(_table).update({'favorite': favorite}).eq('id', id),
      );

  @override
  Future<void> remove(String id) =>
      _guard(() => _client.from(_table).delete().eq('id', id));
}

class SupabasePlannerService implements PlannerService {
  SupabasePlannerService(this._client);

  final sb.SupabaseClient _client;

  static const _table = 'planner_entries';

  @override
  Future<List<PlannerEntry>> entries() async {
    final rows = await _guard(
      () => _client.from(_table).select().order('day', ascending: true),
    );
    return rows.map(_toEntry).toList();
  }

  Future<PlannerEntry?> entryForDay(DateTime day) async {
    final row = await _guard(
      () => _client.from(_table).select().eq('day', _isoDay(day)).maybeSingle(),
    );
    return row == null ? null : _toEntry(row);
  }

  @override
  Future<PlannerEntry> save(PlannerEntry entry) async {
    final row = await _guard(
      () => _client
          .from(_table)
          .upsert({
            'id': newWardrobeItemId(),
            'day': _isoDay(entry.day),
            'outfit_id': entry.outfitId,
            'occasion': entry.occasion,
            'complete': entry.complete,
          }, onConflict: 'owner_id,day')
          .select()
          .single(),
    );
    return _toEntry(row);
  }

  Future<void> setComplete(DateTime day, bool complete) => _guard(
        () => _client
            .from(_table)
            .update({'complete': complete})
            .eq('day', _isoDay(day)),
      );

  @override
  Future<void> remove(DateTime day) =>
      _guard(() => _client.from(_table).delete().eq('day', _isoDay(day)));
}

SavedOutfit _toOutfit(Map<String, dynamic> row) => SavedOutfit(
      id: row['id'] as String,
      name: row['name'] as String? ?? '',
      itemIds: [
        for (final id in (row['item_ids'] as List? ?? const [])) id as String,
      ],
      threshold: (row['threshold'] as num?)?.toDouble() ?? 0.6,
      favorite: row['favorite'] as bool? ?? false,
      createdAt: DateTime.tryParse(row['created_at'] as String? ?? '')?.toLocal(),
    );

PlannerEntry _toEntry(Map<String, dynamic> row) => PlannerEntry(
      day: DateTime.parse(row['day'] as String),
      outfitId: row['outfit_id'] as String,
      occasion: row['occasion'] as String? ?? '',
      complete: row['complete'] as bool? ?? false,
    );

String _isoDay(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

DateTime _day(DateTime value) => DateTime(value.year, value.month, value.day);

Future<T> _guard<T>(Future<T> Function() call) async {
  try {
    return await call();
  } on sb.PostgrestException catch (e) {
    throw OutfitException(_friendly(e.message));
  }
}

String _friendly(String message) {
  final lower = message.toLowerCase();
  if (lower.contains('row-level security') || lower.contains('violates')) {
    return 'Tidak diizinkan menyimpan kombinasi ini.';
  }
  if (lower.contains('jwt') || lower.contains('expired')) {
    return 'Sesi habis, masuk ulang.';
  }
  if (lower.contains('does not exist') || lower.contains('schema cache')) {
    return 'Tabel kombinasi belum ada di Supabase.';
  }
  return message;
}

OutfitService _outfits = DemoOutfitService();
PlannerService _planner = DemoPlannerService();

OutfitService get outfitService {
  if (_outfits is DemoOutfitService) {
    try {
      final client = sb.Supabase.instance.client;
      _outfits = SupabaseOutfitService(client);
    } catch (_) {}
  }
  return _outfits;
}

PlannerService get plannerService {
  if (_planner is DemoPlannerService) {
    try {
      final client = sb.Supabase.instance.client;
      _planner = SupabasePlannerService(client);
    } catch (_) {}
  }
  return _planner;
}

void useOutfitService(OutfitService service) => _outfits = service;

void usePlannerService(PlannerService service) => _planner = service;

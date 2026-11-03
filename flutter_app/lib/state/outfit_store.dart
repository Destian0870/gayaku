import 'package:flutter/foundation.dart';

import '../models/wardrobe.dart';

/// A user-built combination of items, kept in memory for the session.
///
/// ponytail: no persistence — swap the notifier for Supabase/REST when the
/// backend lands (proposal §6.1). The screen only talks to this store.
class SavedOutfit {
  SavedOutfit({
    required this.id,
    required this.name,
    required this.itemIds,
    required this.threshold,
    this.favorite = false,
  });

  final String id;
  String name;

  /// [WardrobeItem.id]s, in slot order. Ids — not names — so renaming a
  /// garment keeps every combination that contains it intact
  /// (docs/adr/0004-sqlite-ids.md).
  List<String> itemIds;

  /// Minimum match percent the user wants, 0..1.
  double threshold;

  /// Favourites sort first in the wardrobe's Kombinasi tab.
  bool favorite;

  /// Resolves [itemIds] against [catalog], dropping ids that no longer exist.
  List<WardrobeItem> itemsOf(List<WardrobeItem> catalog) => [
    for (final id in itemIds) ...catalog.where((i) => i.id == id),
  ];
}

/// Every saved combination, newest first. Listen to it with
/// [ValueListenableBuilder] to rebuild on add/edit/delete.
final savedOutfits = ValueNotifier<List<SavedOutfit>>([]);

String newOutfitId() => DateTime.now().microsecondsSinceEpoch.toString();

void saveOutfit(SavedOutfit outfit) {
  final next = [...savedOutfits.value];
  final at = next.indexWhere((o) => o.id == outfit.id);
  if (at == -1) {
    next.insert(0, outfit);
  } else {
    next[at] = outfit;
  }
  savedOutfits.value = next;
}

void deleteOutfit(String id) {
  savedOutfits.value = savedOutfits.value.where((o) => o.id != id).toList();
}

/// Flips the favourite flag of one combination and re-notifies listeners.
void toggleOutfitFavorite(String id) {
  final next = [...savedOutfits.value];
  final at = next.indexWhere((o) => o.id == id);
  if (at == -1) return;
  next[at].favorite = !next[at].favorite;
  savedOutfits.value = next;
}

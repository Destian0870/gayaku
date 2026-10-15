# Scanned garments live in SQLite, keyed by id

A saved WardrobeItem is a row in a local SQLite database (`sqflite`) with a generated id, and its Cutout is a PNG in the app documents directory. `WardrobeItem` gains `id` and `subcategory`, and saved combinations store item ids instead of item names — the name-keyed store resolved items by name (`lib/state/outfit_store.dart:31`), so renaming a garment silently emptied any combination containing it. The nine demo garments seed the table on first run.

## Considered options

- **In-memory `ValueNotifier`**, as `savedOutfits` works today: every scanned garment would vanish on restart, which fails the real-use bar this work targets.
- **A JSON file**: fewer moving parts, but no schema to migrate and nothing to query once the wardrobe filters and the planner read the same data.

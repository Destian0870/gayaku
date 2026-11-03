# Supabase backend

Auth, profiles, wardrobe items and their images for GAYAKU. Saved looks and
the weekly planner are still in memory in the app.

```
supabase/
  migrations/20261024120000_profiles.sql        profiles table, RLS, sign-up trigger
  migrations/20261024120100_avatars_bucket.sql  private avatars bucket, per-user rules
  migrations/20261103090000_wardrobe_items.sql  scanned garments + private cutouts bucket
```

## What the app talks to

Two files import the Supabase SDK, one per concern; screens never import it:

- `flutter_app/lib/services/auth_service.dart` — `AuthService`, with
  `DemoAuthService` by default (accepts any credentials, no network) and
  `SupabaseAuthService` when `SUPABASE_URL` + `SUPABASE_PUBLISHABLE_KEY` are
  compiled in. `main()` installs it before the first frame.
- `flutter_app/lib/services/wardrobe_service.dart` — `WardrobeService`
  (`items()`, `add(ScanResult)`, `remove(id)`), with the same Demo/Supabase
  pair. `SupabaseWardrobeService` uploads the cutout PNG to `cutouts/<uid>/…`
  and inserts the row.

| Screen | Call |
| --- | --- |
| `login_screen.dart` | `authService.signIn(email:, password:)` |
| `register_screen.dart` | `authService.signUp(email:, password:, displayName:)` |
| `profile_screen.dart` | `authService.currentUser`, `authService.signOut()` |
| wardrobe screens (next) | `wardrobeService.items()`, `.add(scan)`, `.remove(id)` |

`AuthException.message` / `WardrobeException.message` are shown in a SnackBar
as-is, so the mapping from Supabase's English errors to Indonesian copy lives in
`_friendly()`.

## What one scan stores

`ScanResult` (`flutter_app/lib/models/scan_result.dart`) is the contract the
scanner emits. It maps one-to-one onto the table:

| ScanResult | `wardrobe_items` column | Notes |
| --- | --- | --- |
| `cutoutPng` | — (Storage object) | `cutouts/<uid>/<microseconds>.png`, private bucket |
| `label` | `label` text | one of the 18 classes in `labels.json`, free text in SQL |
| `category` | `category` text | check: `Tops`, `Bottoms`, `Outerwear`, `Shoes`, `Accessories` |
| `suggestedName` (or the corrected name) | `name` text | 1–80 chars, trimmed |
| `confidence` | `confidence` real | 0..1, nullable |
| `colorName` | `color_name` text | K-Means label, e.g. `Putih` |
| `dominantColor` | `dominant_color` text | `#RRGGBB`, check-constrained |
| `formality` | `formality` smallint | 1..5, seeded from category |

`owner_id` defaults to `auth.uid()` and every policy tests it, so a client can
neither insert for someone else nor read another user's wardrobe. Images are
private; `items()` hands back a 1-hour signed URL.

## First-time setup

1. Create a project at <https://supabase.com/dashboard> (free tier). Note the
   project ref, the API URL and the **publishable** key from *Project Settings →
   API keys* (older projects call it the **anon** key — same slot, same
   behaviour). That key is public by design; RLS is what protects the data.
   Never ship the `secret` / `service_role` key.
2. Apply the migrations. Either paste all three files from `migrations/` into the
   dashboard SQL editor in filename order, or use the CLI:

   ```bash
   npx supabase login
   npx supabase link --project-ref <project-ref>
   npx supabase db push
   ```

3. Run the app with the credentials:

   ```bash
   cd flutter_app
   flutter run --dart-define=SUPABASE_URL=https://<project-ref>.supabase.co \
               --dart-define=SUPABASE_PUBLISHABLE_KEY=<publishable-key>
   ```

   Add the same two `--dart-define` flags to `flutter build apk --release`. A
   build without them silently runs the demo backend.

## Verifying it works

- Sign up in the app, then check *Table Editor → profiles*: one row, with
  `display_name` taken from the sign-up form.
- *Authentication → Users* shows the new user; `email_confirmed_at` is null
  until the confirmation link is clicked, which is why sign-up with email
  confirmation enabled returns to the Sign In screen with a hint.
- In the SQL editor, `select * from profiles;` as the `anon` role returns
  nothing — that is RLS working, not a bug.
- A scan (once the scanner is wired to `wardrobeService.add`) shows up in
  *Table Editor → wardrobe_items* with `label`, `category`, `dominant_color` and
  `confidence` filled, and *Storage → cutouts → <uid>* holds the PNG.

## Not covered yet

- Google Sign-In. The button says it is not connected; it needs an OAuth client
  and a redirect URL in the dashboard plus `signInWithOAuth` in
  `SupabaseAuthService`.
- Avatar upload. The bucket and policies exist, no screen writes to it.
- The scan UI itself. `WardrobeService.add(ScanResult)` is ready and tested
  against the demo backend, but no screen captures a photo or runs the model
  yet, and the Wardrobe grid still renders the static catalog.
- Saved looks, favourites, weekly planner. Their tables wait until the matching
  rules settle; `wardrobe_items` is what a look will reference.
- `occasions` (Formal/Kasual/Smart-Casual/Sport) is not a column: it is derived
  from `category` by `outfit_matcher`, so it stays client-side for now.
- Offline caching and session refresh UI. `supabase_flutter` persists the
  session on disk and refreshes tokens on its own.

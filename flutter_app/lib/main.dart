import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/login_screen.dart';
import 'services/auth_service.dart';
import 'services/wardrobe_service.dart';
import 'state/wardrobe_store.dart';
import 'state/wardrobe_sync.dart';
import 'theme/app_theme.dart';

/// Compile-time credentials, so no secret ever sits in the repo:
/// `flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_PUBLISHABLE_KEY=...`
/// See `supabase/README.md`. The key is the public one (a legacy anon key works
/// in the same slot); RLS, not secrecy, is what protects the data.
const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Fonts ship in assets/google_fonts/. Failing loudly beats silently fetching a
  // different face at runtime.
  GoogleFonts.config.allowRuntimeFetching = false;

  // The wardrobe is a database, not a constant: read it before the first frame
  // so the home and wardrobe screens never flash an empty catalog.
  await initWardrobeStore();

  // ponytail: SQLite is what the screens read today; Supabase is the shared
  // copy behind the same service seam. Without credentials the app runs on
  // DemoAuthService/DemoWardrobeService, so the UI still works before a
  // project exists - see supabase/README.md for the switch-over.
  if (_supabaseUrl.isNotEmpty && _supabaseKey.isNotEmpty) {
    await Supabase.initialize(url: _supabaseUrl, publishableKey: _supabaseKey);
    final client = Supabase.instance.client;
    useAuthService(SupabaseAuthService(client));
    useWardrobeService(SupabaseWardrobeService(client));
  }

  // Supabase is the shared wardrobe; the SQLite rows are the offline copy. With
  // no credentials this is a no-op and the cache is all there is.
  await loadWardrobeFromBackend();

  runApp(const GayakuApp());
}

class GayakuApp extends StatelessWidget {
  const GayakuApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gayaku',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      home: const LoginScreen(),
    );
  }
}

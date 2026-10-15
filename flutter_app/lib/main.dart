import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'screens/login_screen.dart';
import 'state/wardrobe_store.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Fonts ship in assets/google_fonts/. Failing loudly beats silently fetching a
  // different face at runtime.
  GoogleFonts.config.allowRuntimeFetching = false;
  // The wardrobe is a database, not a constant: read it before the first frame
  // so the home and wardrobe screens never flash an empty catalog.
  await initWardrobeStore();
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

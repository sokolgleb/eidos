import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/settings_service.dart';
import 'utils/app_theme.dart';
import 'screens/main_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://qoyoaavciqzwdboiuzow.supabase.co',
    anonKey: 'sb_publishable_l3e-D-0pYx1jRq-vDu3q4w_0La9756H',
  );

  runApp(const EidosApp());
}

class EidosApp extends StatefulWidget {
  const EidosApp({super.key});

  @override
  State<EidosApp> createState() => _EidosAppState();
}

class _EidosAppState extends State<EidosApp> {
  ThemeMode _themeMode = ThemeMode.dark;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final mode = await SettingsService.getThemeMode();
    if (mounted) setState(() => _themeMode = mode);
  }

  void _onThemeChanged() => _loadTheme();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Eidos',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: MainShell(onThemeChanged: _onThemeChanged),
    );
  }
}

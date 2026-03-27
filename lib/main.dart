import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/gallery_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://qoyoaavciqzwdboiuzow.supabase.co',
    anonKey: 'sb_publishable_l3e-D-0pYx1jRq-vDu3q4w_0La9756H',
  );

  runApp(const EidosApp());
}

class EidosApp extends StatelessWidget {
  const EidosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Eidos',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        colorScheme: const ColorScheme.dark(),
      ),
      home: const GalleryScreen(),
    );
  }
}

import 'package:flutter/material.dart';
import 'screens/gallery_screen.dart';

void main() {
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

import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/sighting.dart';

class SightingStorage {
  static const _key = 'sightings';

  static Future<Directory> _sightingsDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/sightings');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<String> sightingDir(String id) async {
    final base = await _sightingsDir();
    final dir = Directory('${base.path}/$id');
    if (!await dir.exists()) await dir.create();
    return dir.path;
  }

  static Future<List<Sighting>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final docs = await getApplicationDocumentsDirectory();
    final raw = prefs.getStringList(_key) ?? [];
    return raw
        .map((s) => Sighting.fromJson(
            jsonDecode(s) as Map<String, dynamic>, docs.path))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  static Future<void> save(Sighting sighting) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    raw.add(jsonEncode(sighting.toJson()));
    await prefs.setStringList(_key, raw);
  }

  static Future<void> delete(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    raw.removeWhere((s) {
      final map = jsonDecode(s) as Map<String, dynamic>;
      return map['id'] == id;
    });
    await prefs.setStringList(_key, raw);

    // Delete files
    final base = await _sightingsDir();
    final dir = Directory('${base.path}/$id');
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}

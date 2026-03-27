import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/sighting.dart';

class CloudService {
  static SupabaseClient get _db => Supabase.instance.client;

  // ── Auth ──────────────────────────────────────────────────────────────────

  static Future<void> ensureSignedIn() async {
    if (_db.auth.currentUser != null) return;
    await _db.auth.signInAnonymously();
  }

  static String? get userId => _db.auth.currentUser?.id;

  // ── Upload ────────────────────────────────────────────────────────────────

  /// Uploads both images and inserts a record in Supabase.
  /// Returns the updated Sighting with remote URLs, or null on failure.
  static Future<Sighting?> uploadSighting(Sighting sighting) async {
    try {
      await ensureSignedIn();
      final uid = userId;
      if (uid == null) return null;

      // Get presigned URLs for both files
      final origUrl = await _presignedPut(sighting.id, 'original');
      final annUrl  = await _presignedPut(sighting.id, 'annotated');
      if (origUrl == null || annUrl == null) return null;

      // Upload files to R2
      await _putFile(origUrl['uploadUrl']!, File(sighting.originalPath), 'image/jpeg');
      await _putFile(annUrl['uploadUrl']!,  File(sighting.annotatedPath),  'image/png');

      final updated = sighting.copyWith(
        originalUrl: origUrl['publicUrl'],
        annotatedUrl: annUrl['publicUrl'],
        syncStatus: SyncStatus.synced,
      );

      // Insert into Supabase DB
      await _db.from('sightings').upsert(updated.toSupabase(uid));

      return updated;
    } catch (e) {
      return null;
    }
  }

  /// Fetches all sightings for the current user from Supabase.
  static Future<List<Sighting>> fetchRemoteSightings() async {
    try {
      await ensureSignedIn();
      final rows = await _db
          .from('sightings')
          .select()
          .order('created_at', ascending: false);
      return rows.map((r) => Sighting.fromSupabase(r)).toList();
    } catch (_) {
      return [];
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static Future<Map<String, String>?> _presignedPut(
      String sightingId, String fileType) async {
    try {
      final res = await _db.functions.invoke(
        'r2-presigned-url',
        body: {'sightingId': sightingId, 'fileType': fileType},
      );
      final data = res.data as Map<String, dynamic>;
      return {
        'uploadUrl': data['uploadUrl'] as String,
        'publicUrl': data['publicUrl'] as String,
      };
    } catch (_) {
      return null;
    }
  }

  static Future<void> _putFile(
      String url, File file, String contentType) async {
    final bytes = await file.readAsBytes();
    final client = HttpClient();
    try {
      final req = await client.putUrl(Uri.parse(url));
      req.headers.set('Content-Type', contentType);
      req.headers.contentLength = bytes.length;
      req.add(bytes);
      final resp = await req.close();
      if (resp.statusCode >= 300) {
        throw Exception('R2 PUT failed: ${resp.statusCode}');
      }
    } finally {
      client.close();
    }
  }
}

import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/sighting.dart';
import 'device_info_service.dart';

class CloudService {
  static SupabaseClient get _db => Supabase.instance.client;

  // ── Auth ──────────────────────────────────────────────────────────────────

  static Future<void> ensureSignedIn() async {
    if (_db.auth.currentUser != null) return;
    await _db.auth.signInAnonymously();
  }

  static String? get userId => _db.auth.currentUser?.id;

  // ── Profile sync ──────────────────────────────────────────────────────────

  /// Upserts the user's profile with current device metadata.
  /// Safe to call fire-and-forget; all errors are swallowed.
  static Future<void> syncProfile() async {
    try {
      await ensureSignedIn();
      final uid = userId;
      if (uid == null) return;

      final version  = await DeviceInfoService.getAppVersion();
      final platform = DeviceInfoService.platform;
      final loc      = await DeviceInfoService.getLocation();

      // Fetch current state so we can handle one-time fields
      final row = await _db
          .from('profiles')
          .select('platforms, language')
          .eq('id', uid)
          .maybeSingle();

      final currentPlatforms =
          (row?['platforms'] as List?)?.cast<String>() ?? [];

      await _db.from('profiles').upsert({
        'id':          uid,
        'app_version': version,
        if (loc.ip   != null) 'ip':   loc.ip,
        if (loc.iso2 != null) 'iso2': loc.iso2,
        // Append platform only if not already present
        'platforms': currentPlatforms.contains(platform)
            ? currentPlatforms
            : [...currentPlatforms, platform],
        // Language is set once — DB trigger preserves it on subsequent updates,
        // but we also skip it here to avoid the upsert touching it at all.
        if (row?['language'] == null) 'language': DeviceInfoService.language,
      });
    } catch (_) {
      // Non-fatal
    }
  }

  // ── Upload ────────────────────────────────────────────────────────────────

  /// Uploads both images and inserts a record in Supabase.
  /// Returns the updated Sighting with remote URLs, or null on failure.
  static Future<Sighting?> uploadSighting(Sighting sighting) async {
    try {
      await ensureSignedIn();
      final uid = userId;
      if (uid == null) return null;

      // Get presigned URLs for both files in a single Edge Function call
      final urls = await _presignedPuts(sighting.id);
      if (urls == null) return null;
      final origUrl = urls['original']!;
      final annUrl  = urls['annotated']!;

      // Upload both files to R2 in parallel
      await Future.wait([
        _putFile(origUrl['uploadUrl']!, File(sighting.originalPath), 'image/jpeg'),
        _putFile(annUrl['uploadUrl']!,  File(sighting.annotatedPath), 'image/png'),
      ]);

      final updated = sighting.copyWith(
        originalUrl: origUrl['publicUrl'],
        annotatedUrl: annUrl['publicUrl'],
        syncStatus: SyncStatus.synced,
      );

      // Fetch location (cached after first call)
      final loc = await DeviceInfoService.getLocation();

      // Insert into Supabase DB
      await _db.from('sightings').upsert({
        ...updated.toSupabase(uid),
        if (loc.ip   != null) 'ip':   loc.ip,
        if (loc.iso2 != null) 'iso2': loc.iso2,
      });

      return updated;
    } catch (e) {
      return null;
    }
  }

  /// Fetches all active sightings for the current user from Supabase.
  static Future<List<Sighting>> fetchRemoteSightings() async {
    try {
      await ensureSignedIn();
      final rows = await _db
          .from('sightings')
          .select()
          .eq('status', 'active')
          .order('created_at', ascending: false);
      return rows.map((r) => Sighting.fromSupabase(r)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Returns the set of active sighting IDs from the remote.
  /// Returns null on network / auth error so callers can skip reconciliation.
  static Future<Set<String>?> fetchRemoteSightingIds() async {
    try {
      await ensureSignedIn();
      final rows = await _db
          .from('sightings')
          .select('id')
          .eq('status', 'active');
      return {for (final r in rows) r['id'] as String};
    } catch (_) {
      return null;
    }
  }

  /// Soft-deletes a sighting (sets status = 'deleted').
  /// Hard deletion happens automatically after 7 days via a scheduled DB job.
  static Future<void> deleteSighting(String id) async {
    try {
      await ensureSignedIn();
      await _db.from('sightings').update({'status': 'deleted'}).eq('id', id);
    } catch (_) {}
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Returns { 'original': {uploadUrl, publicUrl}, 'annotated': {uploadUrl, publicUrl} }
  static Future<Map<String, Map<String, String>>?> _presignedPuts(
      String sightingId) async {
    try {
      final res = await _db.functions.invoke(
        'r2-presigned-url',
        body: {'sightingId': sightingId},
      );
      final data = res.data as Map<String, dynamic>;
      Map<String, String> parse(dynamic v) {
        final m = v as Map<String, dynamic>;
        return {'uploadUrl': m['uploadUrl'] as String, 'publicUrl': m['publicUrl'] as String};
      }
      return {
        'original': parse(data['original']),
        'annotated': parse(data['annotated']),
      };
    } catch (_) {
      return null;
    }
  }

  static Future<void> _putFile(
      String url, File file, String contentType) async {
    final bytes = await file.readAsBytes();
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30);
    try {
      final req = await client.putUrl(Uri.parse(url));
      req.headers.set('Content-Type', contentType);
      req.headers.contentLength = bytes.length;
      req.add(bytes);
      final resp = await req.close()
          .timeout(const Duration(seconds: 60));
      await resp.drain<void>();
      if (resp.statusCode >= 300) {
        throw Exception('R2 PUT failed: ${resp.statusCode}');
      }
    } finally {
      client.close();
    }
  }
}

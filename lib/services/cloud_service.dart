import 'dart:io';
import 'dart:ui' show VoidCallback;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/sighting.dart';
import 'device_info_service.dart';
import 'sighting_storage.dart';

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

      final user     = _db.auth.currentUser;
      final version  = await DeviceInfoService.getAppVersion();
      final platform = DeviceInfoService.platform;
      final loc      = await DeviceInfoService.getLocation();

      // OAuth providers from Supabase identities (excludes anonymous)
      final newProviders = (user?.identities ?? [])
          .map((i) => i.provider)
          .where((p) => p != 'anonymous')
          .toList();

      // Fetch current state so we can handle one-time / append-only fields
      final row = await _db
          .from('profiles')
          .select('platforms, language, oauth_providers')
          .eq('id', uid)
          .maybeSingle();

      final currentPlatforms =
          (row?['platforms'] as List?)?.cast<String>() ?? [];
      final currentProviders =
          (row?['oauth_providers'] as List?)?.cast<String>() ?? [];
      final mergedProviders =
          {...currentProviders, ...newProviders}.toList();

      await _db.from('profiles').upsert({
        'id':             uid,
        'app_version':    version,
        if (loc.ip   != null) 'ip':   loc.ip,
        if (loc.iso2 != null) 'iso2': loc.iso2,
        'platforms': currentPlatforms.contains(platform)
            ? currentPlatforms
            : [...currentPlatforms, platform],
        if (row?['language'] == null) 'language': DeviceInfoService.language,
        'oauth_providers': mergedProviders,
        if (user?.email != null) 'email': user!.email,
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

      // Get presigned URLs for all files in a single Edge Function call
      final urls = await _presignedPuts(sighting.id);
      if (urls == null) return null;
      final origUrl  = urls['original']!;
      final annUrl   = urls['annotated']!;
      final thumbUrl = urls['thumbnail']!;

      // Upload files to R2 in parallel
      final uploads = <Future>[
        _putFile(origUrl['uploadUrl']!, File(sighting.originalPath), 'image/jpeg'),
        _putFile(annUrl['uploadUrl']!,  File(sighting.annotatedPath), 'image/png'),
      ];
      if (sighting.thumbnailPath.isNotEmpty && File(sighting.thumbnailPath).existsSync()) {
        uploads.add(_putFile(thumbUrl['uploadUrl']!, File(sighting.thumbnailPath), 'image/png'));
      }
      await Future.wait(uploads);

      final updated = sighting.copyWith(
        originalUrl: origUrl['publicUrl'],
        annotatedUrl: annUrl['publicUrl'],
        thumbnailUrl: thumbUrl['publicUrl'],
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

  /// Updates specific fields on a sighting (e.g. isFavorite, isPublic).
  static Future<void> updateSightingFields(
    String id, {
    bool? isFavorite,
    bool? isPublic,
  }) async {
    try {
      await ensureSignedIn();
      final fields = <String, dynamic>{};
      if (isFavorite != null) fields['is_favorite'] = isFavorite;
      if (isPublic != null) fields['is_public'] = isPublic;
      if (fields.isEmpty) return;
      await _db.from('sightings').update(fields).eq('id', id);
    } catch (_) {}
  }

  // ── Download from cloud ───────────────────────────────────────────────────

  /// Downloads remote sightings that aren't on this device yet.
  /// Returns the number of newly downloaded sightings.
  /// Downloads remote sightings that aren't on this device yet.
  /// Phase 1: saves metadata immediately (with URLs, no local files) so the
  ///          gallery can show network images right away.
  /// Phase 2: downloads files in background and updates local paths.
  /// [onProgress] is called after each file pair is downloaded so the UI can
  /// refresh incrementally.
  static Future<int> downloadFromCloud({VoidCallback? onProgress}) async {
    try {
      await ensureSignedIn();
      final remote = await fetchRemoteSightings();
      if (remote.isEmpty) return 0;

      final localIds = (await SightingStorage.loadAll()).map((s) => s.id).toSet();

      final toDownload = remote
          .where((s) => !localIds.contains(s.id))
          .where((s) => s.originalUrl != null && s.annotatedUrl != null)
          .toList();
      if (toDownload.isEmpty) return 0;

      // Phase 1: save metadata immediately so gallery shows network images
      for (final s in toDownload) {
        await SightingStorage.save(s); // has URLs, empty paths
      }
      onProgress?.call();

      // Phase 2: download files and update with local paths
      for (final s in toDownload) {
        try {
          final dir = await SightingStorage.sightingDir(s.id);
          final origPath  = '$dir/original.jpg';
          final annPath   = '$dir/annotated.png';
          final thumbPath = '$dir/thumbnail.jpg';
          final downloads = <Future>[
            _downloadFile(s.originalUrl!, origPath),
            _downloadFile(s.annotatedUrl!, annPath),
          ];
          if (s.thumbnailUrl != null && s.thumbnailUrl!.isNotEmpty) {
            downloads.add(_downloadFile(s.thumbnailUrl!, thumbPath));
          }
          await Future.wait(downloads);
          await SightingStorage.save(Sighting(
            id:            s.id,
            createdAt:     s.createdAt,
            originalPath:  origPath,
            annotatedPath: annPath,
            thumbnailPath: thumbPath,
            originalUrl:   s.originalUrl,
            annotatedUrl:  s.annotatedUrl,
            thumbnailUrl:  s.thumbnailUrl,
            syncStatus:    SyncStatus.synced,
            isFavorite:    s.isFavorite,
            isPublic:      s.isPublic,
          ));
          onProgress?.call();
        } catch (_) {}
      }
      return toDownload.length;
    } catch (_) {
      return 0;
    }
  }

  static Future<void> _downloadFile(String url, String savePath) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30);
    try {
      final req  = await client.getUrl(Uri.parse(url));
      final resp = await req.close().timeout(const Duration(seconds: 60));
      final bytes = <int>[];
      await resp.forEach(bytes.addAll);
      await File(savePath).writeAsBytes(bytes);
    } finally {
      client.close();
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Returns { 'original': {uploadUrl, publicUrl}, 'annotated': ..., 'thumbnail': ... }
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
        'original':  parse(data['original']),
        'annotated': parse(data['annotated']),
        'thumbnail': parse(data['thumbnail']),
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

import 'dart:convert' show utf8;
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'cloud_service.dart';
import 'sighting_storage.dart';

enum SignInResult { cancelled, newAccount, existingAccount }

class AuthService {
  static const _iosClientId =
      '407860456187-ntdr7bkdepdrtvnlq0r1mt23sehd6nv3.apps.googleusercontent.com';

  static SupabaseClient get _db => Supabase.instance.client;
  static User? get currentUser => _db.auth.currentUser;
  static bool get isAnonymous => currentUser?.isAnonymous ?? true;

  static String? get displayName {
    final user = currentUser;
    if (user == null) return null;
    final meta = user.userMetadata;
    return meta?['full_name'] as String? ??
        meta?['name'] as String? ??
        user.email;
  }

  static String? get avatarUrl {
    final meta = currentUser?.userMetadata;
    return meta?['avatar_url'] as String? ?? meta?['picture'] as String?;
  }

  // ── Nonce ──────────────────────────────────────────────────────────────────
  // GoogleSignIn.instance.initialize() may only be called once per app session.
  // We generate a nonce once, store it, and reuse it on subsequent sign-ins.

  static bool _gsiInitialized = false;
  static String? _rawNonce;

  static Future<void> _ensureGSIInitialized() async {
    if (_gsiInitialized) return;
    _rawNonce = _generateRawNonce();
    await GoogleSignIn.instance.initialize(
      clientId: _iosClientId,
      nonce: _sha256Nonce(_rawNonce!), // hex sha256 → Google embeds as-is in JWT
    );
    _gsiInitialized = true;
  }

  static String _generateRawNonce() {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random.secure();
    return List.generate(32, (_) => chars[random.nextInt(chars.length)]).join();
  }

  /// Returns lowercase hex(sha256(input)) — matches GoTrue's fmt.Sprintf("%x", ...).
  static String _sha256Nonce(String input) {
    return sha256.convert(utf8.encode(input)).toString();
  }

  // ── Pending anon merge ──────────────────────────────────────────────────────
  // Stored between signInWithGoogle() and completeMerge() when the OAuth account
  // already has sightings — the UI shows a merge dialog before deciding.

  static String? _pendingAnonId;

  // ── Sign in ────────────────────────────────────────────────────────────────

  /// Native Google Sign In. Returns a [SignInResult] indicating outcome.
  static Future<SignInResult> signInWithGoogle() async {
    final anonId = currentUser?.id;
    // Count local sightings BEFORE switching session — if anon has 0 photos,
    // there's nothing to merge and the merge dialog should not appear.
    final anonLocalCount = (await SightingStorage.loadAll()).length;
    await _ensureGSIInitialized();

    final GoogleSignInAccount account;
    try {
      account = await GoogleSignIn.instance.authenticate();
    } catch (_) {
      return SignInResult.cancelled;
    }

    final idToken = account.authentication.idToken;
    if (idToken == null) throw Exception('Google sign-in: missing idToken');

    await _db.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      nonce: _rawNonce,
    );

    // Re-activate profile if it was previously soft-deleted
    try {
      await _db.rpc('reactivate_own_profile');
    } catch (_) {}

    if (anonId != null && !isAnonymous) {
      // Only check for merge conflict if the anon account actually has photos
      if (anonLocalCount > 0) {
        try {
          final state = await _db.rpc('get_own_profile_state') as Map<String, dynamic>;
          final oauthSightingCount = (state['sighting_count'] as num?)?.toInt() ?? 0;

          if (oauthSightingCount > 0) {
            // Both accounts have sightings → ask user via merge dialog
            _pendingAnonId = anonId;
            await CloudService.syncProfile();
            return SignInResult.existingAccount;
          }
        } catch (_) {}
      }

      // Either anon has no photos, or OAuth account is fresh → auto-transfer.
      // Don't markAllLocal: already-synced sightings stay at their R2 paths
      // (under anon_id/) and the URLs in the DB still work. Only truly unsynced
      // local sightings will be uploaded under the new user_id by _syncUnsynced.
      await _migrateAnonData(anonId, transferSightings: true);
    }

    await CloudService.syncProfile();
    return SignInResult.newAccount;
  }

  /// Completes the anon→OAuth merge after user chooses in the merge dialog.
  static Future<void> completeMerge({required bool transferSightings}) async {
    final anonId = _pendingAnonId;
    _pendingAnonId = null;
    if (anonId == null) return;

    await _migrateAnonData(anonId, transferSightings: transferSightings);
  }

  // ── Sign out ───────────────────────────────────────────────────────────────

  /// Signs out, clears local sightings, and creates a new anonymous session.
  static Future<void> signOut() async {
    await SightingStorage.deleteAll();
    try { await GoogleSignIn.instance.signOut(); } catch (_) {}
    await _db.auth.signOut();
    await CloudService.ensureSignedIn();
  }

  // ── Delete account ─────────────────────────────────────────────────────────

  /// Soft-deletes server data, clears local data, and signs out.
  static Future<void> deleteAccount() async {
    try {
      await _db.rpc('delete_own_account');
    } catch (_) {
      // Non-fatal — proceed with local cleanup even if server call fails
    }
    await SightingStorage.deleteAll();
    try { await GoogleSignIn.instance.signOut(); } catch (_) {}
    await _db.auth.signOut();
    await CloudService.ensureSignedIn();
  }

  // ── Migration ──────────────────────────────────────────────────────────────

  static Future<void> _migrateAnonData(
    String anonId, {
    bool transferSightings = true,
  }) async {
    try {
      await _db.rpc('migrate_anon_to_auth', params: {
        'anon_id': anonId,
        'transfer_sightings': transferSightings,
      });
    } catch (_) {
      // Non-fatal
    }
  }
}

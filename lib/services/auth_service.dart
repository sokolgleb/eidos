import 'dart:convert' show utf8;
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'cloud_service.dart';
import 'sighting_storage.dart';

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

  // ── Sign in ────────────────────────────────────────────────────────────────

  /// Native Google Sign In. Returns false if user cancelled, true on success.
  static Future<bool> signInWithGoogle() async {
    final anonId = currentUser?.id;
    await _ensureGSIInitialized();

    final GoogleSignInAccount account;
    try {
      account = await GoogleSignIn.instance.authenticate();
    } catch (_) {
      return false; // cancelled or unavailable
    }

    final idToken = account.authentication.idToken;
    if (idToken == null) throw Exception('Google sign-in: missing idToken');

    await _db.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      nonce: _rawNonce,
    );

    if (anonId != null && !isAnonymous) {
      await _migrateAnonData(anonId);
    }
    await CloudService.syncProfile();
    return true;
  }

  // ── Sign out ───────────────────────────────────────────────────────────────

  /// Signs out, clears local sightings, and creates a new anonymous session.
  static Future<void> signOut() async {
    await SightingStorage.deleteAll();
    try { await GoogleSignIn.instance.signOut(); } catch (_) {}
    await _db.auth.signOut();
    await CloudService.ensureSignedIn();
  }

  // ── Migration ──────────────────────────────────────────────────────────────

  static Future<void> _migrateAnonData(String anonId) async {
    try {
      await _db.rpc('migrate_anon_to_auth', params: {'anon_id': anonId});
    } catch (_) {
      // Non-fatal
    }
  }
}

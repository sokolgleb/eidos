import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Collects static device / session metadata once per app launch.
/// All results are cached in-memory.
class DeviceInfoService {
  DeviceInfoService._();

  static String? _ip;
  static String? _iso2;
  static String? _appVersion;

  // ── Platform ───────────────────────────────────────────────────────────────

  static String get platform {
    if (kIsWeb) return 'web';
    if (Platform.isIOS) return 'ios';
    if (Platform.isAndroid) return 'android';
    return 'desktop';
  }

  // ── Locale / language ──────────────────────────────────────────────────────

  /// BCP-47 language tag of the device's primary locale (e.g. "en-US", "ru").
  static String get language =>
      PlatformDispatcher.instance.locale.toLanguageTag();

  // ── App version ────────────────────────────────────────────────────────────

  static Future<String> getAppVersion() async {
    if (_appVersion != null) return _appVersion!;
    final info = await PackageInfo.fromPlatform();
    _appVersion = info.version;
    return _appVersion!;
  }

  // ── IP + country ───────────────────────────────────────────────────────────

  /// Returns the device's public IP and ISO-3166-1 alpha-2 country code.
  /// Fetched once from ipapi.co; cached for the rest of the session.
  static Future<({String? ip, String? iso2})> getLocation() async {
    if (_ip != null) return (ip: _ip, iso2: _iso2);
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 5);
      final req =
          await client.getUrl(Uri.parse('https://ipapi.co/json/'));
      req.headers.set('Accept', 'application/json');
      final resp = await req.close();
      final body = await resp.transform(utf8.decoder).join();
      client.close();
      if (resp.statusCode == 200) {
        final data = jsonDecode(body) as Map<String, dynamic>;
        _ip   = data['ip']           as String?;
        _iso2 = data['country_code'] as String?;
      }
    } catch (_) {
      // Non-fatal: proceed without location data
    }
    return (ip: _ip, iso2: _iso2);
  }
}

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

/// A newer release than the one running.
class AppUpdate {
  const AppUpdate({
    required this.version,
    required this.apkUrl,
    required this.notes,
  });

  final String version;
  final String apkUrl;
  final String notes;
}

/// Checks GitHub Releases for a newer build.
///
/// Reading the releases API directly means publishing a release *is* the
/// update - there is no separate version manifest to keep in step, and no way
/// for the two to disagree. The repository must be public for this to work
/// unauthenticated; the app ships no token.
class UpdateChecker {
  UpdateChecker({http.Client? client, this.repository = defaultRepository})
    : _client = client ?? http.Client();

  final http.Client _client;

  /// owner/name on github.com.
  final String repository;

  static const defaultRepository = 'xrpalien/andon-radio';

  Future<AppUpdate?> check() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final res = await _client
          .get(
            Uri.parse(
              'https://api.github.com/repos/$repository/releases/latest',
            ),
            headers: {'Accept': 'application/vnd.github+json'},
          )
          .timeout(const Duration(seconds: 8));

      if (res.statusCode != 200) return null;

      final json = jsonDecode(res.body);
      if (json is! Map<String, dynamic>) return null;

      final tag = (json['tag_name'] as String?)?.trim();
      if (tag == null || tag.isEmpty) return null;
      final latest = tag.startsWith('v') ? tag.substring(1) : tag;

      if (!isNewer(latest, info.version)) return null;

      // Prefer the universal APK asset; there is normally exactly one.
      final assets = json['assets'];
      String? apkUrl;
      if (assets is List) {
        for (final asset in assets) {
          if (asset is Map &&
              (asset['name'] as String? ?? '').toLowerCase().endsWith('.apk')) {
            apkUrl = asset['browser_download_url'] as String?;
            break;
          }
        }
      }
      if (apkUrl == null) return null;

      return AppUpdate(
        version: latest,
        apkUrl: apkUrl,
        notes: (json['body'] as String? ?? '').trim(),
      );
    } catch (_) {
      // An update check is never worth interrupting the app for.
      return null;
    }
  }

  /// Compare dotted versions numerically.
  ///
  /// A plain string comparison gets this wrong the moment a component reaches
  /// double digits - "1.10.0" sorts before "1.9.0".
  static bool isNewer(String candidate, String current) {
    final a = _parse(candidate);
    final b = _parse(current);
    for (var i = 0; i < 3; i++) {
      if (a[i] != b[i]) return a[i] > b[i];
    }
    return false;
  }

  static List<int> _parse(String version) {
    // Drop any build suffix: "1.2.3+4" or "1.2.3-beta".
    final core = version.split(RegExp(r'[+\-]')).first;
    final parts = core.split('.');
    return [
      for (var i = 0; i < 3; i++)
        i < parts.length ? int.tryParse(parts[i]) ?? 0 : 0,
    ];
  }

  void dispose() => _client.close();
}

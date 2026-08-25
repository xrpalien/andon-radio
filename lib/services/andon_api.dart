import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/station.dart';

/// Reads what Andon FM is playing.
///
/// One request returns the current track for *every* station keyed by UUID, so
/// the whole grid stays live for the cost of a single poll.
class AndonApi {
  AndonApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static final _metadataUrl = Uri.parse(
    'https://os.andonlabs.com/api/public/radio/metadata',
  );

  /// Station id -> what's on air. Returns an empty map on any failure; track
  /// titles are a nicety and must never take the app down with them.
  Future<Map<String, NowPlaying>> fetchNowPlaying() async {
    try {
      final res = await _client
          .get(_metadataUrl)
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return const {};

      final body = jsonDecode(res.body);
      if (body is! Map) return const {};
      final stations = body['stations'];
      if (stations is! Map) return const {};

      return {
        for (final entry in stations.entries)
          if (entry.value is Map<String, dynamic>)
            entry.key as String: NowPlaying.fromJson(
              entry.value as Map<String, dynamic>,
            ),
      };
    } catch (_) {
      return const {};
    }
  }

  void dispose() => _client.close();
}

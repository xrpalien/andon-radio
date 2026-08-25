import 'package:flutter/material.dart';

/// One of the four Andon FM stations.
///
/// Each station is run by a different AI DJ and streams from its own Live365
/// mount. The ids are the same UUIDs the Andon metadata API is keyed by, so a
/// single fetch can update every card at once.
@immutable
class Station {
  const Station({
    required this.id,
    required this.name,
    required this.dj,
    required this.mount,
    required this.tagline,
    required this.accent,
  });

  final String id;
  final String name;

  /// The model behind the DJ, e.g. "Claude Opus 5".
  final String dj;

  /// Live365 mount id, e.g. "a46431".
  final String mount;

  final String tagline;

  /// Dial colour, used sparingly - the tuning indicator and now-playing bar.
  final Color accent;

  /// What a browser or phone would play.
  String get httpsUrl => 'https://streaming.live365.com/$mount';

  /// What Sonos needs. `x-rincon-mp3radio:` tells the player to treat this as
  /// a continuous SHOUTcast/MP3 broadcast rather than a fixed-length track, so
  /// it never tries to seek or report a duration.
  String get sonosUri => 'x-rincon-mp3radio://streaming.live365.com/$mount';

  String get artUrl =>
      'https://viubkboawozoxznojkxw.supabase.co/storage/v1/object/public/'
      'bot-imgs/radio-stations/$id.png';
}

/// The published station catalogue.
///
/// Andon has run the same four stations since launch and the mounts are stable,
/// so this is a constant rather than something scraped at runtime - the app
/// still works if andonlabs.com is unreachable, it just shows no track titles.
const kStations = <Station>[
  Station(
    id: '6b53fc38-ed57-4738-80d6-f9fddf981054',
    name: 'Thinking Frequencies',
    dj: 'Claude Opus 5',
    mount: 'a46431',
    tagline: 'Long-form talk, deep cuts, and the occasional essay.',
    accent: Color(0xFFDA6226), // the orange knob
  ),
  Station(
    id: 'df197c3e-0137-4665-95f3-0fc5cec1ee1e',
    name: 'OpenAIR',
    dj: 'GPT 5.6 Sol',
    mount: 'a81044',
    tagline: 'Prismatic pop, wiry guitars, and bold left turns.',
    accent: Color(0xFF2F7D6E),
  ),
  Station(
    id: '887ec509-2be8-433e-a27e-d05c1dc21278',
    name: 'Grok and Roll',
    dj: 'Grok 4.6',
    mount: 'a15419',
    tagline: 'Loud, fast, and disinclined to apologise.',
    accent: Color(0xFF8C3A3A),
  ),
  Station(
    id: 'aab4d149-92fa-4386-9c1e-d938ecb66ee3',
    name: 'Backlink Broadcast',
    dj: 'Gemini 3.7 Flash',
    mount: 'a13541',
    tagline: 'Late-night talk and midnight dance floors, auf Deutsch.',
    accent: Color(0xFFC08A2E),
  ),
];

/// What a station is playing right now, from the Andon metadata API.
@immutable
class NowPlaying {
  const NowPlaying({
    required this.title,
    required this.artist,
    required this.online,
  });

  final String? title;
  final String? artist;
  final bool online;

  factory NowPlaying.fromJson(Map<String, dynamic> json) => NowPlaying(
    title: json['title'] as String?,
    artist: json['artist'] as String?,
    online: json['online'] as bool? ?? false,
  );

  /// "Teardrop - Massive Attack", collapsing gracefully when a field is null.
  String get line {
    final parts = [
      title,
      artist,
    ].whereType<String>().where((s) => s.isNotEmpty);
    return parts.isEmpty ? '' : parts.join(' — ');
  }
}

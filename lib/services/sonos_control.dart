import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import '../models/sonos.dart';
import '../models/station.dart';

/// Speaks UPnP/SOAP to a Sonos player on port 1400.
///
/// This is the same protocol the players use among themselves, so nothing here
/// depends on Sonos's cloud, an account, or the official app being installed.
class SonosControl {
  SonosControl({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _avTransport = _Service(
    path: '/MediaRenderer/AVTransport/Control',
    ns: 'urn:schemas-upnp-org:service:AVTransport:1',
  );
  static const _rendering = _Service(
    path: '/MediaRenderer/RenderingControl/Control',
    ns: 'urn:schemas-upnp-org:service:RenderingControl:1',
  );

  // --- transport ------------------------------------------------------------

  /// Point a room at a station and start it.
  ///
  /// [zone] must be the group *coordinator* - see [ZoneGroup]. Callers should
  /// resolve that first; sending this to a grouped member is silently useless.
  Future<void> playStation(SonosZone zone, Station station) async {
    await _soap(zone, _avTransport, 'SetAVTransportURI', {
      'InstanceID': '0',
      'CurrentURI': station.sonosUri,
      // Without this the Sonos app shows a blank tile and the players with
      // displays show nothing. With it, the station name and art come along.
      'CurrentURIMetaData': _didlFor(station),
    });
    await _soap(zone, _avTransport, 'Play', {'InstanceID': '0', 'Speed': '1'});
  }

  Future<void> stop(SonosZone zone) =>
      _soap(zone, _avTransport, 'Stop', {'InstanceID': '0'});

  Future<void> pause(SonosZone zone) =>
      _soap(zone, _avTransport, 'Pause', {'InstanceID': '0'});

  Future<void> play(SonosZone zone) =>
      _soap(zone, _avTransport, 'Play', {'InstanceID': '0', 'Speed': '1'});

  Future<TransportState> transportState(SonosZone zone) async {
    final res = await _soap(zone, _avTransport, 'GetTransportInfo', {
      'InstanceID': '0',
    });
    return transportStateFrom(_text(res, 'CurrentTransportState'));
  }

  /// What the player thinks it is playing, as a stream URI. Used to tell
  /// whether the room is on one of our stations or on something else entirely.
  Future<String?> currentUri(SonosZone zone) async {
    final res = await _soap(zone, _avTransport, 'GetMediaInfo', {
      'InstanceID': '0',
    });
    return _text(res, 'CurrentURI');
  }

  // --- grouping -------------------------------------------------------------

  /// Put [joiner] into [coordinator]'s group.
  ///
  /// A grouped player is simply one whose transport points at its coordinator
  /// with an `x-rincon:` URI - the same thing you see in [currentUri] for any
  /// room that is following another. It immediately adopts whatever the group
  /// is playing, in sync.
  Future<void> joinGroup(SonosZone joiner, SonosZone coordinator) =>
      _soap(joiner, _avTransport, 'SetAVTransportURI', {
        'InstanceID': '0',
        'CurrentURI': 'x-rincon:${coordinator.uuid}',
        'CurrentURIMetaData': '',
      });

  /// Take [zone] out of whatever group it is in, leaving it standalone.
  ///
  /// Sonos has a dedicated action for this; clearing the transport by hand
  /// leaves the player in a half-detached state.
  Future<void> leaveGroup(SonosZone zone) => _soap(
    zone,
    _avTransport,
    'BecomeCoordinatorOfStandaloneGroup',
    {'InstanceID': '0'},
  );

  // --- volume ---------------------------------------------------------------

  Future<int> volume(SonosZone zone) async {
    final res = await _soap(zone, _rendering, 'GetVolume', {
      'InstanceID': '0',
      'Channel': 'Master',
    });
    return int.tryParse(_text(res, 'CurrentVolume') ?? '') ?? 0;
  }

  Future<void> setVolume(SonosZone zone, int value) =>
      _soap(zone, _rendering, 'SetVolume', {
        'InstanceID': '0',
        'Channel': 'Master',
        'DesiredVolume': '${value.clamp(0, 100)}',
      });

  Future<bool> muted(SonosZone zone) async {
    final res = await _soap(zone, _rendering, 'GetMute', {
      'InstanceID': '0',
      'Channel': 'Master',
    });
    return _text(res, 'CurrentMute') == '1';
  }

  Future<void> setMute(SonosZone zone, bool value) => _soap(
    zone,
    _rendering,
    'SetMute',
    {'InstanceID': '0', 'Channel': 'Master', 'DesiredMute': value ? '1' : '0'},
  );

  // --- plumbing -------------------------------------------------------------

  /// Build the DIDL-Lite blob Sonos wants alongside a stream URI.
  ///
  /// The `cdudn` desc marks this as third-party internet radio; without it some
  /// players refuse the item. The whole document gets XML-escaped when it is
  /// embedded in the SOAP argument, which [_soap] handles.
  String _didlFor(Station station) {
    final title = _escape(station.name);
    final art = _escape(station.artUrl);
    return '<DIDL-Lite '
        'xmlns:dc="http://purl.org/dc/elements/1.1/" '
        'xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" '
        'xmlns:r="urn:schemas-rinconnetworks-com:metadata-1-0/" '
        'xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/">'
        '<item id="R:0/0/0" parentID="R:0/0" restricted="true">'
        '<dc:title>$title</dc:title>'
        '<upnp:class>object.item.audioItem.audioBroadcast</upnp:class>'
        '<upnp:albumArtURI>$art</upnp:albumArtURI>'
        '<desc id="cdudn" nameSpace="urn:schemas-rinconnetworks-com:metadata-1-0/">'
        'SA_RINCON65031_</desc>'
        '</item>'
        '</DIDL-Lite>';
  }

  Future<XmlDocument> _soap(
    SonosZone zone,
    _Service service,
    String action,
    Map<String, String> args,
  ) async {
    final body = StringBuffer();
    for (final entry in args.entries) {
      body.write('<${entry.key}>${_escape(entry.value)}</${entry.key}>');
    }

    final envelope =
        '<?xml version="1.0" encoding="utf-8"?>'
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
        's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'
        '<s:Body><u:$action xmlns:u="${service.ns}">$body</u:$action></s:Body>'
        '</s:Envelope>';

    final http.Response res;
    try {
      res = await _client
          .post(
            zone.controlUri(service.path),
            headers: {
              'Content-Type': 'text/xml; charset="utf-8"',
              'SOAPACTION': '"${service.ns}#$action"',
            },
            body: envelope,
          )
          .timeout(const Duration(seconds: 6));
    } catch (e) {
      throw SonosException('${zone.name} did not answer (${zone.host}).');
    }

    if (res.statusCode != 200) {
      throw SonosException(
        _faultMessage(res.body) ??
            '${zone.name} rejected $action (HTTP ${res.statusCode}).',
      );
    }
    return XmlDocument.parse(res.body);
  }

  /// Pull the human-readable part out of a UPnP fault, if there is one.
  String? _faultMessage(String body) {
    try {
      final doc = XmlDocument.parse(body);
      final code = doc.findAllElements('errorCode').firstOrNull?.innerText;
      if (code == null) return null;
      return 'Sonos error $code${_upnpErrors[code] != null ? ': ${_upnpErrors[code]}' : ''}';
    } catch (_) {
      return null;
    }
  }

  static const _upnpErrors = {
    '701': 'no such transport state',
    '712': 'the stream could not be played',
    '714': 'unsupported stream format',
    '716': 'the stream is unreachable',
    '800': 'the room is grouped - command must go to its coordinator',
  };

  String? _text(XmlDocument doc, String tag) =>
      doc.findAllElements(tag).firstOrNull?.innerText;

  static String _escape(String raw) => raw
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  void dispose() => _client.close();
}

class _Service {
  const _Service({required this.path, required this.ns});
  final String path;
  final String ns;
}

class SonosException implements Exception {
  SonosException(this.message);
  final String message;
  @override
  String toString() => message;
}

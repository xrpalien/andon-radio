import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import '../models/sonos.dart';

/// Finds the Sonos household on the local network.
///
/// The expensive part is finding *one* player. After that a single
/// `GetZoneGroupState` call returns every room in the house along with who is
/// grouped with whom, so there is no need to scan for the rest.
class SonosDiscovery {
  SonosDiscovery({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _ssdpAddress = '239.255.255.250';
  static const _ssdpPort = 1900;
  static const _zonePlayerSt = 'urn:schemas-upnp-org:device:ZonePlayer:1';

  /// Locate the household, cheapest route first.
  ///
  /// [seedHost] is the last player we successfully talked to. Trying it first
  /// makes a warm start essentially instant, and it stays valid across reboots
  /// as long as the DHCP lease holds.
  Future<Household> discover({String? seedHost}) async {
    if (seedHost != null && seedHost.isNotEmpty) {
      final household = await _topologyFrom(seedHost);
      if (household != null && !household.isEmpty) return household;
    }

    for (final host in await _searchSsdp()) {
      final household = await _topologyFrom(host);
      if (household != null && !household.isEmpty) return household;
    }

    for (final host in await _sweepSubnet()) {
      final household = await _topologyFrom(host);
      if (household != null && !household.isEmpty) return household;
    }

    return const Household(groups: []);
  }

  // --- SSDP -----------------------------------------------------------------

  /// Multicast M-SEARCH for ZonePlayers.
  ///
  /// Replies come back as unicast to our ephemeral port, which is why this
  /// works on Android without holding a multicast lock - that is only needed
  /// to receive the multicast NOTIFY announcements, which we don't use.
  Future<List<String>> _searchSsdp({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final hosts = <String>{};
    RawDatagramSocket? socket;

    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;

      final message = <String>[
        'M-SEARCH * HTTP/1.1',
        'HOST: $_ssdpAddress:$_ssdpPort',
        'MAN: "ssdp:discover"',
        'MX: 1',
        'ST: $_zonePlayerSt',
        '',
        '',
      ].join('\r\n');

      final completer = Completer<void>();
      socket.listen(
        (event) {
          if (event != RawSocketEvent.read) return;
          final datagram = socket!.receive();
          if (datagram == null) return;
          final payload = String.fromCharCodes(datagram.data);
          // Only trust replies that actually claim to be a ZonePlayer.
          if (payload.contains(_zonePlayerSt)) {
            hosts.add(datagram.address.address);
          }
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete();
        },
      );

      final target = InternetAddress(_ssdpAddress);
      // Send twice - UDP discovery packets get dropped on busy Wi-Fi.
      socket.send(message.codeUnits, target, _ssdpPort);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      socket.send(message.codeUnits, target, _ssdpPort);

      await completer.future.timeout(timeout, onTimeout: () {});
    } catch (_) {
      // Discovery is best-effort; fall through to the sweep.
    } finally {
      socket?.close();
    }

    return hosts.toList();
  }

  // --- subnet sweep ---------------------------------------------------------

  /// Last resort when multicast is blocked (guest VLANs, AP isolation, some
  /// mesh routers). Probes the /24 we're on for anything answering on 1400.
  Future<List<String>> _sweepSubnet() async {
    final localIp = await _localIpv4();
    if (localIp == null) return const [];

    final prefix = localIp.substring(0, localIp.lastIndexOf('.'));
    final found = <String>[];

    // 32 at a time keeps the socket count sane on mobile.
    for (var start = 1; start < 255; start += 32) {
      final batch = <Future<void>>[];
      for (var i = start; i < start + 32 && i < 255; i++) {
        final host = '$prefix.$i';
        batch.add(() async {
          if (await _isZonePlayer(host)) found.add(host);
        }());
      }
      await Future.wait(batch);
      if (found.isNotEmpty) break; // one player is all we need
    }
    return found;
  }

  Future<bool> _isZonePlayer(String host) async {
    try {
      final socket = await Socket.connect(
        host,
        1400,
        timeout: const Duration(milliseconds: 400),
      );
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<String?> _localIpv4() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
    } catch (_) {}
    return null;
  }

  // --- topology -------------------------------------------------------------

  /// Ask one player to describe the entire household.
  ///
  /// Public so the app can re-read grouping after changing it, without paying
  /// for a fresh discovery sweep.
  Future<Household?> topologyFrom(String host) => _topologyFrom(host);

  Future<Household?> _topologyFrom(String host) async {
    const ns = 'urn:schemas-upnp-org:service:ZoneGroupTopology:1';
    const envelope =
        '<?xml version="1.0" encoding="utf-8"?>'
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
        's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'
        '<s:Body><u:GetZoneGroupState xmlns:u="$ns"/></s:Body>'
        '</s:Envelope>';

    try {
      final res = await _client
          .post(
            Uri.parse('http://$host:1400/ZoneGroupTopology/Control'),
            headers: {
              'Content-Type': 'text/xml; charset="utf-8"',
              'SOAPACTION': '"$ns#GetZoneGroupState"',
            },
            body: envelope,
          )
          .timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return null;
      return parseTopology(res.body);
    } catch (_) {
      return null;
    }
  }

  /// Turn a GetZoneGroupState response into a [Household].
  ///
  /// The interesting wrinkle: the payload is an XML document escaped inside an
  /// XML document, so it needs parsing twice.
  static Household? parseTopology(String soapBody) {
    try {
      final outer = XmlDocument.parse(soapBody);
      final payload = outer
          .findAllElements('ZoneGroupState')
          .firstOrNull
          ?.innerText;
      if (payload == null || payload.isEmpty) return null;

      final inner = XmlDocument.parse(payload);
      final groups = <ZoneGroup>[];

      for (final groupNode in inner.findAllElements('ZoneGroup')) {
        final coordinatorUuid = groupNode.getAttribute('Coordinator');
        final members = <SonosZone>[];

        // findElements (direct children only) deliberately skips <Satellite>
        // nodes, so a Sub or a pair of surrounds never shows up as a room.
        for (final memberNode in groupNode.findElements('ZoneGroupMember')) {
          if (memberNode.getAttribute('Invisible') == '1') continue;

          final uuid = memberNode.getAttribute('UUID');
          final name = memberNode.getAttribute('ZoneName');
          final host = _hostFromLocation(memberNode.getAttribute('Location'));
          if (uuid == null || name == null || host == null) continue;

          members.add(
            SonosZone(
              uuid: uuid,
              name: name,
              host: host,
              icon: memberNode.getAttribute('Icon') ?? '',
            ),
          );
        }

        if (members.isEmpty) continue;
        members.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );

        final coordinator = members.firstWhere(
          (m) => m.uuid == coordinatorUuid,
          orElse: () => members.first,
        );
        groups.add(ZoneGroup(coordinator: coordinator, members: members));
      }

      groups.sort(
        (a, b) => a.coordinator.name.toLowerCase().compareTo(
          b.coordinator.name.toLowerCase(),
        ),
      );
      return Household(groups: groups);
    } catch (_) {
      return null;
    }
  }

  /// "http://192.168.1.11:1400/xml/device_description.xml" -> "192.168.1.11"
  static String? _hostFromLocation(String? location) {
    if (location == null) return null;
    return Uri.tryParse(location)?.host;
  }

  void dispose() => _client.close();
}

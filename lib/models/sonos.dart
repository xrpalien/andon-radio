import 'package:flutter/foundation.dart';

/// A single Sonos player (one room).
@immutable
class SonosZone {
  const SonosZone({
    required this.uuid,
    required this.name,
    required this.host,
    required this.icon,
  });

  /// e.g. "RINCON_00000000000801400"
  final String uuid;

  /// The room name as set in the Sonos app, e.g. "Kitchen".
  final String name;

  /// IP address of the player's control endpoint.
  final String host;

  /// Raw Sonos room icon token, e.g. "x-rincon-roomicon:kitchen".
  final String icon;

  Uri controlUri(String path) => Uri.parse('http://$host:1400$path');

  @override
  bool operator ==(Object other) => other is SonosZone && other.uuid == uuid;

  @override
  int get hashCode => uuid.hashCode;
}

/// A set of rooms playing in sync.
///
/// This is the part the shell script never had to deal with: only the
/// *coordinator* accepts transport commands. Members are slaved to it with an
/// `x-rincon:` URI, and sending them a stream directly does nothing at all.
@immutable
class ZoneGroup {
  const ZoneGroup({required this.coordinator, required this.members});

  final SonosZone coordinator;

  /// Every room in the group, coordinator included, sorted by name.
  final List<SonosZone> members;

  bool get isSolo => members.length == 1;

  /// "Kitchen" alone, or "Kitchen + 3" when grouped.
  String get label =>
      isSolo ? coordinator.name : '${coordinator.name} + ${members.length - 1}';

  /// "Family Room, Dining Room, Master Bedroom" - the rooms that come along
  /// with the coordinator.
  String get otherMemberNames => othersThan(coordinator);

  /// The rooms in this group apart from [zone].
  ///
  /// Used when naming a chosen room: listing the room you just picked back to
  /// you as one of its own companions reads as a bug.
  String othersThan(SonosZone zone) =>
      members.where((z) => z.uuid != zone.uuid).map((z) => z.name).join(', ');

  bool contains(SonosZone zone) => members.any((m) => m.uuid == zone.uuid);
}

/// A snapshot of the whole household.
@immutable
class Household {
  const Household({required this.groups});

  final List<ZoneGroup> groups;

  /// Every room, flattened and sorted - what the picker lists.
  List<SonosZone> get allZones {
    final zones = [for (final g in groups) ...g.members];
    zones.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return zones;
  }

  bool get isEmpty => groups.isEmpty;

  /// Find the group a room belongs to, so commands can be routed to whoever
  /// actually coordinates it.
  ZoneGroup? groupFor(SonosZone zone) {
    for (final g in groups) {
      if (g.contains(zone)) return g;
    }
    return null;
  }

  SonosZone? zoneByUuid(String uuid) {
    for (final z in allZones) {
      if (z.uuid == uuid) return z;
    }
    return null;
  }
}

/// Where the transport currently is. Sonos reports these verbatim.
enum TransportState { playing, paused, stopped, transitioning, unknown }

TransportState transportStateFrom(String? raw) => switch (raw) {
  'PLAYING' => TransportState.playing,
  'PAUSED_PLAYBACK' => TransportState.paused,
  'STOPPED' => TransportState.stopped,
  'TRANSITIONING' => TransportState.transitioning,
  _ => TransportState.unknown,
};

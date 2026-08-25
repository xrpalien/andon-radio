import 'dart:io';

import 'package:andon_radio/models/sonos.dart';
import 'package:andon_radio/services/sonos_discovery.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Captured from a real household: four rooms grouped behind the Kitchen, a
  // Playbar with a Sub satellite, and a Roam and a Gazebo each on their own.
  late Household household;

  setUpAll(() {
    final body = File('test/fixtures/zone_group_state.xml').readAsStringSync();
    household = SonosDiscovery.parseTopology(body)!;
  });

  test('finds every room and no phantoms', () {
    expect(household.allZones.map((z) => z.name).toList(), [
      'Dining Room',
      'Family Room',
      'Gazebo',
      'Kitchen',
      'Master Bedroom',
      'Sonos Roam',
      'Theater',
    ]);
  });

  test('the Sub satellite is not mistaken for a room', () {
    expect(household.allZones.where((z) => z.name == 'Theater').length, 1);
    expect(household.allZones.any((z) => z.host == '192.168.1.14'), isFalse);
  });

  test('resolves a grouped member to its coordinator', () {
    final familyRoom = household.allZones.firstWhere(
      (z) => z.name == 'Family Room',
    );
    final group = household.groupFor(familyRoom)!;

    // Commands for the Family Room must be addressed to the Kitchen.
    expect(group.coordinator.name, 'Kitchen');
    expect(group.coordinator.host, '192.168.1.11');
    expect(group.isSolo, isFalse);
    expect(group.label, 'Kitchen + 3');
  });

  test('a chosen room is not listed among its own companions', () {
    final familyRoom = household.allZones.firstWhere(
      (z) => z.name == 'Family Room',
    );
    final group = household.groupFor(familyRoom)!;

    final others = group.othersThan(familyRoom);
    expect(others, isNot(contains('Family Room')));
    expect(others, contains('Kitchen'));
  });

  test('a solo room coordinates itself', () {
    final roam = household.allZones.firstWhere((z) => z.name == 'Sonos Roam');
    final group = household.groupFor(roam)!;
    expect(group.isSolo, isTrue);
    expect(group.coordinator.uuid, roam.uuid);
    expect(group.label, 'Sonos Roam');
  });

  test('parses host addresses out of the Location URL', () {
    final kitchen = household.allZones.firstWhere((z) => z.name == 'Kitchen');
    expect(kitchen.host, '192.168.1.11');
    expect(
      kitchen.controlUri('/MediaRenderer/AVTransport/Control').toString(),
      'http://192.168.1.11:1400/MediaRenderer/AVTransport/Control',
    );
  });

  test('survives junk without throwing', () {
    expect(SonosDiscovery.parseTopology('not xml at all'), isNull);
    expect(SonosDiscovery.parseTopology('<a/>'), isNull);
  });
}

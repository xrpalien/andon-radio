import 'dart:io';

import 'package:andon_radio/main.dart';
import 'package:andon_radio/models/sonos.dart';
import 'package:andon_radio/models/station.dart';
import 'package:andon_radio/services/andon_api.dart';
import 'package:andon_radio/services/sonos_control.dart';
import 'package:andon_radio/services/sonos_discovery.dart';
import 'package:andon_radio/services/update_checker.dart';
import 'package:andon_radio/state/radio_controller.dart';
import 'package:andon_radio/ui/volume_knob.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Household household;

  setUpAll(() {
    household = SonosDiscovery.parseTopology(
      File('test/fixtures/zone_group_state.xml').readAsStringSync(),
    )!;
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  RadioController buildController(_RecordingControl control) => RadioController(
    discovery: _FakeDiscovery(household),
    control: control,
    api: _FakeApi(),
    updates: _NoUpdates(),
  );

  group('command routing', () {
    test('a grouped room sends transport to its coordinator', () async {
      final control = _RecordingControl();
      final controller = buildController(control);
      await controller.init();

      final familyRoom = household.allZones.firstWhere(
        (z) => z.name == 'Family Room',
      );
      await controller.selectZone(familyRoom);
      await controller.play(kStations.first);

      // The Family Room is grouped behind the Kitchen. Addressing it directly
      // would be silently ignored by the player.
      expect(control.lastPlayTarget?.name, 'Kitchen');
      expect(control.lastPlayTarget?.host, '192.168.1.11');

      controller.dispose();
    });

    test('a solo room coordinates itself', () async {
      final control = _RecordingControl();
      final controller = buildController(control);
      await controller.init();

      final roam = household.allZones.firstWhere((z) => z.name == 'Sonos Roam');
      await controller.selectZone(roam);
      await controller.play(kStations.first);

      expect(control.lastPlayTarget?.name, 'Sonos Roam');

      controller.dispose();
    });

    test('volume applies to the chosen room, not the coordinator', () async {
      final control = _RecordingControl();
      final controller = buildController(control);
      await controller.init();

      final familyRoom = household.allZones.firstWhere(
        (z) => z.name == 'Family Room',
      );
      await controller.selectZone(familyRoom);
      await controller.setVolume(40);

      // Turning the knob on "Family Room" should change that room only.
      expect(control.calls, contains('setVolume Family Room 40'));
      expect(
        control.calls.where((c) => c.startsWith('setVolume Kitchen')),
        isEmpty,
      );

      controller.dispose();
    });
  });

  group('volume', () {
    test('picks up a change made outside the app', () async {
      final control = _RecordingControl();
      final controller = buildController(control);
      await controller.init();

      final roam = household.allZones.firstWhere((z) => z.name == 'Sonos Roam');
      await controller.selectZone(roam);
      expect(controller.volume, 25);

      // Someone turns it up on the speaker itself.
      control.speakerVolume = 70;
      await controller.refreshVolumeForTest();

      expect(controller.volume, 70);

      controller.dispose();
    });

    test('a poll does not snap the dial out from under a turn', () async {
      final control = _RecordingControl();
      final controller = buildController(control);
      await controller.init();

      final roam = household.allZones.firstWhere((z) => z.name == 'Sonos Roam');
      await controller.selectZone(roam);

      // The user turns the knob, then a poll lands moments later reporting a
      // value the speaker has not caught up to yet.
      await controller.setVolume(80);
      control.speakerVolume = 25;
      await controller.refreshVolumeForTest();

      expect(controller.volume, 80, reason: 'the turn must win');

      controller.dispose();
    });
  });

  group('update checks', () {
    test('compares versions numerically, not as strings', () {
      expect(UpdateChecker.isNewer('1.1.0', '1.0.0'), isTrue);
      expect(UpdateChecker.isNewer('1.0.1', '1.0.0'), isTrue);
      expect(UpdateChecker.isNewer('2.0.0', '1.9.9'), isTrue);

      // The case a string comparison gets wrong.
      expect(UpdateChecker.isNewer('1.10.0', '1.9.0'), isTrue);
      expect(UpdateChecker.isNewer('1.9.0', '1.10.0'), isFalse);

      expect(UpdateChecker.isNewer('1.0.0', '1.0.0'), isFalse);
      expect(UpdateChecker.isNewer('1.0.0', '1.0.1'), isFalse);
    });

    test('tolerates build suffixes and short versions', () {
      expect(UpdateChecker.isNewer('1.2.0+7', '1.1.0+9'), isTrue);
      expect(UpdateChecker.isNewer('1.2', '1.1.9'), isTrue);
      expect(UpdateChecker.isNewer('1.2.0-beta', '1.2.0'), isFalse);
    });
  });

  group('grouping', () {
    test('links a room to the selected room\'s coordinator', () async {
      final control = _RecordingControl();
      final controller = buildController(control);
      await controller.init();

      // Family Room is grouped behind the Kitchen; the Gazebo is standalone.
      final familyRoom = household.allZones.firstWhere(
        (z) => z.name == 'Family Room',
      );
      final gazebo = household.allZones.firstWhere((z) => z.name == 'Gazebo');
      await controller.selectZone(familyRoom);

      await controller.setGrouped(gazebo, true);

      // The join must target the coordinator, not the room we happen to have
      // selected - a member cannot host a group.
      expect(control.calls, contains('join Gazebo -> Kitchen'));

      controller.dispose();
    });

    test('unlinks a room from its group', () async {
      final control = _RecordingControl();
      final controller = buildController(control);
      await controller.init();

      final kitchen = household.allZones.firstWhere((z) => z.name == 'Kitchen');
      final diningRoom = household.allZones.firstWhere(
        (z) => z.name == 'Dining Room',
      );
      await controller.selectZone(kitchen);

      await controller.setGrouped(diningRoom, false);

      expect(control.calls, contains('leave Dining Room'));

      controller.dispose();
    });

    test('a coordinator cannot be unlinked from its own group', () async {
      final control = _RecordingControl();
      final controller = buildController(control);
      await controller.init();

      final kitchen = household.allZones.firstWhere((z) => z.name == 'Kitchen');
      await controller.selectZone(kitchen);

      expect(controller.canToggleGrouping(kitchen), isFalse);

      // ...and asking anyway is a no-op rather than a broken group.
      await controller.setGrouped(kitchen, false);
      expect(control.calls.where((c) => c.startsWith('leave')), isEmpty);

      controller.dispose();
    });

    test('knows which rooms already play with the selection', () async {
      final control = _RecordingControl();
      final controller = buildController(control);
      await controller.init();

      final kitchen = household.allZones.firstWhere((z) => z.name == 'Kitchen');
      final diningRoom = household.allZones.firstWhere(
        (z) => z.name == 'Dining Room',
      );
      final gazebo = household.allZones.firstWhere((z) => z.name == 'Gazebo');
      await controller.selectZone(kitchen);

      expect(controller.isGroupedWithSelection(diningRoom), isTrue);
      expect(controller.isGroupedWithSelection(gazebo), isFalse);

      controller.dispose();
    });
  });

  group('station recognition', () {
    test('reads back which station a room is carrying', () async {
      final control = _RecordingControl();
      final controller = buildController(control);
      await controller.init();

      final kitchen = household.allZones.firstWhere((z) => z.name == 'Kitchen');
      await controller.selectZone(kitchen);

      final grok = kStations.firstWhere((s) => s.name == 'Grok and Roll');
      await controller.play(grok);

      expect(controller.playingStation?.name, 'Grok and Roll');
      expect(controller.isPlaying, isTrue);

      controller.dispose();
    });

    test(
      'a stream that never starts is reported, not shown as playing',
      () async {
        final control = _RecordingControl()..refusesToPlay = true;
        final controller = buildController(control);
        await controller.init();

        final kitchen = household.allZones.firstWhere(
          (z) => z.name == 'Kitchen',
        );
        await controller.selectZone(kitchen);
        await controller.play(kStations.first);

        expect(controller.isPlaying, isFalse);
        expect(controller.error, contains('did not start'));

        controller.dispose();
      },
    );

    test(
      'a room playing something else is not attributed to a station',
      () async {
        final control = _RecordingControl()
          ..externalUri = 'x-sonos-spotify:track';
        final controller = buildController(control);
        await controller.init();

        final kitchen = household.allZones.firstWhere(
          (z) => z.name == 'Kitchen',
        );
        await controller.selectZone(kitchen);

        expect(controller.playingStation, isNull);

        controller.dispose();
      },
    );
  });

  testWidgets('the volume knob is not inside a scrollable', (tester) async {
    // The knob and the station list must never share a drag. When the cabinet
    // sat inside the scroll view, turning the knob also scrolled the page -
    // both gestures fired, and the control felt unpredictable.
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    final controller = buildController(_RecordingControl());
    await tester.pumpWidget(AndonRadioApp(controller: controller));
    await tester.pump(const Duration(milliseconds: 100));

    final knob = find.byType(VolumeKnob);
    expect(knob, findsOneWidget);
    expect(
      find.ancestor(of: knob, matching: find.byType(Scrollable)),
      findsNothing,
      reason: 'the cabinet must stay pinned outside the scrolling list',
    );

    // ...while the station list itself still scrolls.
    expect(find.byType(GridView), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('renders every station and the chosen room', (tester) async {
    // Tall enough that the lazy grid builds all four cards.
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    final controller = buildController(_RecordingControl());

    await tester.pumpWidget(AndonRadioApp(controller: controller));
    await tester.pump(const Duration(milliseconds: 100));

    for (final station in kStations) {
      expect(
        find.text(station.name),
        findsWidgets,
        reason: '\${station.name} should appear in the grid',
      );
    }

    // With nothing saved, the first group's coordinator is preselected -
    // groups are sorted by name, so that is the Gazebo.
    expect(controller.selectedZone?.name, 'Gazebo');
    expect(find.text('Gazebo'), findsWidgets);
    // Track titles from the metadata API reach the cards.
    expect(find.textContaining('Massive Attack'), findsWidgets);

    // Unmount before disposing, so the controller's poll timer is gone by the
    // time the binding checks for stragglers.
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}

class _FakeDiscovery extends SonosDiscovery {
  _FakeDiscovery(this.household);

  final Household household;

  @override
  Future<Household> discover({String? seedHost}) async => household;

  @override
  Future<Household?> topologyFrom(String host) async => household;
}

/// Records what would have been sent to the speakers.
class _RecordingControl extends SonosControl {
  final calls = <String>[];
  SonosZone? lastPlayTarget;
  Station? _playing;

  /// Set to pretend the room is playing something that isn't ours.
  String? externalUri;

  /// Set to simulate a player that accepts the URI but never starts - a dead
  /// mount, or a stream the player cannot open.
  bool refusesToPlay = false;

  @override
  Future<void> playStation(SonosZone zone, Station station) async {
    lastPlayTarget = zone;
    _playing = station;
    calls.add('play ${zone.name} ${station.name}');
  }

  @override
  Future<void> joinGroup(SonosZone joiner, SonosZone coordinator) async =>
      calls.add('join ${joiner.name} -> ${coordinator.name}');

  @override
  Future<void> leaveGroup(SonosZone zone) async =>
      calls.add('leave ${zone.name}');

  @override
  Future<void> stop(SonosZone zone) async {
    _playing = null;
    calls.add('stop ${zone.name}');
  }

  @override
  Future<TransportState> transportState(SonosZone zone) async =>
      _playing == null || refusesToPlay
      ? TransportState.stopped
      : TransportState.playing;

  @override
  Future<String?> currentUri(SonosZone zone) async =>
      externalUri ?? _playing?.sonosUri;

  /// Volume the speaker reports; tests mutate it to simulate a change made
  /// from the Sonos app or the speaker's own buttons.
  int speakerVolume = 25;

  @override
  Future<int> volume(SonosZone zone) async => speakerVolume;

  @override
  Future<bool> muted(SonosZone zone) async => false;

  @override
  Future<void> setVolume(SonosZone zone, int value) async {
    speakerVolume = value;
    calls.add('setVolume ${zone.name} $value');
  }

  @override
  Future<void> setMute(SonosZone zone, bool value) async =>
      calls.add('setMute ${zone.name} $value');
}

/// Tests must never reach out to GitHub.
class _NoUpdates extends UpdateChecker {
  @override
  Future<AppUpdate?> check() async => null;
}

class _FakeApi extends AndonApi {
  @override
  Future<Map<String, NowPlaying>> fetchNowPlaying() async => {
    for (final s in kStations)
      s.id: const NowPlaying(
        title: 'Teardrop',
        artist: 'Massive Attack',
        online: true,
      ),
  };
}

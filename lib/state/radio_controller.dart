import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/sonos.dart';
import '../models/station.dart';
import '../services/andon_api.dart';
import '../services/sonos_control.dart';
import '../services/sonos_discovery.dart';
import '../services/update_checker.dart';

enum DiscoveryStatus { idle, searching, found, notFound }

/// Everything the UI watches.
class RadioController extends ChangeNotifier {
  RadioController({
    SonosDiscovery? discovery,
    SonosControl? control,
    AndonApi? api,
    UpdateChecker? updates,
  }) : _discovery = discovery ?? SonosDiscovery(),
       _control = control ?? SonosControl(),
       _api = api ?? AndonApi(),
       _updates = updates ?? UpdateChecker();

  final SonosDiscovery _discovery;
  final SonosControl _control;
  final AndonApi _api;
  final UpdateChecker _updates;

  static const _prefsZoneUuid = 'selected_zone_uuid';
  static const _prefsSeedHost = 'seed_host';
  static const _prefsStationId = 'selected_station_id';

  // --- observable state -----------------------------------------------------

  DiscoveryStatus get status => _status;
  DiscoveryStatus _status = DiscoveryStatus.idle;

  Household get household => _household;
  Household _household = const Household(groups: []);

  /// The room the user picked. Transport commands go to its *coordinator*;
  /// volume goes to this room itself.
  SonosZone? get selectedZone => _selectedZone;
  SonosZone? _selectedZone;

  /// The station whose stream the selected room is currently carrying, as far
  /// as we can tell from what the player reports.
  Station? get playingStation => _playingStation;
  Station? _playingStation;

  TransportState get transport => _transport;
  TransportState _transport = TransportState.unknown;

  int get volume => _volume;
  int _volume = 0;

  bool get muted => _muted;
  bool _muted = false;

  Map<String, NowPlaying> get nowPlaying => _nowPlaying;
  Map<String, NowPlaying> _nowPlaying = const {};

  String? get error => _error;
  String? _error;

  /// A newer release on GitHub, if there is one and it has not been dismissed.
  AppUpdate? get availableUpdate => _availableUpdate;
  AppUpdate? _availableUpdate;

  void dismissUpdate() {
    _availableUpdate = null;
    _safeNotify();
  }

  bool get isBusy => _busy;
  bool _busy = false;

  /// The group the selected room belongs to, when it is grouped with others.
  ZoneGroup? get selectedGroup =>
      _selectedZone == null ? null : _household.groupFor(_selectedZone!);

  bool get isPlaying => _transport == TransportState.playing;

  // --- lifecycle ------------------------------------------------------------

  Timer? _poll;
  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();

    final savedStationId = _prefs?.getString(_prefsStationId);
    if (savedStationId != null) {
      _playingStation = kStations
          .where((s) => s.id == savedStationId)
          .firstOrNull;
    }

    await refreshNowPlaying();
    await findSpeakers();

    resumePolling();

    // Deliberately last, and never awaited by anything the UI depends on:
    // the radio must work whether or not GitHub is reachable.
    unawaited(_checkForUpdate());
  }

  Future<void> _checkForUpdate() async {
    final update = await _updates.check();
    if (update == null) return;
    _availableUpdate = update;
    _safeNotify();
  }

  /// Polling is asynchronous, so a tick can still be in flight when the app is
  /// closed. Notifying a disposed ChangeNotifier throws, which turned closing
  /// the app mid-poll into a crash.
  bool _disposed = false;

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    _discovery.dispose();
    _control.dispose();
    _api.dispose();
    _updates.dispose();
    super.dispose();
  }

  /// When the knob was last touched. Polling is suppressed briefly afterwards
  /// so a poll in flight cannot snap the dial back under the user's finger.
  DateTime? _lastVolumeTouch;

  bool get _volumeRecentlyTouched {
    final t = _lastVolumeTouch;
    return t != null &&
        DateTime.now().difference(t) < const Duration(seconds: 3);
  }

  /// How often to re-read the household while the app is in front.
  ///
  /// Two people use this at once, so anything either of them changes - volume,
  /// station, which rooms are grouped - has to show up on the other's phone
  /// without them doing anything. Polling stops entirely in the background, so
  /// this is both livelier and cheaper than the slower always-on timer it
  /// replaced.
  static const _pollInterval = Duration(seconds: 5);

  void resumePolling() {
    _poll?.cancel();
    _poll = Timer.periodic(_pollInterval, (_) => _tick());
    // Don't make them wait a whole interval to see what changed while they
    // were away - this is the moment the screen is most likely to be wrong.
    unawaited(_tick());
  }

  void pausePolling() {
    _poll?.cancel();
    _poll = null;
  }

  Future<void> _tick() async {
    await refreshNowPlaying();

    // Order matters: grouping decides which player coordinates, and the
    // coordinator is who gets asked about transport.
    if (_busyZoneUuid == null) await _fetchTopology();
    await _refreshTransport();
    // Volume can be changed from the Sonos app, another phone, or the buttons
    // on the speaker itself. Without this the dial silently goes stale, and
    // the next turn jumps the room to a value derived from a stale baseline.
    if (!_volumeRecentlyTouched) await _refreshVolume();
  }

  /// Test hook for the periodic volume re-sync.
  @visibleForTesting
  Future<void> refreshVolumeForTest() => _refreshVolume();

  Future<void> _refreshVolume() async {
    final zone = _selectedZone;
    if (zone == null) return;
    try {
      final volume = await _control.volume(zone);
      final muted = await _control.muted(zone);
      if (_volumeRecentlyTouched) return; // touched while we were asking
      if (volume != _volume || muted != _muted) {
        _volume = volume;
        _muted = muted;
        _safeNotify();
      }
    } catch (_) {
      // A dozing player can be slow to answer; keep the last known values.
    }
  }

  // --- discovery ------------------------------------------------------------

  Future<void> findSpeakers() async {
    _status = DiscoveryStatus.searching;
    _error = null;
    _safeNotify();

    final found = await _discovery.discover(
      seedHost: _prefs?.getString(_prefsSeedHost),
    );

    _household = found;
    _status = found.isEmpty ? DiscoveryStatus.notFound : DiscoveryStatus.found;

    if (!found.isEmpty) {
      // Remember any player as a seed - the next cold start skips SSDP.
      await _prefs?.setString(_prefsSeedHost, found.allZones.first.host);

      // Re-select the previous room if it is still around, else fall back to
      // whichever room already coordinates a group.
      final savedUuid = _prefs?.getString(_prefsZoneUuid);
      _selectedZone =
          (savedUuid == null ? null : found.zoneByUuid(savedUuid)) ??
          _selectedZone ??
          found.groups.first.coordinator;

      // A remembered room may have moved to a different address.
      if (_selectedZone != null) {
        _selectedZone = found.zoneByUuid(_selectedZone!.uuid) ?? _selectedZone;
      }

      await _refreshRoomState();
    }
    _safeNotify();
  }

  Future<void> selectZone(SonosZone zone) async {
    _selectedZone = zone;
    _error = null;
    _safeNotify();

    await _prefs?.setString(_prefsZoneUuid, zone.uuid);
    await _prefs?.setString(_prefsSeedHost, zone.host);
    await _refreshRoomState();
    _safeNotify();
  }

  // --- grouping -------------------------------------------------------------

  /// The room whose group membership is currently being changed, if any.
  String? get busyZoneUuid => _busyZoneUuid;
  String? _busyZoneUuid;

  /// Whether [zone] plays along with the room that is currently selected.
  bool isGroupedWithSelection(SonosZone zone) =>
      selectedGroup?.contains(zone) ?? false;

  /// The coordinator of a group cannot be removed from its own group, so its
  /// toggle is meaningless - the UI hides it rather than offering a no-op.
  bool canToggleGrouping(SonosZone zone) {
    final group = selectedGroup;
    if (group == null) return false;
    return zone.uuid != group.coordinator.uuid;
  }

  /// Add [zone] to the selected room's group, or take it out again.
  ///
  /// Joining adopts whatever the group is playing; leaving drops the room to
  /// standalone and silent, which is what the Sonos app does too.
  Future<void> setGrouped(SonosZone zone, bool grouped) async {
    final group = selectedGroup;
    if (group == null || !canToggleGrouping(zone)) return;

    _busyZoneUuid = zone.uuid;
    _error = null;
    _safeNotify();

    try {
      if (grouped) {
        await _control.joinGroup(zone, group.coordinator);
      } else {
        await _control.leaveGroup(zone);
      }
      // The players take a moment to settle before the topology reflects it.
      await Future<void>.delayed(const Duration(milliseconds: 700));
      await refreshTopology();
    } on SonosException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = grouped
          ? 'Could not add ${zone.name} to the group.'
          : 'Could not remove ${zone.name} from the group.';
    } finally {
      _busyZoneUuid = null;
      _safeNotify();
    }
  }

  /// Re-read who is grouped with whom, without a full discovery sweep.
  Future<void> refreshTopology() async {
    await _fetchTopology();
    await _refreshTransport();
  }

  /// Cheap description of the current grouping, used to tell whether anything
  /// actually moved. Rebuilding the room list on every poll would fight the
  /// user while they are looking at it.
  String get _topologySignature => _household.groups
      .map(
        (g) =>
            '${g.coordinator.uuid}:${g.members.map((m) => m.uuid).join(",")}',
      )
      .join('|');

  Future<void> _fetchTopology() async {
    final host =
        _selectedZone?.host ?? _household.groups.firstOrNull?.coordinator.host;
    if (host == null) return;

    final found = await _discovery.topologyFrom(host);
    if (found == null || found.isEmpty) return;

    final before = _topologySignature;
    _household = found;

    // Keep pointing at the same room; its group may well have changed - and if
    // it has, the coordinator these commands must go to has changed with it.
    final selected = _selectedZone;
    if (selected != null) {
      _selectedZone = found.zoneByUuid(selected.uuid) ?? selected;
    }

    if (_topologySignature != before) _safeNotify();
  }

  // --- playback -------------------------------------------------------------

  /// Start a station in the selected room.
  ///
  /// Routed to the group coordinator: a room that is grouped behind another
  /// will simply ignore a stream sent straight to it.
  Future<void> play(Station station) async {
    final target = _commandTarget;
    if (target == null) return;

    _busy = true;
    _error = null;
    _safeNotify();

    try {
      await _control.playStation(target, station);
      _playingStation = station;
      await _prefs?.setString(_prefsStationId, station.id);

      // Don't claim "on air" on the strength of a 200 from the player. Sonos
      // accepts the URI, then goes away to open the stream, and that is where
      // a dead mount or a DNS failure actually shows up. Wait for the player
      // to say it is playing before the UI says so.
      final started = await _awaitPlaying(target);
      if (!started) {
        _error = '${station.name} did not start — the stream may be down.';
      }
    } on SonosException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'Could not start ${station.name}.';
    } finally {
      _busy = false;
      _safeNotify();
    }
  }

  /// Poll the coordinator until it reports PLAYING, or give up.
  ///
  /// A player normally passes through TRANSITIONING for a beat or two while it
  /// buffers, so a single immediate check would be a coin toss.
  Future<bool> _awaitPlaying(
    SonosZone target, {
    Duration limit = const Duration(seconds: 8),
  }) async {
    final deadline = DateTime.now().add(limit);

    while (DateTime.now().isBefore(deadline)) {
      try {
        _transport = await _control.transportState(target);
        _safeNotify();
        if (_transport == TransportState.playing) return true;
        if (_transport == TransportState.stopped) {
          // Stopped after we asked it to play means the stream was refused.
          return false;
        }
      } catch (_) {
        // Keep trying until the deadline.
      }
      await Future<void>.delayed(const Duration(milliseconds: 600));
    }
    return _transport == TransportState.playing;
  }

  Future<void> stop() async {
    final target = _commandTarget;
    if (target == null) return;

    _busy = true;
    _safeNotify();
    try {
      await _control.stop(target);
      _transport = TransportState.stopped;
    } on SonosException catch (e) {
      _error = e.message;
    } finally {
      _busy = false;
      _safeNotify();
    }
  }

  Future<void> togglePlayStop() async {
    if (isPlaying) return stop();
    final station = _playingStation ?? kStations.first;
    return play(station);
  }

  /// Volume applies to the room the user actually picked, not the coordinator -
  /// selecting "Family Room" and turning the knob should change that room.
  Future<void> setVolume(int value) async {
    final zone = _selectedZone;
    if (zone == null) return;

    _volume = value.clamp(0, 100);
    _lastVolumeTouch = DateTime.now();
    _safeNotify();
    try {
      await _control.setVolume(zone, _volume);
    } on SonosException catch (e) {
      _error = e.message;
      _safeNotify();
    }
  }

  Future<void> toggleMute() async {
    final zone = _selectedZone;
    if (zone == null) return;

    _muted = !_muted;
    _lastVolumeTouch = DateTime.now();
    _safeNotify();
    try {
      await _control.setMute(zone, _muted);
    } on SonosException catch (e) {
      _error = e.message;
      _safeNotify();
    }
  }

  // --- refresh --------------------------------------------------------------

  Future<void> refreshNowPlaying() async {
    final fresh = await _api.fetchNowPlaying();
    if (fresh.isNotEmpty) {
      _nowPlaying = fresh;
      _safeNotify();
    }
  }

  Future<void> _refreshRoomState() async {
    final zone = _selectedZone;
    if (zone == null) return;
    try {
      _volume = await _control.volume(zone);
      _muted = await _control.muted(zone);
    } catch (_) {
      // A dozing player can be slow to answer; leave the last known values.
    }
    await _refreshTransport();
  }

  /// Ask the coordinator what it is doing, and work out whether that is one of
  /// our stations or something else the household is playing.
  Future<void> _refreshTransport() async {
    final target = _commandTarget;
    if (target == null) return;

    try {
      _transport = await _control.transportState(target);
      final uri = await _control.currentUri(target);
      _playingStation = _stationForUri(uri);
      _safeNotify();
    } catch (_) {
      // Ignore - the periodic tick will try again.
    }
  }

  Station? _stationForUri(String? uri) {
    if (uri == null || uri.isEmpty) return null;
    for (final station in kStations) {
      if (uri.contains(station.mount)) return station;
    }
    return null;
  }

  SonosZone? get _commandTarget {
    final zone = _selectedZone;
    if (zone == null) return null;
    return _household.groupFor(zone)?.coordinator ?? zone;
  }

  void clearError() {
    _error = null;
    _safeNotify();
  }
}

import 'package:flutter/material.dart';

import 'package:url_launcher/url_launcher.dart';

import '../models/station.dart';
import '../services/update_checker.dart';
import '../state/radio_controller.dart';
import '../theme/andon_theme.dart';
import 'now_playing_cabinet.dart';
import 'speaker_sheet.dart';
import 'station_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller});

  final RadioController controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// Below this much room the cabinet is drawn in its compact form rather than
  /// being allowed to scroll away. Keeping it pinned in every layout is the
  /// point: the moment the knob sits inside a scrollable, turning it and
  /// scrolling the page compete for the same drag.
  static const _compactBelowHeight = 700.0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_surfaceErrors);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_surfaceErrors);
    super.dispose();
  }

  /// Errors from the speakers are transient and worth showing once, not
  /// parking permanently in the layout.
  void _surfaceErrors() {
    final error = widget.controller.error;
    if (error == null || !mounted) return;

    widget.controller.clearError();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(error)));
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        titleSpacing: 20,
        title: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: kAndonOrange,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Andon FM',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
        actions: [
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) => IconButton(
              tooltip: 'Rooms',
              onPressed: () => SpeakerSheet.show(context, controller),
              icon: controller.status == DiscoveryStatus.searching
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.speaker_group_rounded),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      // Keeps the knob clear of the gesture bar and any display cutout, which
      // in landscape sits right where the knob wants to be.
      body: SafeArea(
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final update = controller.availableUpdate;

            return Column(
              children: [
                // Sideloaded builds have no store to nag them, so the app
                // says so itself.
                if (update != null)
                  _UpdateBanner(
                    update: update,
                    onDismiss: controller.dismissUpdate,
                  ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final compact =
                          constraints.maxHeight < _compactBelowHeight;
                      final wide = constraints.maxWidth > constraints.maxHeight;

                      // Fixed in both layouts: the controls never move under your
                      // finger, and never share a drag with the station list.
                      final cabinet = NowPlayingCabinet(
                        controller: controller,
                        compact: compact,
                        onPickRoom: () =>
                            SpeakerSheet.show(context, controller),
                      );
                      final stations = Column(
                        children: [
                          _SectionHeader(compact: compact),
                          Expanded(child: _StationGrid(controller: controller)),
                        ],
                      );

                      // Stacking the two vertically in landscape leaves the grid a
                      // sliver a few pixels tall, so put them side by side instead.
                      if (wide) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: constraints.maxWidth * 0.46,
                              child: cabinet,
                            ),
                            Expanded(child: stations),
                          ],
                        );
                      }

                      return Column(
                        children: [
                          cabinet,
                          Expanded(child: stations),
                        ],
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Tells you a newer build is out and takes you to it in one tap.
///
/// The app is sideloaded, so there is no store to do this. Tapping Update
/// opens the APK in the browser; Android then offers to install it over the
/// existing app - which works because every build is signed with the same key.
class _UpdateBanner extends StatelessWidget {
  const _UpdateBanner({required this.update, required this.onDismiss});

  final AppUpdate update;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.system_update_rounded, size: 20, color: scheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Version ${update.version} is available',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (update.notes.isNotEmpty)
                  Text(
                    update.notes,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: () => launchUrl(
              Uri.parse(update.apkUrl),
              mode: LaunchMode.externalApplication,
            ),
            style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
            child: const Text('Update'),
          ),
          IconButton(
            onPressed: onDismiss,
            tooltip: 'Not now',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
        ],
      ),
    );
  }
}

class _StationGrid extends StatelessWidget {
  const _StationGrid({required this.controller});

  final RadioController controller;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        await controller.refreshNowPlaying();
        await controller.findSpeakers();
      },
      child: GridView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          // Keep the last row clear of the gesture bar.
          20 + MediaQuery.paddingOf(context).bottom,
        ),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.62,
        ),
        itemCount: kStations.length,
        itemBuilder: (context, i) {
          final station = kStations[i];
          return StationCard(
            station: station,
            nowPlaying: controller.nowPlaying[station.id],
            selected: controller.playingStation?.id == station.id,
            playing: controller.isPlaying,
            onTap: () => _onStationTapped(context, station),
          );
        },
      ),
    );
  }

  Future<void> _onStationTapped(BuildContext context, Station station) async {
    // Nothing to play into yet - send them to the picker instead of failing.
    if (controller.selectedZone == null) {
      await SpeakerSheet.show(context, controller);
      if (controller.selectedZone == null) return;
    }
    await controller.play(station);
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(22, compact ? 8 : 16, 22, compact ? 8 : 12),
      child: Row(
        children: [
          Text(
            'STATIONS',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 2,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              height: 1,
              color: theme.colorScheme.outlineVariant,
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../state/radio_controller.dart';
import '../theme/andon_theme.dart';
import 'grille.dart';
import 'station_card.dart';
import 'volume_knob.dart';

/// The radio itself: a walnut cabinet with a grille, a transport switch and
/// the orange knob. This is the one place the vintage reference is literal;
/// everything below it is ordinary Material.
class NowPlayingCabinet extends StatelessWidget {
  const NowPlayingCabinet({
    super.key,
    required this.controller,
    required this.onPickRoom,
    this.compact = false,
  });

  final RadioController controller;
  final VoidCallback onPickRoom;

  /// Drawn tighter when there is not much vertical room, so the controls can
  /// stay pinned instead of scrolling away.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final palette = theme.extension<AndonPalette>()!;

    final station = controller.playingStation;
    final accent = station?.accent ?? kAndonOrange;
    final zone = controller.selectedZone;
    final group = controller.selectedGroup;
    final hasRoom = zone != null;
    final playing = controller.isPlaying;
    final np = station == null ? null : controller.nowPlaying[station.id];

    return Container(
      margin: EdgeInsets.fromLTRB(16, 4, 16, compact ? 4 : 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        // The cabinet: lit on the top edge, falling into shadow at the base.
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette.walnutLight, palette.walnutDark],
        ),
        boxShadow: [
          BoxShadow(
            color: palette.cabinetShadow,
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: EdgeInsets.all(compact ? 8 : 10),
      child: Column(
        // Hug the controls. Side by side in landscape the cabinet is handed
        // loose height, and a greedy Column stretched it into a slab of empty
        // wood below the knob.
        mainAxisSize: MainAxisSize.min,
        children: [
          _RoomBar(
            label: hasRoom ? zone.name : 'Choose a room',
            detail: group != null && !group.isSolo && hasRoom
                ? 'with ${group.othersThan(zone)}'
                : null,
            onTap: onPickRoom,
          ),
          SizedBox(height: compact ? 8 : 10),

          // The grille panel - where the sound would come out.
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              color: palette.grille,
              child: GrillePanel(
                perforation: palette.grillePerforation,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    compact ? 12 : 18,
                    16,
                    compact ? 12 : 16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (playing) ...[
                            OnAirBars(color: accent, size: 11),
                            const SizedBox(width: 7),
                          ],
                          Text(
                            playing
                                ? 'ON AIR'
                                : station != null
                                ? 'READY'
                                : 'ANDON FM',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurface.withValues(alpha: 0.55),
                              letterSpacing: 2,
                              fontWeight: FontWeight.w700,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        station?.name ?? 'Pick a station',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            (compact
                                    ? theme.textTheme.titleLarge
                                    : theme.textTheme.headlineSmall)
                                ?.copyWith(
                                  color: scheme.onSurface,
                                  fontWeight: FontWeight.w600,
                                ),
                      ),
                      const SizedBox(height: 3),
                      // Minimum, not fixed - long track titles and larger
                      // font scales grow the panel instead of being cut off.
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: compact ? 20 : 34,
                        ),
                        child: Text(
                          np?.line.isNotEmpty == true
                              ? np!.line
                              : station?.dj ?? 'Four stations, four AI DJs.',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurface.withValues(alpha: 0.7),
                            height: 1.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Controls: transport on the left, the knob on the right, sitting on
          // the wood the way the originals did.
          Padding(
            padding: EdgeInsets.fromLTRB(6, compact ? 10 : 14, 6, 6),
            child: Row(
              children: [
                _TransportButton(
                  size: compact ? 56 : 68,
                  playing: playing,
                  busy: controller.isBusy,
                  enabled: hasRoom,
                  accent: accent,
                  onPressed: controller.togglePlayStop,
                ),
                const SizedBox(width: 14),
                _MuteButton(
                  size: compact ? 42 : 48,
                  muted: controller.muted,
                  enabled: hasRoom,
                  onPressed: controller.toggleMute,
                ),
                const Spacer(),
                VolumeKnob(
                  value: controller.volume,
                  muted: controller.muted,
                  enabled: hasRoom,
                  accent: accent,
                  size: compact ? 92 : 116,
                  onChanged: controller.setVolume,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoomBar extends StatelessWidget {
  const _RoomBar({
    required this.label,
    required this.detail,
    required this.onTap,
  });

  final String label;
  final String? detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.white.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              const Icon(Icons.speaker_rounded, size: 18, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (detail != null) ...[
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          detail!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.unfold_more_rounded,
                size: 18,
                color: Colors.white.withValues(alpha: 0.8),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TransportButton extends StatelessWidget {
  const _TransportButton({
    required this.size,
    required this.playing,
    required this.busy,
    required this.enabled,
    required this.accent,
    required this.onPressed,
  });

  final double size;
  final bool playing;
  final bool busy;
  final bool enabled;
  final Color accent;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Material(
        color: enabled ? accent : accent.withValues(alpha: 0.35),
        shape: const CircleBorder(),
        elevation: enabled ? 3 : 0,
        child: InkShape(
          onTap: enabled && !busy ? onPressed : null,
          child: Center(
            child: busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  )
                : Icon(
                    playing ? Icons.stop_rounded : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: size * 0.5,
                  ),
          ),
        ),
      ),
    );
  }
}

class _MuteButton extends StatelessWidget {
  const _MuteButton({
    required this.size,
    required this.muted,
    required this.enabled,
    required this.onPressed,
  });

  final double size;
  final bool muted;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Material(
        color: Colors.white.withValues(alpha: muted ? 0.24 : 0.12),
        shape: const CircleBorder(),
        child: InkShape(
          onTap: enabled ? onPressed : null,
          child: Center(
            child: Icon(
              muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
              color: Colors.white.withValues(alpha: enabled ? 0.92 : 0.4),
              size: size * 0.46,
            ),
          ),
        ),
      ),
    );
  }
}

/// InkWell clipped to the parent [Material]'s shape - keeps the ripple round
/// on the circular buttons.
class InkShape extends StatelessWidget {
  const InkShape({super.key, required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: child,
    );
  }
}

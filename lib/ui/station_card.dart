import 'package:flutter/material.dart';

import '../models/station.dart';

/// One station in the grid: artwork, who is DJing, and what is on air now.
class StationCard extends StatelessWidget {
  const StationCard({
    super.key,
    required this.station,
    required this.nowPlaying,
    required this.selected,
    required this.playing,
    required this.onTap,
  });

  final Station station;
  final NowPlaying? nowPlaying;

  /// This is the station the chosen room is carrying.
  final bool selected;

  /// ...and it is actually playing right now.
  final bool playing;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final offline = nowPlaying != null && !nowPlaying!.online;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: selected
            ? scheme.surfaceContainerHigh
            : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected ? station.accent : scheme.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _Artwork(
                    station: station,
                    playing: playing && selected,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  station.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.3,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  station.dj,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 8),
                _NowPlayingLine(
                  station: station,
                  nowPlaying: nowPlaying,
                  offline: offline,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Artwork extends StatelessWidget {
  const _Artwork({required this.station, required this.playing});

  final Station station;
  final bool playing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: station.accent.withValues(alpha: 0.14)),
          Image.network(
            station.artUrl,
            fit: BoxFit.cover,
            // Artwork is a nicety - a station with no art still works.
            errorBuilder: (_, _, _) => _ArtworkFallback(station: station),
            loadingBuilder: (context, child, progress) =>
                progress == null ? child : _ArtworkFallback(station: station),
          ),
          if (playing)
            Positioned(
              left: 8,
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: scheme.surface.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OnAirBars(color: station.accent),
                    const SizedBox(width: 6),
                    Text(
                      'ON AIR',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ArtworkFallback extends StatelessWidget {
  const _ArtworkFallback({required this.station});

  final Station station;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: station.accent.withValues(alpha: 0.16),
      alignment: Alignment.center,
      child: Icon(Icons.radio_rounded, color: station.accent, size: 32),
    );
  }
}

class _NowPlayingLine extends StatelessWidget {
  const _NowPlayingLine({
    required this.station,
    required this.nowPlaying,
    required this.offline,
  });

  final Station station;
  final NowPlaying? nowPlaying;
  final bool offline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (offline) {
      return Text(
        'Off air',
        style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
      );
    }

    // No fixed height here: the artwork above is in an Expanded, so it gives
    // up whatever room the text needs. A hard height clipped the second line
    // as soon as the system font scale went up.
    final line = nowPlaying?.line ?? '';
    return line.isEmpty
        ? Text(
            station.tagline,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
              height: 1.25,
            ),
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 3,
                height: 28,
                margin: const EdgeInsets.only(right: 8, top: 1),
                decoration: BoxDecoration(
                  color: station.accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: Text(
                  line,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          );
  }
}

/// Three little bars bouncing, the universal "this is live" tell.
class OnAirBars extends StatefulWidget {
  const OnAirBars({super.key, required this.color, this.size = 10});

  final Color color;
  final double size;

  @override
  State<OnAirBars> createState() => _OnAirBarsState();
}

class _OnAirBarsState extends State<OnAirBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(3, (i) {
              // Stagger the phases so they never move as a block.
              final phase = (_c.value + i * 0.33) % 1.0;
              final t = (phase < 0.5 ? phase : 1 - phase) * 2;
              return Container(
                width: widget.size * 0.22,
                height: widget.size * (0.35 + 0.65 * t),
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(1),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}

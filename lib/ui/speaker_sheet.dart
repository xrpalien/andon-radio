import 'package:flutter/material.dart';

import '../models/sonos.dart';
import '../state/radio_controller.dart';

/// Room picker and grouping control.
///
/// Tapping a room chooses where playback goes. The link button on each row
/// adds or removes that room from the chosen room's group, so the whole house
/// can be wired together without leaving the app.
class SpeakerSheet extends StatelessWidget {
  const SpeakerSheet({super.key, required this.controller});

  final RadioController controller;

  static Future<void> show(BuildContext context, RadioController controller) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SpeakerSheet(controller: controller),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final household = controller.household;
        final zones = household.allZones;
        final group = controller.selectedGroup;
        final searching = controller.status == DiscoveryStatus.searching;

        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.8,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 4, 12, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Play in', style: theme.textTheme.titleLarge),
                            const SizedBox(height: 2),
                            Text(
                              zones.isEmpty
                                  ? 'No players found'
                                  : group == null || group.isSolo
                                  ? '${zones.length} rooms · link rooms to play together'
                                  : 'Playing in ${group.members.length} rooms',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: searching ? null : controller.findSpeakers,
                        tooltip: 'Search again',
                        icon: searching
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.refresh_rounded),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: zones.isEmpty
                      ? _EmptyState(controller: controller)
                      : ListView.separated(
                          shrinkWrap: true,
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                          itemCount: zones.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 2),
                          itemBuilder: (context, i) =>
                              _ZoneTile(zone: zones[i], controller: controller),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ZoneTile extends StatelessWidget {
  const _ZoneTile({required this.zone, required this.controller});

  final SonosZone zone;
  final RadioController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final household = controller.household;
    final group = household.groupFor(zone);
    final selected = controller.selectedZone?.uuid == zone.uuid;
    final grouped = controller.isGroupedWithSelection(zone);
    final canToggle = controller.canToggleGrouping(zone);
    final busy = controller.busyZoneUuid == zone.uuid;

    final isCoordinator = group?.coordinator.uuid == zone.uuid;
    final inMultiRoomGroup = group != null && !group.isSolo;

    // The line that saves you wondering why four rooms lit up at once.
    final String? subtitle;
    if (inMultiRoomGroup && isCoordinator) {
      subtitle = 'Grouped with ${group.otherMemberNames}';
    } else if (inMultiRoomGroup) {
      subtitle = 'In ${group.coordinator.name}\'s group';
    } else {
      subtitle = null;
    }

    return ListTile(
      onTap: () {
        controller.selectZone(zone);
        Navigator.of(context).pop();
      },
      selected: selected,
      selectedTileColor: scheme.surfaceContainerHighest,
      contentPadding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: selected
              ? scheme.primary.withValues(alpha: 0.16)
              : scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          _iconFor(zone.icon),
          size: 21,
          color: selected ? scheme.primary : scheme.onSurfaceVariant,
        ),
      ),
      title: Text(
        zone.name,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (selected)
            Icon(Icons.check_circle_rounded, size: 22, color: scheme.primary),
          if (busy)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (canToggle)
            IconButton(
              onPressed: () => controller.setGrouped(zone, !grouped),
              tooltip: grouped
                  ? 'Remove ${zone.name} from the group'
                  : 'Play ${zone.name} with this group',
              isSelected: grouped,
              icon: const Icon(Icons.add_link_rounded),
              selectedIcon: const Icon(Icons.link_off_rounded),
              style: IconButton.styleFrom(
                foregroundColor: scheme.onSurfaceVariant,
                backgroundColor: grouped
                    ? scheme.primary.withValues(alpha: 0.14)
                    : null,
                highlightColor: scheme.primary.withValues(alpha: 0.1),
              ),
            )
          else
            // The group's own coordinator: nothing to link it to but itself.
            const SizedBox(width: 48),
        ],
      ),
    );
  }

  /// Map Sonos's room icon tokens onto Material icons.
  static IconData _iconFor(String token) {
    final key = token.split(':').last;
    return switch (key) {
      'kitchen' => Icons.countertops_rounded,
      'living' || 'family' => Icons.weekend_rounded,
      'tvroom' || 'media' => Icons.tv_rounded,
      'bedroom' || 'masterbedroom' => Icons.bed_rounded,
      'dining' => Icons.dining_rounded,
      'bathroom' => Icons.bathtub_rounded,
      'office' || 'den' => Icons.desk_rounded,
      'garage' => Icons.garage_rounded,
      'patio' || 'garden' || 'porch' => Icons.deck_rounded,
      'portable' || 'roam' || 'move' => Icons.speaker_rounded,
      _ => Icons.speaker_group_rounded,
    };
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.controller});

  final RadioController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final searching = controller.status == DiscoveryStatus.searching;

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 12, 28, 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            searching ? Icons.wifi_find_rounded : Icons.wifi_off_rounded,
            size: 40,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 14),
          Text(
            searching ? 'Looking for players…' : 'No Sonos players found',
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            searching
                ? 'Checking the local network.'
                : 'Make sure this phone is on the same Wi-Fi as your speakers — '
                      'not a guest network, and not on mobile data.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.tonalIcon(
            onPressed: searching ? null : controller.findSpeakers,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Search again'),
          ),
        ],
      ),
    );
  }
}

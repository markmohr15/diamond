import 'package:diamond/src/events/generated/events.dart';
import 'package:flutter/material.dart';

/// Keys the widget tests resolve against. Production code has no reason to
/// look them up.
@visibleForTesting
Key trajectoryKey(Trajectory trajectory) =>
    Key('trajectory-${trajectoryValues.reverse[trajectory]}');

/// Display labels, in the row's fixed order (§11.1's five buttons).
const _labels = <Trajectory, String>{
  Trajectory.GROUND: 'Ground',
  Trajectory.LINE: 'Line',
  Trajectory.FLY: 'Fly',
  Trajectory.POPUP: 'Popup',
  Trajectory.BUNT: 'Bunt',
};

/// §11.1's trajectory row: five buttons, one selection, shown once the
/// landing is down. Selection is repeatable — a re-tap re-chooses, since
/// "line or fly?" is a legitimate second thought mid-play.
class TrajectoryRow extends StatelessWidget {
  const TrajectoryRow({
    required this.selected,
    required this.onChosen,
    super.key,
  });

  final Trajectory? selected;
  final ValueChanged<Trajectory> onChosen;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final entry in _labels.entries)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ChoiceChip(
              key: trajectoryKey(entry.key),
              label: Text(entry.value),
              selected: selected == entry.key,
              onSelected: (_) => onChosen(entry.key),
            ),
          ),
      ],
    );
  }
}

import 'package:diamond/src/events/generated/events.dart';
import 'package:flutter/material.dart';

/// Keys the widget tests resolve against. Production code has no reason to
/// look them up.
@visibleForTesting
Key trajectoryKey(Trajectory trajectory) =>
    Key('trajectory-${trajectoryValues.reverse[trajectory]}');

/// Display labels, in the row's fixed order (§11.1's five buttons).
const _labels = <Trajectory, String>{
  Trajectory.GROUND: 'Grounder',
  Trajectory.LINE: 'Line drive',
  Trajectory.FLY: 'Fly ball',
  Trajectory.POPUP: 'Popup',
  Trajectory.BUNT: 'Bunt',
};

/// The display name of one trajectory — the header chip and the modal share
/// this vocabulary.
String trajectoryLabel(Trajectory trajectory) => _labels[trajectory]!;

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
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final entry in _labels.entries)
          ChoiceChip(
            key: trajectoryKey(entry.key),
            label: Text(entry.value),
            selected: selected == entry.key,
            onSelected: (_) => onChosen(entry.key),
          ),
      ],
    );
  }
}

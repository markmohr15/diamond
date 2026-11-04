import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/rules/batted_ball.dart';
import 'package:flutter/material.dart';

/// Keys the widget tests resolve against. Production code has no reason to
/// look them up.
@visibleForTesting
Key trajectoryKey(Trajectory trajectory) =>
    Key('trajectory-${trajectoryValues.reverse[trajectory]}');

/// The row's *Bunt* chip, which opens the ground-or-air pair rather than
/// choosing a trajectory itself.
@visibleForTesting
const Key trajectoryBuntKey = Key('trajectory-bunt-pick');

/// Back from the bunt pair to the five-option row.
@visibleForTesting
const Key trajectoryBackKey = Key('trajectory-back');

/// Display labels, in the row's fixed order (§11.1's five buttons). *Bunt*
/// is not a trajectory on its own: it opens [_buntLabels].
const _labels = <Trajectory, String>{
  Trajectory.GROUND: 'Grounder',
  Trajectory.LINE: 'Line drive',
  Trajectory.FLY: 'Fly ball',
  Trajectory.POPUP: 'Popup',
};

/// A bunt still has to say whether it was on the ground or in the air —
/// that is what decides whether it can be caught (DIA-019 M).
const _buntLabels = <Trajectory, String>{
  Trajectory.BUNT: 'Bunt on the ground',
  Trajectory.BUNT_AIR: 'Bunt in the air',
};

/// The display name of one trajectory — the header chip and the modal share
/// this vocabulary.
String trajectoryLabel(Trajectory trajectory) =>
    _labels[trajectory] ?? _buntLabels[trajectory]!;

/// §11.1's trajectory row: five buttons, one selection, shown once the
/// landing is down. Selection is repeatable — a re-tap re-chooses, since
/// "line or fly?" is a legitimate second thought mid-play.
///
/// *Bunt* opens a second pair, on the ground or in the air. When the outcome
/// sheet already said she bunted ([bunted]) the pair is all there is: the
/// five-option question was answered there, and only the half it could not
/// answer is asked. Either way the batted ball records the same trajectory.
class TrajectoryRow extends StatefulWidget {
  const TrajectoryRow({
    required this.selected,
    required this.onChosen,
    this.bunted = false,
    super.key,
  });

  final Trajectory? selected;
  final ValueChanged<Trajectory> onChosen;
  final bool bunted;

  @override
  State<TrajectoryRow> createState() => _TrajectoryRowState();
}

class _TrajectoryRowState extends State<TrajectoryRow> {
  late bool _bunt = widget.bunted || isBunt(widget.selected);

  @override
  Widget build(BuildContext context) {
    Widget chip(Key key, String label, Trajectory trajectory) => ChoiceChip(
      key: key,
      label: Text(label),
      selected: widget.selected == trajectory,
      onSelected: (_) => widget.onChosen(trajectory),
    );

    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: _bunt
          ? [
              // Sheet said bunt: nothing to go back to — changing that
              // answer is the outcome sheet's job, through undo.
              if (!widget.bunted)
                IconButton(
                  key: trajectoryBackKey,
                  tooltip: 'Not a bunt',
                  onPressed: () => setState(() => _bunt = false),
                  icon: const Icon(Icons.arrow_back),
                ),
              for (final entry in _buntLabels.entries)
                chip(trajectoryKey(entry.key), entry.value, entry.key),
            ]
          : [
              for (final entry in _labels.entries)
                chip(trajectoryKey(entry.key), entry.value, entry.key),
              ChoiceChip(
                key: trajectoryBuntKey,
                label: const Text('Bunt'),
                selected: false,
                onSelected: (_) => setState(() => _bunt = true),
              ),
            ],
    );
  }
}

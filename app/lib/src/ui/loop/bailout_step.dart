import 'package:diamond/src/events/generated/events.dart';
import 'package:flutter/material.dart';

/// §11.2's bottom rung (v0.41): BALL / STRIKE / FOUL / IN PLAY, filling the
/// step surface — chaos mode, so the targets are enormous and there are only
/// four of them.
///
/// STRIKE records `strike_unspecified` (§4.1): the count advanced and the
/// scorer doesn't know how — called, swinging, or possibly an uncaught foul.
/// FOUL earns its button at exactly two strikes, where a foul is a no-op and
/// a strike is strike three; the tell is whether the at-bat ended, which the
/// field shows even in chaos. Below two strikes, a foul mistapped as STRIKE
/// costs nothing but a foul stat.
class BailoutStep extends StatelessWidget {
  const BailoutStep({required this.onChosen, super.key});

  final ValueChanged<Outcome> onChosen;

  static const _rows = <(String, Outcome)>[
    ('BALL', Outcome.BALL),
    ('STRIKE', Outcome.STRIKE_UNSPECIFIED),
    ('FOUL', Outcome.FOUL),
    ('IN PLAY', Outcome.IN_PLAY),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (label, outcome) in _rows)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: FilledButton.tonal(
                  onPressed: () => onChosen(outcome),
                  style: FilledButton.styleFrom(
                    textStyle: Theme.of(context).textTheme.displayMedium,
                  ),
                  child: Text(label),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

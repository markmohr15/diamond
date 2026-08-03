import 'package:diamond/src/events/generated/events.dart';
import 'package:flutter/material.dart';

/// Key the widget tests resolve against. Production code has no reason to
/// look it up.
@visibleForTesting
const Key outcomeConfirmKey = Key('outcomeConfirm');

/// Display labels for the outcomes the M1 row offers. `ball_intentional`,
/// `no_pitch`, and the batter-action-dependent reads are deliberately absent
/// from the row for now — rare enough that their tap real estate costs more
/// than a between-pitches correction does (flagged in DIA-007a's PR).
const _rowOutcomes = <Outcome, String>{
  Outcome.BALL: 'Ball',
  Outcome.CALLED_STRIKE: 'Called strike',
  Outcome.SWINGING_STRIKE: 'Swinging strike',
  Outcome.SWINGING_STRIKE_BLOCKED: 'Swinging (in dirt)',
  Outcome.FOUL: 'Foul',
  Outcome.FOUL_BUNT: 'Foul bunt',
  Outcome.FOUL_TIP: 'Foul tip',
  Outcome.IN_PLAY: 'In play',
  Outcome.HIT_BY_PITCH: 'HBP',
  Outcome.ILLEGAL_PITCH: 'Illegal pitch',
  Outcome.UNKNOWN: 'Unknown',
};

/// §11.1's outcome step: one big confirm carrying Diamond's suggestion, and
/// the full override row beneath it.
///
/// The suggestion is only ever a head start — the ump's call is the truth,
/// not the location, so nothing commits without a tap. With no location
/// captured there is no suggestion and the row alone is shown.
///
/// This surface belongs to the **scorer's** duty bundle (§12.2, v0.39). Under
/// the M2 split it renders on the primary only; the caller's device never
/// shows these buttons.
class OutcomeStep extends StatelessWidget {
  const OutcomeStep({
    required this.suggestion,
    required this.onChosen,
    super.key,
  });

  final Outcome? suggestion;
  final ValueChanged<Outcome> onChosen;

  @override
  Widget build(BuildContext context) {
    final suggested = suggestion;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (suggested != null) ...[
            FilledButton(
              key: outcomeConfirmKey,
              onPressed: () => onChosen(suggested),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 22),
                textStyle: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              child: Text(_rowOutcomes[suggested]!),
            ),
            const SizedBox(height: 20),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (final entry in _rowOutcomes.entries)
                // The suggestion already has the big button; repeating it in
                // the row would be two controls for one meaning.
                if (entry.key != suggested)
                  OutlinedButton(
                    onPressed: () => onChosen(entry.key),
                    child: Text(entry.value),
                  ),
            ],
          ),
        ],
      ),
    );
  }
}

import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/ui/theme/brand_metrics.dart';
import 'package:flutter/material.dart';

/// Key the widget tests resolve against. Production code has no reason to
/// look it up.
@visibleForTesting
const Key outcomeConfirmKey = Key('outcomeConfirm');
@visibleForTesting
const Key outcomeInPlayKey = Key('outcomeInPlay');
@visibleForTesting
const Key outcomeD3kKey = Key('outcomeD3k');

/// Display labels for the outcomes the M1 row offers. `ball_intentional`,
/// `no_pitch`, and the batter-action-dependent reads are deliberately absent
/// from the row for now — rare enough that their tap real estate costs more
/// than a between-pitches correction does (flagged in DIA-007a's PR).
const _rowOutcomes = <Outcome, String>{
  Outcome.BALL: 'Ball',
  Outcome.CALLED_STRIKE: 'Called strike',
  Outcome.SWINGING_STRIKE: 'Swinging strike',
  Outcome.FOUL: 'Foul',
  Outcome.FOUL_BUNT: 'Foul bunt',
  Outcome.FOUL_TIP: 'Foul tip',
  Outcome.IN_PLAY: 'In play',
  Outcome.HIT_BY_PITCH: 'HBP',
  Outcome.CATCHER_INTERFERENCE: "Catcher's interference",
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
    this.onDroppedThirdStrike,
    super.key,
  });

  final Outcome? suggestion;
  final ValueChanged<Outcome> onChosen;

  /// Set only at two strikes with the batter entitled to run (§11.3). A
  /// dropped third strike is not a note on a strikeout — it is an outcome
  /// that opens a surface, the equivalent of putting the ball in play, and
  /// belongs where the scorer looks for it rather than in a prompt after
  /// the fact.
  final VoidCallback? onDroppedThirdStrike;

  /// The two outcomes worth a full row of their own: the suggestion, and
  /// in play.
  Widget _bigButton(
    BuildContext context, {
    required Key key,
    required String label,
    required VoidCallback onPressed,
  }) {
    return FilledButton(
      key: key,
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: BrandMetrics.space2xl),
        textStyle: Theme.of(context).textTheme.headlineLarge,
      ),
      child: Text(label),
    );
  }

  @override
  Widget build(BuildContext context) {
    final suggested = suggestion;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        // Sized to content: this renders inside a centered dialog (v0.43's
        // popup design), which is only as big as necessary.
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (suggested != null) ...[
            _bigButton(
              context,
              key: outcomeConfirmKey,
              label: _rowOutcomes[suggested]!,
              onPressed: () => onChosen(suggested),
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
                // the row would be two controls for one meaning. `in_play`
                // has its own, below.
                if (entry.key != suggested && entry.key != Outcome.IN_PLAY)
                  OutlinedButton(
                    onPressed: () => onChosen(entry.key),
                    style: OutlinedButton.styleFrom(
                      textStyle: Theme.of(context).textTheme.titleMedium,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 18,
                      ),
                    ),
                    child: Text(entry.value),
                  ),
            ],
          ),
          // In play is the other outcome that changes everything — it opens
          // the whole field surface — so it gets the suggestion's weight and
          // a row of its own, in the same place every time. Never suggested
          // (§11.1: contact isn't inferable from location), always here.
          const SizedBox(height: 20),
          _bigButton(
            context,
            key: outcomeInPlayKey,
            label: _rowOutcomes[Outcome.IN_PLAY]!,
            onPressed: () => onChosen(Outcome.IN_PLAY),
          ),
          // The other outcome that opens a surface, and only ever offered
          // when the rules let her run. "Dropped" rather than the more
          // correct "uncaught" because it is what scorers say — and it is
          // already the wire word (§4.3's `dropped_third_strike`).
          if (onDroppedThirdStrike != null) ...[
            const SizedBox(height: 12),
            _bigButton(
              context,
              key: outcomeD3kKey,
              label: 'Dropped 3rd strike',
              onPressed: onDroppedThirdStrike!,
            ),
          ],
        ],
      ),
    );
  }
}

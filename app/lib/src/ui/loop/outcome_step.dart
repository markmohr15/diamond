import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/ui/theme/brand_metrics.dart';
import 'package:flutter/material.dart';

/// Keys the widget tests resolve against. Production code has no reason to
/// look them up.
@visibleForTesting
const Key outcomeInPlayKey = Key('outcomeInPlay');
@visibleForTesting
const Key outcomeD3kKey = Key('outcomeD3k');
@visibleForTesting
Key outcomeKey(Outcome outcome) =>
    Key('outcome-${outcomeValues.reverse[outcome]}');

/// The five outcomes that account for nearly every pitch, in frequency order
/// (Claude Design panel 5A).
///
/// **Ranked by how often a thing gets tapped, which is fixed and knowable.**
/// The sheet used to rank by Diamond's location suggestion, and that could not
/// do the job: `suggestOutcome` returned only `ball` or `called_strike` —
/// location knows nothing about whether the batter swung — so its most
/// confident case was its worst one, since a pitch *in* the zone is more often
/// swung at than taken. It promoted the wrong button and called it help.
const _primaryOutcomes = <Outcome, String>{
  Outcome.BALL: 'Ball',
  Outcome.CALLED_STRIKE: 'Called strike',
  Outcome.SWINGING_STRIKE: 'Swinging',
  Outcome.FOUL: 'Foul',
  Outcome.IN_PLAY: 'In play',
};

/// Everything else, under an "everything else" rule rather than a judgment
/// about each one.
///
/// `strike_unspecified` earns its place by protecting the count (§11.2): it
/// says *a strike happened and I missed which kind*, which still advances the
/// count correctly — where `unknown` says *I did not see it* and leaves the
/// count ambiguous, turning the HUD amber (§12.5). Without it the scorer must
/// either invent a fact or throw away one she had.
///
/// `ball_intentional` is here from v0.51: four intentional balls is a
/// different story from four missed spots, for the pitcher's line and for
/// scouting, and it had no writer anywhere.
const _rareOutcomes = <Outcome, String>{
  Outcome.HIT_BY_PITCH: 'HBP',
  Outcome.CATCHER_INTERFERENCE: "Catcher's interference",
  Outcome.ILLEGAL_PITCH: 'Illegal pitch',
  Outcome.FOUL_TIP: 'Foul tip',
  Outcome.FOUL_BUNT: 'Foul bunt',
  Outcome.BALL_INTENTIONAL: 'Intentional ball',
  Outcome.STRIKE_UNSPECIFIED: 'Strike (unspecified)',
  Outcome.UNKNOWN: 'Unknown',
};

/// §11.1's outcome step: five primaries at fixed positions, then everything
/// else.
///
/// **Nothing here consults the pitch's location.** The ump's call is the
/// truth and location is not evidence of it, so the sheet looks identical
/// whatever was captured — which is what makes the five positions learnable.
///
/// This surface belongs to the **scorer's** duty bundle (§12.2, v0.39). Under
/// the M2 split it renders on the primary only; the caller's device never
/// shows these buttons.
class OutcomeStep extends StatelessWidget {
  const OutcomeStep({
    required this.onChosen,
    this.onDroppedThirdStrike,
    super.key,
  });

  final ValueChanged<Outcome> onChosen;

  /// Set only at two strikes with the batter entitled to run (§11.3). A
  /// dropped third strike is not a note on a strikeout — it is an outcome
  /// that opens a surface, the equivalent of putting the ball in play, and
  /// belongs where the scorer looks for it rather than in a prompt after
  /// the fact.
  final VoidCallback? onDroppedThirdStrike;

  Widget _primary(
    BuildContext context, {
    required Key key,
    required String label,
    required VoidCallback onPressed,
  }) => FilledButton(
    key: key,
    onPressed: onPressed,
    style: FilledButton.styleFrom(
      padding: const EdgeInsets.symmetric(vertical: BrandMetrics.space2xl),
      textStyle: Theme.of(context).textTheme.headlineLarge,
    ),
    child: Text(label),
  );

  @override
  Widget build(BuildContext context) {
    // Scrollable because the sheet can be tall: six primaries when she may run
    // on strike three, plus eight rare chips. A `Dialog` sizes to its content
    // and does not scroll, so without this the bottom clips on a short screen
    // — and the app is phone-capable (§21). Costs nothing when it fits.
    return SingleChildScrollView(
      padding: const EdgeInsets.all(BrandMetrics.spaceLg),
      child: Column(
        // Sized to content: this renders inside a centered dialog (v0.43's
        // popup design), which is only as big as necessary.
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final entry in _primaryOutcomes.entries) ...[
            _primary(
              context,
              // `In play` keeps a name of its own: it is the one primary the
              // rest of the app navigates to.
              key: entry.key == Outcome.IN_PLAY
                  ? outcomeInPlayKey
                  : outcomeKey(entry.key),
              label: entry.value,
              onPressed: () => onChosen(entry.key),
            ),
            const SizedBox(height: BrandMetrics.spaceMd),
          ],

          // The other outcome that opens a surface, and only ever offered
          // when the rules let her run. "Dropped" rather than the more
          // correct "uncaught" because it is what scorers say — and it is
          // already the wire word (§4.3's `dropped_third_strike`).
          if (onDroppedThirdStrike != null) ...[
            _primary(
              context,
              key: outcomeD3kKey,
              label: 'Dropped 3rd strike',
              onPressed: onDroppedThirdStrike!,
            ),
            const SizedBox(height: BrandMetrics.spaceMd),
          ],

          const SizedBox(height: BrandMetrics.spaceSm),
          Wrap(
            spacing: BrandMetrics.spaceSm,
            runSpacing: BrandMetrics.spaceSm,
            alignment: WrapAlignment.center,
            children: [
              for (final entry in _rareOutcomes.entries)
                OutlinedButton(
                  key: outcomeKey(entry.key),
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

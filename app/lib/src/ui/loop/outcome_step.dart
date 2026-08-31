import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/ui/theme/brand_metrics.dart';
import 'package:diamond/src/ui/theme/brand_type.dart';
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
@visibleForTesting
Key batterActionKey(BatterAction action) =>
    Key('batterAction-${batterActionValues.reverse[action]}');
@visibleForTesting
Key getawayKey(Cause cause) => Key('getaway-${causeValues.reverse[cause]}');

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
  // "Swinging" alone does not say *strike* — it reads as a description of the
  // swing rather than the call. Paired with "Called strike" above it, the two
  // read as the set they are (Mark, 2026-08-28).
  Outcome.SWINGING_STRIKE: 'Swinging strike',
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

/// What she was doing at the plate (§4.1), orthogonal to what the pitch did.
///
/// **`slap` is offered in both sports for M1** and should be gated to fastpitch
/// by `RuleSet` — DIA-017. Offering it to a baseball scorer is a wrong option
/// in a list; blocking this on a config refactor that touches every
/// sport-dependent rule is worse, and the gate has one obvious home when it
/// exists.
const _batterActions = <BatterAction, String>{
  BatterAction.BUNT: 'Bunt',
  BatterAction.SLAP: 'Slap',
  BatterAction.SLASH: 'Slash',
};

/// The ball got away, and which (§13.2). Offered only with a runner aboard:
/// rule 9.13 charges a wild pitch or passed ball on its *consequence*, so with
/// the bases empty there is nothing to charge and nothing to ask.
const _getaways = <Cause, String>{
  Cause.WILD_PITCH: 'Wild pitch',
  Cause.PASSED_BALL: 'Passed ball',
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
class OutcomeStep extends StatefulWidget {
  const OutcomeStep({
    required this.onChosen,
    this.runnersAboard = false,
    this.onDroppedThirdStrike,
    super.key,
  });

  /// The outcome, and the two modifiers that describe the same pitch. One
  /// callback rather than three, because they are facts about one event — a
  /// separate "modifier committed" path would let them disagree about which
  /// pitch they described.
  final void Function(Outcome outcome, BatterAction? action, Cause? getaway)
  onChosen;

  /// Whether anybody is on base. Gates the getaway chips: see [_getaways].
  final bool runnersAboard;

  /// Set only at two strikes with the batter entitled to run (§11.3). A
  /// dropped third strike is not a note on a strikeout — it is an outcome
  /// that opens a surface, the equivalent of putting the ball in play, and
  /// belongs where the scorer looks for it rather than in a prompt after
  /// the fact.
  final VoidCallback? onDroppedThirdStrike;

  @override
  State<OutcomeStep> createState() => _OutcomeStepState();
}

class _OutcomeStepState extends State<OutcomeStep> {
  /// Sticky across the outcome tap, and deliberately not sticky across
  /// pitches: posture is a per-pitch observation, and carrying it forward
  /// would record a bunt she did not show.
  BatterAction? _action;
  Cause? _getaway;

  /// A bordered group with a small label.
  ///
  /// Deliberately quiet — a hairline and an eyebrow, not a card. The sheet's
  /// weight belongs to the five primaries (§23.1.1: data-ink first, and the
  /// datum here is the outcome). These sections exist to say *these controls
  /// answer one question*, which a gap alone does not: the chips all look
  /// alike, so nothing distinguished "what the batter did" from "what the ball
  /// did" from "everything else".
  ///
  /// The label is `BrandType.eyebrow` — mono, small caps, wide tracking —
  /// because a section name is read as a tag rather than as prose (§23.5), the
  /// same style the count HUD's COUNT UNSURE uses.
  Widget _section(BuildContext context, String label, Widget child) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: BrandMetrics.spaceMd),
      padding: const EdgeInsets.all(BrandMetrics.spaceMd),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(BrandMetrics.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            style: BrandType.eyebrow.copyWith(color: scheme.outline),
          ),
          const SizedBox(height: BrandMetrics.spaceSm),
          child,
        ],
      ),
    );
  }

  Widget _chips(List<Widget> children) => Wrap(
    spacing: BrandMetrics.spaceSm,
    runSpacing: BrandMetrics.spaceSm,
    alignment: WrapAlignment.center,
    children: children,
  );

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
          // 5A's "AND THEN" tier. Above the primaries rather than below,
          // because it is context the outcome is read *in*: "bunt, foul" is
          // one observation, and choosing the posture after committing the
          // outcome would mean two taps describing one pitch in the wrong
          // order.
          // Both of these sections hold **toggles**: tapping one lights it
          // and nothing commits. The primaries below commit. That difference
          // is what the borders really mark, and it is why `Dropped 3rd
          // strike` stays below with `In play` rather than joining the
          // getaways it resembles — it leaves the screen when tapped, and a
          // shared border would promise otherwise.
          _section(
            context,
            'AT THE PLATE',
            _chips([
              for (final entry in _batterActions.entries)
                FilterChip(
                  key: batterActionKey(entry.key),
                  label: Text(entry.value),
                  selected: _action == entry.key,
                  // Toggling off matters: a mis-tap is corrected here rather
                  // than by committing the pitch and undoing it.
                  onSelected: (on) =>
                      setState(() => _action = on ? entry.key : null),
                ),
            ]),
          ),
          if (widget.runnersAboard)
            _section(
              context,
              'GOT AWAY',
              _chips([
                for (final entry in _getaways.entries)
                  FilterChip(
                    key: getawayKey(entry.key),
                    label: Text(entry.value),
                    selected: _getaway == entry.key,
                    onSelected: (on) =>
                        setState(() => _getaway = on ? entry.key : null),
                  ),
              ]),
            ),
          const SizedBox(height: BrandMetrics.spaceLg),
          for (final entry in _primaryOutcomes.entries) ...[
            _primary(
              context,
              // `In play` keeps a name of its own: it is the one primary the
              // rest of the app navigates to.
              key: entry.key == Outcome.IN_PLAY
                  ? outcomeInPlayKey
                  : outcomeKey(entry.key),
              label: entry.value,
              onPressed: () => widget.onChosen(entry.key, _action, _getaway),
            ),
            const SizedBox(height: BrandMetrics.spaceMd),
          ],

          // The other outcome that opens a surface, and only ever offered
          // when the rules let her run. "Dropped" rather than the more
          // correct "uncaught" because it is what scorers say — and it is
          // already the wire word (§4.3's `dropped_third_strike`).
          if (widget.onDroppedThirdStrike != null) ...[
            _primary(
              context,
              key: outcomeD3kKey,
              label: 'Dropped 3rd strike',
              onPressed: widget.onDroppedThirdStrike!,
            ),
            const SizedBox(height: BrandMetrics.spaceMd),
          ],

          _section(
            context,
            'EVERYTHING ELSE',
            _chips([
              for (final entry in _rareOutcomes.entries)
                OutlinedButton(
                  key: outcomeKey(entry.key),
                  onPressed: () =>
                      widget.onChosen(entry.key, _action, _getaway),
                  child: Text(entry.value),
                ),
            ]),
          ),
        ],
      ),
    );
  }
}

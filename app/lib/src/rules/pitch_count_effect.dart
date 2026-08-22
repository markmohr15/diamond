import 'package:diamond/src/events/generated/events.dart';

/// The result of folding one [Outcome] into a (balls, strikes) count.
/// Shared by the real fold and by back-inference's enumeration (spec
/// §4.1) — one place that knows foul-at-2-strikes-is-a-no-op and
/// foul-tip/foul-bunt-can-be-strike-three, so the two never drift apart.
class PitchCountEffect {
  const PitchCountEffect({
    required this.balls,
    required this.strikes,
    required this.endsPlateAppearance,
    required this.strikesAdvanced,
  });

  final int balls;
  final int strikes;

  /// True when this pitch concludes the at-bat: ball 4, strike 3, a ball
  /// hit into play, or a hit-by-pitch.
  final bool endsPlateAppearance;

  /// True when this specific pitch actually moved the strike count. False
  /// for a `foul` that landed on an already-2-strikes count (a no-op) —
  /// distinct from `strikes` itself, since back-inference needs to know
  /// whether THIS pitch had any effect at all, not just the resulting count.
  final bool strikesAdvanced;
}

/// `outcome` should not be [Outcome.UNKNOWN] — the fold handles unknown
/// pitches specially (they don't touch the count at all; see
/// game_state_fold.dart), never by routing them through here.
PitchCountEffect applyPitchCountEffect(
  int balls,
  int strikes,
  Outcome outcome,
) {
  switch (outcome) {
    case Outcome.BALL:
    case Outcome.BALL_INTENTIONAL:
    case Outcome.ILLEGAL_PITCH: // softball: illegal pitch is a ball (spec §4.1)
      final b = balls + 1;
      return PitchCountEffect(
        balls: b,
        strikes: strikes,
        endsPlateAppearance: b >= 4,
        strikesAdvanced: false,
      );

    case Outcome.CALLED_STRIKE:
    case Outcome.SWINGING_STRIKE:
    case Outcome.SWINGING_STRIKE_BLOCKED:
    // §11.2 bailout (v0.41): kind unknown — called, swinging, or possibly an
    // uncaught foul — but the count advanced, which is the part that must be
    // right. At two strikes the scorer distinguishes FOUL from STRIKE by
    // whether the at-bat ended, so strike three here is a real strike three.
    case Outcome.STRIKE_UNSPECIFIED:
    case Outcome.FOUL_TIP: // caught by definition — always a strike (spec §4.1)
    case Outcome.FOUL_BUNT: // strike three on a 2-strike bunt foul (spec §4.1)
      final s = strikes + 1;
      return PitchCountEffect(
        balls: balls,
        strikes: s,
        endsPlateAppearance: s >= 3,
        strikesAdvanced: true,
      );

    case Outcome.FOUL:
      // A plain foul can never be strike three — a no-op once strikes==2.
      if (strikes >= 2) {
        return PitchCountEffect(
          balls: balls,
          strikes: strikes,
          endsPlateAppearance: false,
          strikesAdvanced: false,
        );
      }
      final s = strikes + 1;
      return PitchCountEffect(
        balls: balls,
        strikes: s,
        endsPlateAppearance: false, // s < 3 here since strikes was < 2
        strikesAdvanced: true,
      );

    case Outcome.IN_PLAY:
    case Outcome.HIT_BY_PITCH:
    // Catcher's interference (§4.1 v0.43): dead ball, no count effect, PA
    // over, batter awarded first — structurally the HBP pattern.
    case Outcome.CATCHER_INTERFERENCE:
      return PitchCountEffect(
        balls: balls,
        strikes: strikes,
        endsPlateAppearance: true,
        strikesAdvanced: false,
      );

    case Outcome.NO_PITCH:
    case Outcome.UNKNOWN:
      return PitchCountEffect(
        balls: balls,
        strikes: strikes,
        endsPlateAppearance: false,
        strikesAdvanced: false,
      );
  }
}

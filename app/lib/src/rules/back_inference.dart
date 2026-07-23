import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/rules/pitch_count_effect.dart';

/// Attempts to retroactively resolve every `unknown`-outcome pitch in
/// [span] against a `CountCorrection` checkpoint (spec §12.5), conservative
/// by construction: infers only when exactly one history explains the
/// checkpoint, never a guess among several.
///
/// [span] is every `PitchThrown` event since the last certain state (AB
/// start, or the previous `CountCorrection` in this AB) up to and including
/// the pitch immediately before the checkpoint, in logical order — knowns
/// and unknowns interleaved exactly as they occurred.
///
/// [startBalls]/[startStrikes] are the certain count at the *start* of
/// [span], before any span event (known or unknown) has been applied — the
/// replay applies the span's known pitches itself, so passing a count that
/// already includes them would apply those knowns twice.
///
/// ## Why enumerate instead of a closed-form check
///
/// An earlier version of this checked `u == Δb + Δs` (unknown count equals
/// the total balls+strikes the checkpoint needs) and inferred whenever it
/// held. That's wrong: a *known* `foul` inside the span has a count effect
/// that depends on the strike count *at that exact moment*, which itself
/// depends on how the surrounding unknowns resolve. Two different
/// histories can both satisfy the aggregate arithmetic while disagreeing
/// on every individual pitch — matching totals never implied a unique
/// path. So instead of a side formula, each candidate history is replayed
/// through [applyPitchCountEffect] — the same function the real fold
/// uses — and "unique" means exactly one candidate's replay lands on the
/// checkpoint.
///
/// ## Why exactly two candidates per unknown, not three
///
/// Each unknown is tried as either `ball` or `foul` — never a third
/// `called_strike`-style candidate — because these two are genuine
/// count-effect equivalence classes, not arbitrary stand-ins:
/// - Below 2 strikes, `foul` and an "advancing strike" have an *identical*
///   count effect (+1 strike). A third candidate would just be a relabeled
///   duplicate of `foul` here.
/// - At 2 strikes, an advancing strike is impossible within a continuing
///   at-bat — it would be strike three, ending it. Any candidate reaching
///   that point can only be a no-op foul or a ball; `called_strike` is not
///   a real possibility for a pitch this function is even asked to
///   consider (the checkpoint's AB is still open).
///
/// Adding a third label would not add a real possibility — it would add a
/// *duplicate* of one that already exists, which breaks the uniqueness
/// check toward false ambiguity: two differently-labeled candidates with
/// the same count effect would both "match", making the algorithm see two
/// histories where there's really one, and refuse to infer something it
/// safely could.
///
/// Returns `null` when inference isn't possible or isn't safe to record —
/// including the rare case where the one matching candidate assigns a
/// pitch to a no-effect foul (at 2 strikes already): there's no count
/// effect to record for that pitch (see [InferredPitchEffect]), so rather
/// than record a partial answer, this refuses the whole span.
Map<String, InferredPitchEffect>? inferBackward({
  required List<GameEvent> span,
  required int startBalls,
  required int startStrikes,
  required int checkpointBalls,
  required int checkpointStrikes,
}) {
  final unknownPositions = <int>[
    for (var i = 0; i < span.length; i++)
      if (span[i].type == 'PitchThrown' &&
          PitchThrown.fromJson(span[i].payload).outcome == Outcome.UNKNOWN)
        i,
  ];
  if (unknownPositions.isEmpty) return null;

  final matches = <_Candidate>[];
  final candidateCount = 1 << unknownPositions.length; // 2^u, u is tiny

  for (var mask = 0; mask < candidateCount; mask++) {
    final candidate = _replay(
      span: span,
      unknownPositions: unknownPositions,
      mask: mask,
      balls: startBalls,
      strikes: startStrikes,
    );
    if (candidate == null) continue; // AB ended before the span was exhausted
    if (candidate.balls == checkpointBalls &&
        candidate.strikes == checkpointStrikes) {
      matches.add(candidate);
    }
  }

  if (matches.length != 1) return null; // zero or ambiguous — no inference
  final only = matches.single;
  if (only.hasUnrecordableNoOp) return null;
  return only.effects;
}

class _Candidate {
  _Candidate({
    required this.balls,
    required this.strikes,
    required this.effects,
    required this.hasUnrecordableNoOp,
  });

  final int balls;
  final int strikes;
  final Map<String, InferredPitchEffect> effects;
  final bool hasUnrecordableNoOp;
}

/// Replays [span] once for one candidate [mask] (bit i = 1 means "the i-th
/// unknown is a foul", bit i = 0 means "ball"). Returns null if the at-bat
/// would end before the span is exhausted — that candidate can't explain a
/// span whose later (known) events presume the same at-bat is still live.
_Candidate? _replay({
  required List<GameEvent> span,
  required List<int> unknownPositions,
  required int mask,
  required int balls,
  required int strikes,
}) {
  final effects = <String, InferredPitchEffect>{};
  var hasUnrecordableNoOp = false;
  var runningBalls = balls;
  var runningStrikes = strikes;

  for (var i = 0; i < span.length; i++) {
    final event = span[i];
    final unknownSlot = unknownPositions.indexOf(i);
    final isUnknown = unknownSlot != -1;

    final outcome = isUnknown
        ? ((mask >> unknownSlot) & 1 == 1 ? Outcome.FOUL : Outcome.BALL)
        : PitchThrown.fromJson(event.payload).outcome;

    final effect = applyPitchCountEffect(runningBalls, runningStrikes, outcome);
    runningBalls = effect.balls;
    runningStrikes = effect.strikes;

    if (isUnknown) {
      if (outcome == Outcome.BALL) {
        effects[event.id] = InferredPitchEffect.BALL;
      } else if (effect.strikesAdvanced) {
        effects[event.id] = InferredPitchEffect.STRIKE_EFFECT;
      } else {
        hasUnrecordableNoOp = true;
      }
    }

    final isLast = i == span.length - 1;
    if (effect.endsPlateAppearance && !isLast) {
      return null;
    }
  }

  return _Candidate(
    balls: runningBalls,
    strikes: runningStrikes,
    effects: effects,
    hasUnrecordableNoOp: hasUnrecordableNoOp,
  );
}

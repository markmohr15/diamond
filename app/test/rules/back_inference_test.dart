import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/rules/back_inference.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

void main() {
  final b = EventBuilder();

  GameEvent pitchOf(String id, Outcome outcome) {
    return b.pitch(id: id, batterId: 'bat', pitcherId: 'p', outcome: outcome);
  }

  GameEvent unknown(String id) => pitchOf(id, Outcome.UNKNOWN);
  GameEvent foul(String id) => pitchOf(id, Outcome.FOUL);

  test(
    'positive case: two unknowns, checkpoint needs only strikes -> infers',
    () {
      // 0-0, two unknown pitches, checkpoint 0-2. Only (foul, foul) reaches
      // 0-2 — (ball, *) always leaves balls=1, which can never match — so
      // this is unique despite having two unknowns.
      final u1 = unknown('u1');
      final u2 = unknown('u2');

      final result = inferBackward(
        span: [u1, u2],
        startBalls: 0,
        startStrikes: 0,
        checkpointBalls: 0,
        checkpointStrikes: 2,
      );

      expect(result, {
        'u1': InferredPitchEffect.STRIKE_EFFECT,
        'u2': InferredPitchEffect.STRIKE_EFFECT,
      });
    },
  );

  test(
    "Mark's counterexample: a known foul inside the span makes the "
    'aggregate arithmetic match two different histories',
    () {
      // certain 0-1, then: unknown / known-foul / unknown, checkpoint 1-2.
      // History A: unknown1=strike (0-1->0-2), knownFoul no-ops at 2
      // strikes (0-2->0-2), unknown2=ball (0-2->1-2).
      // History B: unknown1=ball (0-1->1-1), knownFoul counts since
      // strikes<2 (1-1->1-2), unknown2=no-op foul at 2 strikes (1-2->1-2).
      // Both reach 1-2. u=2, Δb+Δs=2 — the old formula would have wrongly
      // called this unique.
      final u1 = unknown('u1');
      final knownFoul = foul('kf');
      final u2 = unknown('u2');

      final result = inferBackward(
        span: [u1, knownFoul, u2],
        startBalls: 0,
        startStrikes: 1,
        checkpointBalls: 1,
        checkpointStrikes: 2,
      );

      expect(
        result,
        isNull,
        reason: 'two independently legal histories reach 1-2; must refuse',
      );
    },
  );

  test(
    'multiset-ambiguity counterexample: 0-0 -> 2-1 with three unknowns is '
    'a three-way positional tie even with zero known events involved',
    () {
      // Δb=2, Δs=1, u=3 — arithmetic matches (u == Δb+Δs), but WHICH of
      // the 3 unknowns was the strike is undetermined: strike-ball-ball,
      // ball-strike-ball, and ball-ball-strike are all equally legal
      // (strikes never reaches 2 in any of them), so 3 candidates match.
      final u1 = unknown('u1');
      final u2 = unknown('u2');
      final u3 = unknown('u3');

      final result = inferBackward(
        span: [u1, u2, u3],
        startBalls: 0,
        startStrikes: 0,
        checkpointBalls: 2,
        checkpointStrikes: 1,
      );

      expect(
        result,
        isNull,
        reason: 'three positions could be the strike; none is determined',
      );
    },
  );

  test('no unknowns in span -> nothing to infer', () {
    final known = pitchOf('k', Outcome.BALL);
    final result = inferBackward(
      span: [known],
      startBalls: 0,
      startStrikes: 0,
      checkpointBalls: 1,
      checkpointStrikes: 0,
    );
    expect(result, isNull);
  });

  test(
    'single unknown at 2 strikes, checkpoint unchanged: the only '
    'explanation is a no-op foul, which has no recordable effect, so '
    'this refuses even though it is technically unique',
    () {
      final u1 = unknown('u1');
      final result = inferBackward(
        span: [u1],
        startBalls: 0,
        startStrikes: 2,
        checkpointBalls: 0,
        checkpointStrikes: 2,
      );
      expect(result, isNull);
    },
  );

  test(
    'a candidate that would end the AB before the span is exhausted is '
    'discarded, not treated as a match',
    () {
      // 3 balls, then an unknown, then a KNOWN foul that presumes the AB
      // is still alive. If the unknown were a ball, the AB would have
      // ended at ball 4 and the known foul couldn't have happened — so
      // 'ball' must be discarded, leaving only 'foul' as a candidate:
      // 3-0 -> (u1=foul, +1 strike) -> 3-1 -> (knownFoul, +1 strike) -> 3-2.
      final u1 = unknown('u1');
      final knownFoul = foul('kf');

      final result = inferBackward(
        span: [u1, knownFoul],
        startBalls: 3,
        startStrikes: 0,
        checkpointBalls: 3,
        checkpointStrikes: 2,
      );

      expect(result, {'u1': InferredPitchEffect.STRIKE_EFFECT});
    },
  );
}

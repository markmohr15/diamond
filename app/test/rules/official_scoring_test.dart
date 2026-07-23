import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/rules/official_scoring.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

void main() {
  // The §14 play-2 sequence: boot, batter reaches on it, recovery throw
  // sails, batter takes third. bootEffort is the hit-vs-error judgment.
  List<GameEvent> playTwo(EventBuilder b, {required bool bootEffort}) {
    return [
      b.pitch(
        id: 'p',
        batterId: 'b1',
        pitcherId: 'pit',
        outcome: Outcome.IN_PLAY,
      ),
      b.ballInPlay(id: 'bip', pitchEventId: 'p'),
      b.fielderTouch(
        id: 'boot',
        anchorEventId: 'bip',
        position: 6,
        touchType: TouchType.BOOTED,
        ordinaryEffort: bootEffort,
      ),
      b.runnerAdvance(
        id: 'reach',
        runnerId: 'b1',
        from: 0,
        to: 1,
        reason: RunnerAdvanceReason.ERROR,
        enabledByTouchId: 'boot',
      ),
      b.fielderTouch(
        id: 'throw',
        anchorEventId: 'bip',
        position: 6,
        touchType: TouchType.WILD_THROW,
        ordinaryEffort: true,
      ),
      b.runnerAdvance(
        id: 'to-third',
        runnerId: 'b1',
        from: 1,
        to: 3,
        reason: RunnerAdvanceReason.WILD_THROW,
        enabledByTouchId: 'throw',
      ),
    ];
  }

  test("play-2 variant: flipping the boot's ordinaryEffort to false turns "
      'E6+E6 into a single plus one throwing error (§13.2 hit-vs-error)', () {
    final scoring = foldOfficialScoring(
      playTwo(EventBuilder(), bootEffort: false),
    );

    expect(scoring.errors, hasLength(1));
    expect(scoring.errors.single.kind, OfficialErrorKind.throwing);
    expect(scoring.errors.single.position, 6);

    final outcome = scoring.outcomeFor('b1')!;
    expect(outcome.scoring, 'single');
    expect(outcome.hit, isTrue);

    // Both misplays stay in the development ledger regardless (§13.1).
    expect(scoring.misplays, hasLength(2));
    // The uncharged reach is a hit, so no unearned condition attaches.
    expect(scoring.unearnedConditions, isEmpty);
  });

  test('play-2 as recorded: both errors charged, reach is on the boot', () {
    final scoring = foldOfficialScoring(
      playTwo(EventBuilder(), bootEffort: true),
    );

    expect(scoring.errors, hasLength(2));
    expect(scoring.errors[0].kind, OfficialErrorKind.fielding);
    expect(scoring.errors[0].basis, OfficialErrorBasis.reached);
    expect(scoring.errors[1].kind, OfficialErrorKind.throwing);
    expect(scoring.errors[1].basis, OfficialErrorBasis.advance);

    final outcome = scoring.outcomeFor('b1')!;
    expect(outcome.scoring, 'reached_on_error');
    expect(outcome.hit, isFalse);
    expect(scoring.unearnedConditions['b1'], 'unearned_if_scores');
  });

  test('unresolved ordinaryEffort (wild_throw with no flag) logs the misplay '
      'but never charges an error until the scorer resolves it (§13.2)', () {
    final b = EventBuilder();
    final scoring = foldOfficialScoring([
      b.pitch(
        id: 'p',
        batterId: 'b1',
        pitcherId: 'pit',
        outcome: Outcome.IN_PLAY,
      ),
      b.ballInPlay(id: 'bip', pitchEventId: 'p'),
      b.fielderTouch(
        id: 'throw',
        anchorEventId: 'bip',
        position: 5,
        touchType: TouchType.WILD_THROW,
      ),
      b.runnerAdvance(
        id: 'reach',
        runnerId: 'b1',
        from: 0,
        to: 2,
        reason: RunnerAdvanceReason.WILD_THROW,
        enabledByTouchId: 'throw',
      ),
    ]);

    expect(scoring.errors, isEmpty);
    expect(scoring.misplays, hasLength(1));
    expect(scoring.misplays.single.ordinaryEffort, isNull);
  });

  test('booted with no recorded judgment defaults ordinaryEffort true and '
      'charges once a consequence exists (§13.2 defaults)', () {
    final b = EventBuilder();
    final scoring = foldOfficialScoring([
      b.pitch(
        id: 'p',
        batterId: 'b1',
        pitcherId: 'pit',
        outcome: Outcome.IN_PLAY,
      ),
      b.ballInPlay(id: 'bip', pitchEventId: 'p'),
      b.fielderTouch(
        id: 'boot',
        anchorEventId: 'bip',
        position: 4,
        touchType: TouchType.BOOTED,
      ),
      b.runnerAdvance(
        id: 'reach',
        runnerId: 'b1',
        from: 0,
        to: 1,
        reason: RunnerAdvanceReason.ERROR,
        enabledByTouchId: 'boot',
      ),
    ]);

    expect(scoring.errors, hasLength(1));
    expect(scoring.errors.single.basis, OfficialErrorBasis.reached);
  });

  test('misplay with ordinaryEffort true but zero consequence: no error', () {
    final b = EventBuilder();
    final scoring = foldOfficialScoring([
      b.pitch(
        id: 'p',
        batterId: 'b1',
        pitcherId: 'pit',
        outcome: Outcome.IN_PLAY,
      ),
      b.ballInPlay(id: 'bip', pitchEventId: 'p'),
      b.fielderTouch(
        id: 'drop',
        anchorEventId: 'bip',
        position: 6,
        touchType: TouchType.DROPPED,
        ordinaryEffort: true,
      ),
      b.fielderTouch(
        id: 'recover',
        anchorEventId: 'bip',
        position: 6,
        touchType: TouchType.FIELDED,
      ),
      b.fielderTouch(
        id: 'receive',
        anchorEventId: 'bip',
        position: 3,
        touchType: TouchType.RECEIVED_THROW,
      ),
      b.runnerOut(id: 'out', runnerId: 'b1', atBase: 1, how: How.FORCE),
    ]);

    expect(scoring.errors, isEmpty);
    expect(scoring.misplays, hasLength(1));
  });

  test('putout and assist credit follows the touch chain', () {
    final b = EventBuilder();
    final events = [
      b.pitch(
        id: 'p',
        batterId: 'b1',
        pitcherId: 'pit',
        outcome: Outcome.IN_PLAY,
      ),
      b.ballInPlay(id: 'bip', pitchEventId: 'p'),
      b.fielderTouch(
        id: 'field',
        anchorEventId: 'bip',
        position: 6,
        touchType: TouchType.FIELDED,
      ),
      b.fielderTouch(
        id: 'receive',
        anchorEventId: 'bip',
        position: 3,
        touchType: TouchType.RECEIVED_THROW,
      ),
      b.make(
        id: 'out',
        type: 'RunnerOut',
        payload: RunnerOut(
          runnerId: 'b1',
          atBase: 1,
          how: How.FORCE,
          putoutTouchId: 'receive',
        ).toJson(),
      ),
    ];

    final scoring = foldOfficialScoring(events);
    expect(scoring.putoutsByPosition, {3: 1});
    expect(scoring.assistsByPosition, {6: 1});
  });
}

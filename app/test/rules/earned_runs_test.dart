import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/rules/earned_runs.dart';
import 'package:diamond/src/rules/game_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

void main() {
  GameEvent inPlay(EventBuilder b, String id, String batterId) {
    return b.pitch(
      id: id,
      batterId: batterId,
      pitcherId: 'pit',
      outcome: Outcome.IN_PLAY,
    );
  }

  test('a clean reach that scores on a clean hit is earned', () {
    final b = EventBuilder();
    final rulings = reconstructEarnedRuns([
      inPlay(b, 'p1', 'b1'),
      b.ballInPlay(id: 'bip1', pitchEventId: 'p1'),
      b.runnerAdvance(
        id: 'reach',
        runnerId: 'b1',
        from: 0,
        to: 1,
        reason: RunnerAdvanceReason.BATTED_BALL,
      ),
      inPlay(b, 'p2', 'b2'),
      b.ballInPlay(id: 'bip2', pitchEventId: 'p2'),
      b.runnerAdvance(
        id: 'scores',
        runnerId: 'b1',
        from: 1,
        to: 4,
        reason: RunnerAdvanceReason.BATTED_BALL,
      ),
    ]);

    expect(rulings, {'scores': RunRuling.earned});
  });

  test('play-2 continuation: the runner who reached on a charged error is '
      'removed from the reconstruction — the eventual run is unearned', () {
    final b = EventBuilder();
    final rulings = reconstructEarnedRuns([
      inPlay(b, 'p1', 'b1'),
      b.ballInPlay(id: 'bip1', pitchEventId: 'p1'),
      b.fielderTouch(
        id: 'boot',
        anchorEventId: 'bip1',
        position: 6,
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
      inPlay(b, 'p2', 'b2'),
      b.ballInPlay(id: 'bip2', pitchEventId: 'p2'),
      b.runnerAdvance(
        id: 'scores',
        runnerId: 'b1',
        from: 1,
        to: 4,
        reason: RunnerAdvanceReason.BATTED_BALL,
      ),
    ]);

    expect(rulings, {'scores': RunRuling.unearned});
  });

  test('play-4 continuation: homer after the dropped foul that should have '
      'ended the at-bat is unearned', () {
    final b = EventBuilder();
    final rulings = reconstructEarnedRuns([
      b.pitch(
        id: 'p1',
        batterId: 'b1',
        pitcherId: 'pit',
        outcome: Outcome.FOUL,
      ),
      b.ballInPlay(
        id: 'bip1',
        pitchEventId: 'p1',
        fair: false,
        trajectory: Trajectory.POPUP,
      ),
      b.fielderTouch(
        id: 'drop',
        anchorEventId: 'bip1',
        position: 5,
        touchType: TouchType.DROPPED,
      ),
      inPlay(b, 'p2', 'b1'),
      b.ballInPlay(id: 'bip2', pitchEventId: 'p2'),
      b.runnerAdvance(
        id: 'homers',
        runnerId: 'b1',
        from: 0,
        to: 4,
        reason: RunnerAdvanceReason.BATTED_BALL,
      ),
    ]);

    expect(rulings, {'homers': RunRuling.unearned});
  });

  test('an error-enabled advance breaks the chain: scoring from the stolen '
      'ground is unearned even though the reach was clean', () {
    final b = EventBuilder();
    final rulings = reconstructEarnedRuns([
      inPlay(b, 'p1', 'b1'),
      b.ballInPlay(id: 'bip1', pitchEventId: 'p1'),
      b.runnerAdvance(
        id: 'reach',
        runnerId: 'b1',
        from: 0,
        to: 1,
        reason: RunnerAdvanceReason.BATTED_BALL,
      ),
      b.fielderTouch(
        id: 'throw',
        anchorEventId: 'bip1',
        position: 9,
        touchType: TouchType.WILD_THROW,
      ),
      b.runnerAdvance(
        id: 'to-third',
        runnerId: 'b1',
        from: 1,
        to: 3,
        reason: RunnerAdvanceReason.WILD_THROW,
        enabledByTouchId: 'throw',
      ),
      inPlay(b, 'p2', 'b2'),
      b.ballInPlay(id: 'bip2', pitchEventId: 'p2'),
      b.runnerAdvance(
        id: 'scores',
        runnerId: 'b1',
        from: 3,
        to: 4,
        reason: RunnerAdvanceReason.BATTED_BALL,
      ),
    ]);

    expect(rulings, {'scores': RunRuling.unearned});
  });

  test('runs after the reconstructed third out are unearned, including a '
      'later clean homer', () {
    final b = EventBuilder();
    final rulings = reconstructEarnedRuns([
      inPlay(b, 'p1', 'b1'),
      b.ballInPlay(id: 'bip1', pitchEventId: 'p1'),
      b.fielderTouch(
        id: 'boot',
        anchorEventId: 'bip1',
        position: 6,
        touchType: TouchType.BOOTED,
      ),
      // The reach that should have been out #3.
      b.runnerAdvance(
        id: 'reach',
        runnerId: 'b1',
        from: 0,
        to: 1,
        reason: RunnerAdvanceReason.ERROR,
        enabledByTouchId: 'boot',
      ),
      inPlay(b, 'p2', 'b2'),
      b.ballInPlay(id: 'bip2', pitchEventId: 'p2'),
      b.runnerAdvance(
        id: 'b1-scores',
        runnerId: 'b1',
        from: 1,
        to: 4,
        reason: RunnerAdvanceReason.BATTED_BALL,
      ),
      b.runnerAdvance(
        id: 'b2-homers',
        runnerId: 'b2',
        from: 0,
        to: 4,
        reason: RunnerAdvanceReason.BATTED_BALL,
      ),
    ], startingFrom: const GameState(outs: 2));

    expect(rulings, {
      'b1-scores': RunRuling.unearned,
      'b2-homers': RunRuling.unearned,
    });
  });

  test("a run scoring on a wild pitch stays earned (pitcher's own doing)", () {
    final b = EventBuilder();
    final rulings = reconstructEarnedRuns([
      inPlay(b, 'p1', 'b1'),
      b.ballInPlay(id: 'bip1', pitchEventId: 'p1'),
      b.runnerAdvance(
        id: 'reach',
        runnerId: 'b1',
        from: 0,
        to: 3,
        reason: RunnerAdvanceReason.BATTED_BALL,
      ),
      b.pitch(
        id: 'p2',
        batterId: 'b2',
        pitcherId: 'pit',
        outcome: Outcome.BALL,
      ),
      b.runnerAdvance(
        id: 'scores',
        runnerId: 'b1',
        from: 3,
        to: 4,
        reason: RunnerAdvanceReason.WILD_PITCH,
      ),
    ]);

    expect(rulings, {'scores': RunRuling.earned});
  });

  test('a run scoring on a passed ball is unearned (§13.3)', () {
    final b = EventBuilder();
    final rulings = reconstructEarnedRuns([
      inPlay(b, 'p1', 'b1'),
      b.ballInPlay(id: 'bip1', pitchEventId: 'p1'),
      b.runnerAdvance(
        id: 'reach',
        runnerId: 'b1',
        from: 0,
        to: 3,
        reason: RunnerAdvanceReason.BATTED_BALL,
      ),
      b.pitch(
        id: 'p2',
        batterId: 'b2',
        pitcherId: 'pit',
        outcome: Outcome.BALL,
      ),
      b.runnerAdvance(
        id: 'scores',
        runnerId: 'b1',
        from: 3,
        to: 4,
        reason: RunnerAdvanceReason.PASSED_BALL,
      ),
    ]);

    expect(rulings, {'scores': RunRuling.unearned});
  });
}

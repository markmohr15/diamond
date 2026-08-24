import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/rules/game_state.dart';
import 'package:diamond/src/rules/official_scoring.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

void main() {
  /// The §13.6 sac-fly shape, with knobs for each condition it turns on.
  List<GameEvent> sacFly(
    EventBuilder b, {
    Trajectory trajectory = Trajectory.FLY,
    bool caught = true,
    bool batterOut = true,
    int scoresFrom = 3,
    bool withError = false,
    bool? judged,
  }) {
    return [
      b.pitch(
        id: 'p',
        batterId: 'b1',
        pitcherId: 'pit',
        outcome: Outcome.IN_PLAY,
      ),
      b.make(
        id: 'bip',
        type: 'BallInPlay',
        payload: BallInPlay(
          pitchEventId: 'p',
          fair: true,
          trajectory: trajectory,
          landing: FieldCoord(x: 0, y: 240),
          landingIsCaught: caught,
          sacrifice: judged,
        ).toJson(),
      ),
      b.fielderTouch(
        id: 't',
        anchorEventId: 'bip',
        position: 8,
        touchType: caught ? TouchType.CAUGHT : TouchType.DROPPED,
        ordinaryEffort: withError ? true : null,
      ),
      if (batterOut)
        b.runnerOut(id: 'o', runnerId: 'b1', atBase: 1, how: How.FLY_OUT),
      b.runnerAdvance(
        id: 'score',
        runnerId: 'r3',
        from: scoresFrom,
        to: 4,
        reason: RunnerAdvanceReason.BATTED_BALL,
        enabledByTouchId: withError ? 't' : null,
      ),
    ];
  }

  test('a sac fly derives: caught, batter out, runner in from third, no '
      'error — a plate appearance but not an at-bat (§13.6)', () {
    final o = foldOfficialScoring(sacFly(EventBuilder())).outcomeFor('b1')!;
    expect(o.scoring, 'sacrifice_fly');
    expect(o.hit, isFalse);
    expect(o.atBat, isFalse);
    expect(o.rbi, 1, reason: 'the run she gave herself up for still counts');
  });

  test('each condition is load-bearing: drop it and the sacrifice goes', () {
    String scoringOf(List<GameEvent> events) =>
        foldOfficialScoring(events).outcomeFor('b1')!.scoring;

    // Not caught: she did not give herself up, somebody muffed it.
    expect(
      scoringOf(sacFly(EventBuilder(), caught: false)),
      isNot('sacrifice_fly'),
    );
    // Nobody scored from third.
    expect(
      scoringOf(sacFly(EventBuilder(), scoresFrom: 2)),
      isNot('sacrifice_fly'),
    );
    // An error on the play: the run needed a misplay, not her out.
    expect(
      scoringOf(sacFly(EventBuilder(), caught: false, withError: true)),
      isNot('sacrifice_fly'),
    );
    // A grounder is not caught in the air.
    expect(
      scoringOf(sacFly(EventBuilder(), trajectory: Trajectory.GROUND)),
      isNot('sacrifice_fly'),
    );
  });

  test('anything caught in the air qualifies — pop-up and line drive too', () {
    for (final trajectory in [
      Trajectory.FLY,
      Trajectory.POPUP,
      Trajectory.LINE,
    ]) {
      final o = foldOfficialScoring(
        sacFly(EventBuilder(), trajectory: trajectory),
      ).outcomeFor('b1')!;
      expect(o.scoring, 'sacrifice_fly', reason: trajectory.toString());
      expect(o.atBat, isFalse, reason: trajectory.toString());
    }
  });

  test(
    'two outs already: the catch is the third, so there is no sacrifice',
    () {
      final b = EventBuilder();
      final o = foldOfficialScoring(
        sacFly(b),
        startingFrom: const GameState(outs: 2),
      ).outcomeFor('b1')!;
      expect(o.scoring, isNot('sacrifice_fly'));
    },
  );

  test('a sac bunt cannot derive — it is the scorer who knows (§13.6)', () {
    final unjudged = foldOfficialScoring(
      sacFly(EventBuilder(), trajectory: Trajectory.BUNT, caught: false),
    ).outcomeFor('b1')!;
    expect(unjudged.scoring, isNot('sacrifice_bunt'));
    expect(unjudged.atBat, isTrue);

    final judged = foldOfficialScoring(
      sacFly(
        EventBuilder(),
        trajectory: Trajectory.BUNT,
        caught: false,
        judged: true,
      ),
    ).outcomeFor('b1')!;
    expect(judged.scoring, 'sacrifice_bunt');
    expect(judged.atBat, isFalse);
  });

  test('an explicit judgment overrides the derivation both ways', () {
    final denied = foldOfficialScoring(
      sacFly(EventBuilder(), judged: false),
    ).outcomeFor('b1')!;
    expect(denied.scoring, 'out');
    expect(denied.atBat, isTrue);
  });

  test('obstruction on the batter-runner (§13.2 v0.43): not a hit, not an '
      'at-bat, and a fielding error to whoever obstructed her', () {
    final b = EventBuilder();
    final scoring = foldOfficialScoring([
      b.pitch(
        id: 'p',
        batterId: 'b1',
        pitcherId: 'pit',
        outcome: Outcome.IN_PLAY,
      ),
      b.ballInPlay(id: 'bip', pitchEventId: 'p'),
      b.make(
        id: 'call',
        type: 'RuleCall',
        payload: RuleCall(
          callType: CallType.OBSTRUCTION,
          againstPosition: 3,
        ).toJson(),
      ),
      b.make(
        id: 'award',
        type: 'RunnerAdvance',
        payload: RunnerAdvance(
          runnerId: 'b1',
          from: 0,
          to: 1,
          reason: RunnerAdvanceReason.OBSTRUCTION,
          enabledByCallId: 'call',
        ).toJson(),
      ),
    ]);

    final outcome = scoring.outcomeFor('b1')!;
    expect(outcome.scoring, 'obstruction');
    expect(outcome.hit, isFalse);
    expect(outcome.atBat, isFalse);
    expect(scoring.errors, hasLength(1));
    final charged = scoring.errors.single;
    expect(charged.position, 3);
    expect(charged.kind, OfficialErrorKind.fielding);
    expect(scoring.misplays, isEmpty, reason: 'no misplay touch behind it');
  });

  test('obstruction on a runner already aboard touches none of that', () {
    final b = EventBuilder();
    final scoring = foldOfficialScoring([
      b.pitch(
        id: 'p',
        batterId: 'b1',
        pitcherId: 'pit',
        outcome: Outcome.IN_PLAY,
      ),
      b.ballInPlay(id: 'bip', pitchEventId: 'p'),
      b.make(
        id: 'call',
        type: 'RuleCall',
        payload: RuleCall(
          callType: CallType.OBSTRUCTION,
          againstPosition: 5,
        ).toJson(),
      ),
      b.make(
        id: 'adv',
        type: 'RunnerAdvance',
        payload: RunnerAdvance(
          runnerId: 'r2',
          from: 2,
          to: 3,
          reason: RunnerAdvanceReason.OBSTRUCTION,
          enabledByCallId: 'call',
        ).toJson(),
      ),
      b.runnerAdvance(
        id: 'reach',
        runnerId: 'b1',
        from: 0,
        to: 1,
        reason: RunnerAdvanceReason.BATTED_BALL,
      ),
    ]);

    expect(scoring.errors, isEmpty, reason: 'she was going there anyway');
    final outcome = scoring.outcomeFor('b1')!;
    expect(outcome.scoring, 'single');
    expect(outcome.atBat, isTrue);
  });

  test('a reach claiming an error with nothing to link is still not a hit '
      '(§13.2)', () {
    final b = EventBuilder();
    final scoring = foldOfficialScoring([
      b.pitch(
        id: 'p',
        batterId: 'b1',
        pitcherId: 'pit',
        outcome: Outcome.IN_PLAY,
      ),
      b.ballInPlay(id: 'bip', pitchEventId: 'p'),
      b.runnerAdvance(
        id: 'reach',
        runnerId: 'b1',
        from: 0,
        to: 1,
        reason: RunnerAdvanceReason.ERROR,
      ),
    ]);

    final outcome = scoring.outcomeFor('b1')!;
    expect(outcome.scoring, 'reached_on_error');
    expect(outcome.hit, isFalse);
    expect(outcome.atBat, isTrue, reason: 'reaching on an error is an at-bat');
  });

  test('at-bats are plate appearances minus the awards (§13 v0.43)', () {
    final cases = <RunnerAdvanceReason, bool>{
      RunnerAdvanceReason.WALK: false,
      RunnerAdvanceReason.HBP: false,
      RunnerAdvanceReason.CATCHER_INTERFERENCE: false,
      RunnerAdvanceReason.OBSTRUCTION: false,
      RunnerAdvanceReason.DROPPED_THIRD_STRIKE: true,
      RunnerAdvanceReason.FIELDERS_CHOICE: true,
      RunnerAdvanceReason.BATTED_BALL: true,
    };
    for (final entry in cases.entries) {
      final reason = entry.key;
      final expected = entry.value;
      final b = EventBuilder();
      final scoring = foldOfficialScoring([
        b.pitch(
          id: 'p',
          batterId: 'b1',
          pitcherId: 'pit',
          outcome: Outcome.IN_PLAY,
        ),
        b.runnerAdvance(
          id: 'reach',
          runnerId: 'b1',
          from: 0,
          to: 1,
          reason: reason,
        ),
      ]);
      expect(
        scoring.outcomeFor('b1')!.atBat,
        expected,
        reason: reason.toString(),
      );
    }
  });

  test('a recorded missed tag is a charged fielding error (§13.2 v0.43): '
      'if it is worth putting in the play-by-play, it is an error', () {
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
        id: 'field',
        anchorEventId: 'bip',
        position: 5,
        touchType: TouchType.FIELDED,
      ),
      b.fielderTouch(
        id: 'muff',
        anchorEventId: 'bip',
        position: 5,
        touchType: TouchType.TAG_MISSED,
      ),
      // The runner she failed to tag takes the extra base on it.
      b.runnerAdvance(
        id: 'extra',
        runnerId: 'r1',
        from: 1,
        to: 3,
        reason: RunnerAdvanceReason.ERROR,
        enabledByTouchId: 'muff',
      ),
    ]);

    expect(scoring.errors, hasLength(1));
    expect(scoring.errors.single.position, 5);
    expect(scoring.errors.single.kind, OfficialErrorKind.fielding);
    // No explicit judgment was entered: the default says she should have
    // made it, which is the whole reason it got recorded.
    expect(scoring.misplays.single.ordinaryEffort, isTrue);
  });

  test('a missed tag judged no-play stays in the development ledger and '
      'charges nothing (§13.1)', () {
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
        id: 'muff',
        anchorEventId: 'bip',
        position: 5,
        touchType: TouchType.TAG_MISSED,
        ordinaryEffort: false,
      ),
      b.runnerAdvance(
        id: 'extra',
        runnerId: 'r1',
        from: 1,
        to: 3,
        reason: RunnerAdvanceReason.ERROR,
        enabledByTouchId: 'muff',
      ),
    ]);

    expect(scoring.errors, isEmpty);
    expect(scoring.misplays, hasLength(1));
  });

  test('hit rank counts only the hit itself (v0.43): taking second on the '
      'throw is a single plus an advance, never a double', () {
    final b = EventBuilder();
    final scoring = foldOfficialScoring([
      b.pitch(
        id: 'p',
        batterId: 'b1',
        pitcherId: 'pit',
        outcome: Outcome.IN_PLAY,
      ),
      b.ballInPlay(id: 'bip', pitchEventId: 'p'),
      b.runnerAdvance(
        id: 'reach',
        runnerId: 'b1',
        from: 0,
        to: 1,
        reason: RunnerAdvanceReason.BATTED_BALL,
      ),
      b.fielderTouch(
        id: 'lf',
        anchorEventId: 'bip',
        position: 7,
        touchType: TouchType.FIELDED,
      ),
      b.fielderTouch(
        id: 'cutoff',
        anchorEventId: 'bip',
        position: 6,
        touchType: TouchType.RECEIVED_THROW,
      ),
      // Took second on the throw home: linked to the clean receiving touch.
      b.runnerAdvance(
        id: 'on-throw',
        runnerId: 'b1',
        from: 1,
        to: 2,
        reason: RunnerAdvanceReason.BATTED_BALL,
        enabledByTouchId: 'cutoff',
      ),
    ]);

    final outcome = scoring.outcomeFor('b1')!;
    expect(outcome.scoring, 'single');
    expect(outcome.hit, isTrue);
    expect(scoring.errors, isEmpty);
  });

  test("catcher's interference (§4.1 v0.43): E2 by rule, no misplay touch, "
      'batter result derives from the reason', () {
    final b = EventBuilder();
    final scoring = foldOfficialScoring([
      b.pitch(
        id: 'p',
        batterId: 'b1',
        pitcherId: 'pit',
        outcome: Outcome.CATCHER_INTERFERENCE,
      ),
      b.runnerAdvance(
        id: 'award',
        runnerId: 'b1',
        from: 0,
        to: 1,
        reason: RunnerAdvanceReason.CATCHER_INTERFERENCE,
      ),
    ]);

    expect(scoring.errors, hasLength(1));
    expect(scoring.errors.single.position, 2);
    expect(scoring.errors.single.kind, OfficialErrorKind.interference);
    expect(scoring.misplays, isEmpty);
    final outcome = scoring.outcomeFor('b1')!;
    expect(outcome.scoring, 'catcher_interference');
    expect(outcome.hit, isFalse);
  });

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

  test('unresolved ordinaryEffort (bobbled with no flag) logs the misplay '
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
        id: 'bobble',
        anchorEventId: 'bip',
        position: 5,
        touchType: TouchType.BOBBLED,
      ),
      b.runnerAdvance(
        id: 'reach',
        runnerId: 'b1',
        from: 0,
        to: 1,
        reason: RunnerAdvanceReason.ERROR,
        enabledByTouchId: 'bobble',
      ),
    ]);

    expect(scoring.errors, isEmpty);
    expect(scoring.misplays, hasLength(1));
    expect(scoring.misplays.single.ordinaryEffort, isNull);
  });

  test('the v0.43 defaults: recording a missed tag is itself the claim she '
      'should have made it; a wild throw is not (§13.2)', () {
    expect(defaultOrdinaryEffort(TouchType.TAG_MISSED), isTrue);
    expect(defaultOrdinaryEffort(TouchType.BOOTED), isTrue);
    expect(defaultOrdinaryEffort(TouchType.MISSED_CATCH), isTrue);
    expect(defaultOrdinaryEffort(TouchType.DROPPED), isTrue);
    // Judgment calls, unresolved until someone makes them: a throw can
    // sail and cost nothing, and a bobble is a bobble.
    expect(defaultOrdinaryEffort(TouchType.WILD_THROW), isNull);
    expect(defaultOrdinaryEffort(TouchType.BOBBLED), isNull);
    // Never a candidate at all (§13.2): no judgment to default.
    expect(defaultOrdinaryEffort(TouchType.DEFLECTED), isNull);
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

  group('wild pitches and passed balls (§13.2, rule 9.13)', () {
    List<GameEvent> getaway({
      TouchType? catcherTouch,
      bool? ordinaryEffort,
      RunnerAdvanceReason reason = RunnerAdvanceReason.PASSED_BALL,
      bool runnerMoves = true,
    }) {
      final b = EventBuilder();
      return [
        b.pitch(
          id: 'p',
          batterId: 'b1',
          pitcherId: 'pit',
          outcome: Outcome.BALL,
        ),
        if (catcherTouch != null)
          b.fielderTouch(
            id: 'drop',
            anchorEventId: 'p',
            position: 2,
            touchType: catcherTouch,
            ordinaryEffort: ordinaryEffort,
          ),
        if (runnerMoves)
          b.runnerAdvance(
            id: 'adv',
            runnerId: 'r2',
            from: 2,
            to: 3,
            reason: reason,
            enabledByTouchId: catcherTouch == null ? null : 'drop',
          ),
      ];
    }

    test('an ordinary-effort failure to receive is a passed ball', () {
      final scoring = foldOfficialScoring(
        getaway(catcherTouch: TouchType.MISSED_CATCH),
      );
      expect(scoring.passedBalls, 1);
      expect(scoring.wildPitchesByPitcher, isEmpty);
      expect(scoring.errors, isEmpty, reason: 'a PB is never an error');
      expect(scoring.pitchGetaways.single.position, 2);
    });

    test("no touch against the pitch is the pitcher's wild pitch", () {
      final scoring = foldOfficialScoring(
        getaway(reason: RunnerAdvanceReason.WILD_PITCH),
      );
      expect(scoring.wildPitchesByPitcher, {'pit': 1});
      expect(scoring.passedBalls, 0);
    });

    test('a misplay she could not have held is a wild pitch, not a PB', () {
      final scoring = foldOfficialScoring(
        getaway(catcherTouch: TouchType.MISSED_CATCH, ordinaryEffort: false),
      );
      expect(scoring.wildPitchesByPitcher, {'pit': 1});
      expect(scoring.passedBalls, 0);
    });

    test('physics decides, not the advance label', () {
      // Labeled a passed ball with no catcher touch behind it: the ball
      // getting away was the pitcher's doing whatever the chip said.
      final scoring = foldOfficialScoring(getaway());
      expect(scoring.passedBalls, 0);
      expect(scoring.wildPitchesByPitcher, {'pit': 1});
    });

    test('nobody moved: a blocked pitch is charged to no one', () {
      final scoring = foldOfficialScoring(
        getaway(catcherTouch: TouchType.MISSED_CATCH, runnerMoves: false),
      );
      expect(scoring.pitchGetaways, isEmpty);
      expect(scoring.passedBalls, 0);
      expect(scoring.wildPitchesByPitcher, isEmpty);
    });

    test('a reach claimed by the throw is no getaway: she blocked it, then '
        'threw it away (§13.2 v0.44)', () {
      final b = EventBuilder();
      final scoring = foldOfficialScoring([
        b.pitch(
          id: 'p',
          batterId: 'b1',
          pitcherId: 'pit',
          outcome: Outcome.SWINGING_STRIKE_BLOCKED,
        ),
        // Blocked and kept in front of her — the ball never got away. The
        // throw to first is what put her on.
        b.fielderTouch(
          id: 'throw',
          anchorEventId: 'p',
          position: 2,
          touchType: TouchType.WILD_THROW,
          ordinaryEffort: true,
        ),
        b.runnerAdvance(
          id: 'reach',
          runnerId: 'b1',
          from: 0,
          to: 1,
          reason: RunnerAdvanceReason.DROPPED_THIRD_STRIKE,
          enabledByTouchId: 'throw',
        ),
      ]);
      expect(scoring.pitchGetaways, isEmpty, reason: 'no WP and no PB');
      expect(scoring.passedBalls, 0);
      expect(scoring.wildPitchesByPitcher, isEmpty);
      // The error still stands — and it is the only charge on the play.
      expect(scoring.errors.single.position, 2);
      expect(scoring.errors.single.kind, OfficialErrorKind.throwing);
    });

    test('one pitch, two runners: one passed ball, two advances', () {
      final b = EventBuilder();
      final scoring = foldOfficialScoring([
        b.pitch(
          id: 'p',
          batterId: 'b1',
          pitcherId: 'pit',
          outcome: Outcome.BALL,
        ),
        b.fielderTouch(
          id: 'drop',
          anchorEventId: 'p',
          position: 2,
          touchType: TouchType.MISSED_CATCH,
        ),
        b.runnerAdvance(
          id: 'a1',
          runnerId: 'r3',
          from: 3,
          to: 4,
          reason: RunnerAdvanceReason.PASSED_BALL,
          enabledByTouchId: 'drop',
        ),
        b.runnerAdvance(
          id: 'a2',
          runnerId: 'r1',
          from: 1,
          to: 2,
          reason: RunnerAdvanceReason.PASSED_BALL,
          enabledByTouchId: 'drop',
        ),
      ]);
      expect(scoring.passedBalls, 1);
      expect(scoring.pitchGetaways.single.advanceEventIds, ['a1', 'a2']);
    });
  });
}

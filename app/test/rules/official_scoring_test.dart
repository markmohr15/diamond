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

  test(
    'two plate appearances are independent — the second is not the first',
    () {
      // The bug this closes: `reach` and `wasOut` scanned the whole game's
      // advances and outs, so a batter's result was pinned to her *first* plate
      // appearance forever. She flies out, the order comes back around, she
      // singles — and the single used to report as an out.
      //
      // This is the criterion that generalizes. It fails for any read that
      // reaches outside its plate appearance, including ones nobody has thought
      // of, which is what all four of Part 1's bugs turned out to be.
      final b = EventBuilder();
      final events = <GameEvent>[
        // PA 1 — b1 flies out.
        b.pitch(
          id: 'p1',
          batterId: 'b1',
          pitcherId: 'pit',
          outcome: Outcome.IN_PLAY,
        ),
        b.make(
          id: 'bip1',
          type: 'BallInPlay',
          payload: BallInPlay(
            pitchEventId: 'p1',
            fair: true,
            trajectory: Trajectory.FLY,
            landing: FieldCoord(x: 0, y: 240),
            landingIsCaught: true,
          ).toJson(),
        ),
        b.fielderTouch(
          id: 't1',
          anchorEventId: 'bip1',
          position: 8,
          touchType: TouchType.CAUGHT,
        ),
        b.runnerOut(id: 'o1', runnerId: 'b1', atBase: 1, how: How.FLY_OUT),

        // PA 2 — somebody else, so the partition has a boundary to find.
        b.pitch(
          id: 'p2',
          batterId: 'b2',
          pitcherId: 'pit',
          outcome: Outcome.IN_PLAY,
        ),
        b.make(
          id: 'bip2',
          type: 'BallInPlay',
          payload: BallInPlay(
            pitchEventId: 'p2',
            fair: true,
            trajectory: Trajectory.GROUND,
            landing: FieldCoord(x: -40, y: 90),
            landingIsCaught: false,
          ).toJson(),
        ),
        b.fielderTouch(
          id: 't2',
          anchorEventId: 'bip2',
          position: 6,
          touchType: TouchType.FIELDED,
        ),
        b.runnerOut(id: 'o2', runnerId: 'b2', atBase: 1, how: How.FORCE),

        // PA 3 — b1 again, and this time she singles.
        b.pitch(
          id: 'p3',
          batterId: 'b1',
          pitcherId: 'pit',
          outcome: Outcome.IN_PLAY,
        ),
        b.make(
          id: 'bip3',
          type: 'BallInPlay',
          payload: BallInPlay(
            pitchEventId: 'p3',
            fair: true,
            trajectory: Trajectory.LINE,
            landing: FieldCoord(x: 60, y: 200),
            landingIsCaught: false,
          ).toJson(),
        ),
        b.fielderTouch(
          id: 't3',
          anchorEventId: 'bip3',
          position: 9,
          touchType: TouchType.FIELDED,
        ),
        b.runnerAdvance(
          id: 'a3',
          runnerId: 'b1',
          from: 0,
          to: 1,
          reason: RunnerAdvanceReason.BATTED_BALL,
        ),
      ];

      final forB1 = foldOfficialScoring(
        events,
      ).batterOutcomes.where((o) => o.batterId == 'b1').toList();

      expect(forB1, hasLength(2), reason: 'two plate appearances, two results');
      expect(forB1.first.scoring, 'out');
      expect(forB1.first.atBat, isTrue);
      expect(forB1.last.scoring, 'single', reason: 'not pinned to the flyout');
      expect(forB1.last.hit, isTrue);
    },
  );

  test('each condition is load-bearing: drop it and the sacrifice goes', () {
    String? scoringOf(List<GameEvent> events) =>
        foldOfficialScoring(events).outcomeFor('b1')!.scoring;

    // Not caught: she did not give herself up, somebody muffed it.
    expect(
      scoringOf(sacFly(EventBuilder(), caught: false)),
      isNot('sacrifice_fly'),
    );
    // Not judged and not caught: no clause-(1) derivation, and clause (2)
    // needs the scorer to say so.
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

  test('a runner scoring from second credits it, not just from third', () {
    // The rule asks only that a runner scores after the catch. A runner
    // tagging from second on a deep fly is legal and happens; the derivation
    // used to require `from == 3` and the variable was named for the
    // assumption, which is how it survived.
    final o = foldOfficialScoring(
      sacFly(EventBuilder(), scoresFrom: 2),
    ).outcomeFor('b1')!;
    expect(o.scoring, 'sacrifice_fly');
    expect(o.sacrifice, isTrue);
    expect(o.atBat, isFalse);
  });

  test('clause (2): a dropped fly the scorer judges a sacrifice', () {
    // The rule credits a sac fly on either of two clauses — caught and a
    // runner scores, *or* dropped and a runner scores who could have scored
    // had it been caught. Clause (2) is judgment, so it arrives through the
    // scorer's flag rather than deriving.
    //
    // She reaches on the error, so she is not retired — and it is still a
    // sacrifice, still a plate appearance, and still not an at-bat. That
    // combination is what the old single `scoring` string could not hold.
    final o = foldOfficialScoring(
      sacFly(EventBuilder(), caught: false, withError: true, judged: true),
    ).outcomeFor('b1')!;

    expect(o.sacrifice, isTrue);
    expect(o.atBat, isFalse, reason: 'a sacrifice is never an at-bat');
    expect(o.complete, isTrue);
    expect(o.hit, isFalse);
  });

  test('an error on the play does not cancel a caught sacrifice fly', () {
    // `anyChargedError` used to guard the derivation and was wrong even for
    // clause (1): the runner tags and scores, the throw home gets away, and
    // another runner takes a base. Still a sacrifice fly, and still an error.
    final b = EventBuilder();
    final scoring = foldOfficialScoring([
      ...sacFly(b),
      b.fielderTouch(
        id: 'wild',
        anchorEventId: 'bip',
        position: 8,
        touchType: TouchType.WILD_THROW,
        ordinaryEffort: true,
      ),
      b.runnerAdvance(
        id: 'extra',
        runnerId: 'r1',
        from: 1,
        to: 2,
        reason: RunnerAdvanceReason.ERROR,
        enabledByTouchId: 'wild',
      ),
    ]);

    expect(scoring.errors, isNotEmpty, reason: 'the throw is still an error');
    final o = scoring.outcomeFor('b1')!;
    expect(o.scoring, 'sacrifice_fly');
    expect(o.sacrifice, isTrue);
    expect(o.atBat, isFalse);
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

    test('the passed-ball exemption is the catcher on a pitch, and nothing '
        'else', () {
      // §13.2: a passed ball is not an error — they are separate statistics.
      // But the exemption kept widening past its own rule, because every
      // condition short of the full one lets something through.
      //
      // Anchored to a pitch was the first try, and §15.6 anchors *every*
      // between-pitch entry to the pitch, so a rundown's dropped exchange went
      // uncharged. Adding "first touch on that anchor" fixed the rundown and
      // not the pickoff: a throw over to first *is* the first touch on its
      // anchor.
      List<GameEvent> missedCatchBy(int position) {
        final b = EventBuilder();
        return [
          b.pitch(
            id: 'p',
            batterId: 'b1',
            pitcherId: 'pit',
            outcome: Outcome.BALL,
          ),
          b.fielderTouch(
            id: 'miss',
            anchorEventId: 'p',
            position: position,
            touchType: TouchType.MISSED_CATCH,
            ordinaryEffort: true,
          ),
          b.runnerAdvance(
            id: 'adv',
            runnerId: 'r1',
            from: 1,
            to: 2,
            reason: RunnerAdvanceReason.ERROR,
            enabledByTouchId: 'miss',
          ),
        ];
      }

      // The first baseman missing a pickoff throw has muffed a *throw*.
      expect(
        foldOfficialScoring(missedCatchBy(3)).errors,
        isNotEmpty,
        reason: 'E3 — nobody pitched to the first baseman',
      );

      // The catcher missing the pitch is the one exemption.
      expect(foldOfficialScoring(missedCatchBy(2)).errors, isEmpty);
    });

    test('a D3K says which getaway it was, or says none (§13.2 v0.50)', () {
      // `reason` and `cause` answer different questions, and on a dropped
      // third strike they come apart: she is entitled to run because strike
      // three was not caught, while what happened to the ball is a separate
      // fact. They shared one field until v0.50, so the engine inferred the
      // second from whether a catcher touch existed.
      List<GameEvent> d3k({Cause? cause, bool blockedThenThrewItAway = false}) {
        final b = EventBuilder();
        return [
          b.pitch(
            id: 'p',
            batterId: 'b1',
            pitcherId: 'pit',
            outcome: Outcome.SWINGING_STRIKE,
          ),
          if (blockedThenThrewItAway)
            b.fielderTouch(
              id: 'wild',
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
            cause: cause,
            enabledByTouchId: blockedThenThrewItAway ? 'wild' : null,
          ),
        ];
      }

      // She says it got past the catcher.
      expect(foldOfficialScoring(d3k(cause: Cause.PASSED_BALL)).passedBalls, 1);

      // She says the pitcher threw it away.
      expect(
        foldOfficialScoring(d3k(cause: Cause.WILD_PITCH)).wildPitchesByPitcher,
        {'pit': 1},
      );

      // Blocked, kept in front of her, then thrown away: she reached on the
      // **error**, and no getaway is charged. Never both an error and a passed
      // ball for the same advance.
      final onError = foldOfficialScoring(d3k(blockedThenThrewItAway: true));
      expect(onError.pitchGetaways, isEmpty);
      expect(onError.errors, isNotEmpty);

      // Nothing said and nothing linked: the catcher smothered it, retrieved
      // it cleanly, threw on time, and a fast batter simply beat it. Nobody is
      // charged anything — which the old derivation could not express, because
      // silence meant wild pitch.
      final beatTheThrow = foldOfficialScoring(d3k());
      expect(beatTheThrow.pitchGetaways, isEmpty);
      expect(beatTheThrow.errors, isEmpty);
    });

    test('the label decides, not the physics (§13.2 v0.49)', () {
      // Labelled a passed ball with no catcher touch behind it. This used to
      // score a **wild pitch** — the derivation read the absence of a touch as
      // meaning, and overruled the scorer who had just said otherwise.
      //
      // The evidence is optional to enter, which is what makes reading its
      // absence wrong: a `missed_catch` touch on a pitch nobody fielded is an
      // extra tap, so the old rule charged the pitcher whenever the scorer was
      // busy. Asking is cheaper than inferring from evidence that may not
      // exist.
      final scoring = foldOfficialScoring(getaway());
      expect(scoring.passedBalls, 1);
      expect(scoring.wildPitchesByPitcher, isEmpty);
      expect(
        scoring.pitchGetaways.single.position,
        isNull,
        reason: 'nobody was named, and it is still a passed ball',
      );
    });

    test('an explicit wild_pitch stays one even with a catcher touch', () {
      // The mirror of the case above, and the reason this is a rule rather
      // than a convenience: the label wins in both directions. A touch that
      // happens to exist does not promote a wild pitch into a passed ball.
      final scoring = foldOfficialScoring(
        getaway(
          reason: RunnerAdvanceReason.WILD_PITCH,
          catcherTouch: TouchType.MISSED_CATCH,
        ),
      );
      expect(scoring.wildPitchesByPitcher, {'pit': 1});
      expect(scoring.passedBalls, 0);
    });

    test('ordinaryEffort still governs the error, never the WP/PB split', () {
      // A catcher misplay she could not have held with ordinary effort is not
      // an error. That judgment is untouched — it simply no longer decides
      // *which* getaway this was, which is the scorer's call now.
      final scoring = foldOfficialScoring(
        getaway(catcherTouch: TouchType.MISSED_CATCH, ordinaryEffort: false),
      );
      expect(scoring.passedBalls, 1, reason: 'the chip said passed ball');
      expect(scoring.errors, isEmpty, reason: 'not ordinary effort, no error');
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
          outcome: Outcome.SWINGING_STRIKE,
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

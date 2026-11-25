import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/rules/earned_runs.dart';
import 'package:diamond/src/rules/logical_order.dart';
import 'package:diamond/src/rules/official_scoring.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

/// DIA-010: §13.5's overrides, and §13.3 per half-inning (v0.76).
void main() {
  GameEvent inPlay(EventBuilder b, String id, String batterId) => b.pitch(
    id: id,
    batterId: batterId,
    pitcherId: 'pit',
    outcome: Outcome.IN_PLAY,
  );

  /// b1 reaches on a boot by the SS, then scores on b2's single: the
  /// derivation rules the run unearned.
  List<GameEvent> bootThenSingle(EventBuilder b) => [
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
  ];

  /// b1 singles and scores on b2's single: earned, and b2's RBI.
  List<GameEvent> twoSingles(EventBuilder b) => [
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
  ];

  OfficialScoring score(List<GameEvent> raw) =>
      foldOfficialScoring(resolveVisibleLogicalOrder(raw));

  group('EarnedRunOverride', () {
    test('flips a derived unearned run to earned, keeping both', () {
      final b = EventBuilder();
      final run = score([
        ...bootThenSingle(b),
        b.earnedRunOverride(
          id: 'o1',
          runEventId: 'scores',
          earned: true,
          note: 'would have scored on the double anyway',
        ),
      ]).runs.single;

      expect(run.derivedEarned, isFalse);
      expect(run.earned, isTrue);
      expect(run.edited, isTrue);
      expect(
        run.earnedOverride!.note,
        'would have scored on the double anyway',
      );
    });

    test('flips a derived earned run to unearned', () {
      final b = EventBuilder();
      final run = score([
        ...twoSingles(b),
        b.earnedRunOverride(id: 'o1', runEventId: 'scores', earned: false),
      ]).runs.single;

      expect(run.derivedEarned, isTrue);
      expect(run.earned, isFalse);
    });

    test('a voided override reverts to the derivation', () {
      final b = EventBuilder();
      final run = score([
        ...bootThenSingle(b),
        b.earnedRunOverride(id: 'o1', runEventId: 'scores', earned: true),
        b.voidEvent(id: 'v1', targetId: 'o1'),
      ]).runs.single;

      expect(run.earned, isFalse);
      expect(run.edited, isFalse);
    });

    test('a corrected override is flipped by its latest version', () {
      final b = EventBuilder();
      final run = score([
        ...bootThenSingle(b),
        b.earnedRunOverride(id: 'o1', runEventId: 'scores', earned: true),
        b.earnedRunOverride(
          id: 'o2',
          runEventId: 'scores',
          earned: false,
          corrects: 'o1',
        ),
      ]).runs.single;

      expect(run.earned, isFalse);
      expect(run.edited, isTrue);
    });
  });

  group('RbiOverride', () {
    test("changes one run's credit and leaves the other run on the play", () {
      final b = EventBuilder();
      final scoring = score([
        inPlay(b, 'p1', 'b1'),
        b.ballInPlay(id: 'bip1', pitchEventId: 'p1'),
        b.runnerAdvance(
          id: 'r2-scores',
          runnerId: 'r2',
          from: 2,
          to: 4,
          reason: RunnerAdvanceReason.BATTED_BALL,
        ),
        b.runnerAdvance(
          id: 'r3-scores',
          runnerId: 'r3',
          from: 3,
          to: 4,
          reason: RunnerAdvanceReason.BATTED_BALL,
        ),
        b.runnerAdvance(
          id: 'reach',
          runnerId: 'b1',
          from: 0,
          to: 2,
          reason: RunnerAdvanceReason.BATTED_BALL,
        ),
        b.rbiOverride(id: 'o1', runEventId: 'r2-scores', rbi: false),
      ]);

      expect(scoring.batterOutcomes.single.rbi, 1);
      final byRunner = {for (final r in scoring.runs) r.runnerId: r};
      expect(byRunner['r2']!.rbi, isFalse);
      expect(byRunner['r2']!.derivedRbi, isTrue);
      expect(byRunner['r3']!.rbi, isTrue);
      expect(byRunner['r3']!.edited, isFalse);
    });

    test('credits a run the derivation does not', () {
      final b = EventBuilder();
      final scoring = score([
        inPlay(b, 'p1', 'b1'),
        b.runnerAdvance(
          id: 'wp-scores',
          runnerId: 'r3',
          from: 3,
          to: 4,
          reason: RunnerAdvanceReason.WILD_PITCH,
        ),
        b.rbiOverride(id: 'o1', runEventId: 'wp-scores', rbi: true),
      ]);

      expect(scoring.runs.single.derivedRbi, isFalse);
      expect(scoring.runs.single.batterId, 'b1');
      expect(scoring.batterOutcomes.single.rbi, 1);
    });
  });

  group("an override's anchor (v0.76)", () {
    test('follows its run through a correction', () {
      final b = EventBuilder();
      final scoring = score([
        ...twoSingles(b),
        // The scorer fixes the run's reason; the correction names the root.
        b.runnerAdvance(
          id: 'scores-v2',
          runnerId: 'b1',
          from: 1,
          to: 4,
          reason: RunnerAdvanceReason.WILD_PITCH,
          corrects: 'scores',
        ),
        b.rbiOverride(id: 'o1', runEventId: 'scores', rbi: true),
      ]);

      final run = scoring.runs.single;
      expect(run.eventId, 'scores-v2');
      expect(run.anchorId, 'scores');
      expect(run.derivedRbi, isFalse);
      expect(run.rbi, isTrue);
    });

    test('applies to nothing once its run is voided', () {
      final b = EventBuilder();
      final scoring = score([
        ...twoSingles(b),
        b.rbiOverride(id: 'o1', runEventId: 'scores', rbi: true),
        b.voidEvent(id: 'v1', targetId: 'scores'),
      ]);

      expect(scoring.runs, isEmpty);
      expect(scoring.batterOutcomes.map((o) => o.rbi), everyElement(0));
    });

    test('applies to nothing once its run is corrected to stop short', () {
      final b = EventBuilder();
      final scoring = score([
        ...twoSingles(b),
        b.earnedRunOverride(id: 'o1', runEventId: 'scores', earned: false),
        b.runnerAdvance(
          id: 'scores-v2',
          runnerId: 'b1',
          from: 1,
          to: 3,
          reason: RunnerAdvanceReason.BATTED_BALL,
          corrects: 'scores',
        ),
      ]);

      expect(scoring.runs, isEmpty);
    });

    test('naming something that is not a run is ignored', () {
      final b = EventBuilder();
      final scoring = score([
        ...twoSingles(b),
        b.earnedRunOverride(id: 'o1', runEventId: 'reach', earned: false),
        b.rbiOverride(id: 'o2', runEventId: 'p1', rbi: true),
      ]);

      final run = scoring.runs.single;
      expect(run.earned, isTrue);
      expect(run.edited, isFalse);
      expect(scoring.batterOutcomes.map((o) => o.rbi), [0, 1]);
    });
  });

  group('§13.3 per half-inning (v0.76)', () {
    List<GameEvent> threeOutHalf(EventBuilder b) => [
      b.inningHalfStart(
        id: 'top1',
        inning: 1,
        half: Half.TOP,
        battingTeamId: 'away',
      ),
      for (final n in [1, 2, 3]) ...[
        inPlay(b, 'out-p$n', 'a$n'),
        b.ballInPlay(id: 'out-bip$n', pitchEventId: 'out-p$n'),
        b.runnerOut(id: 'out$n', runnerId: 'a$n', atBase: 1, how: How.FORCE),
      ],
    ];

    test("a half's three outs do not make the next half's runs unearned", () {
      final b = EventBuilder();
      final rulings = reconstructEarnedRuns(
        resolveVisibleLogicalOrder([
          ...threeOutHalf(b),
          b.inningHalfStart(
            id: 'bot1',
            inning: 1,
            half: Half.BOTTOM,
            battingTeamId: 'home',
          ),
          ...twoSingles(b),
        ]),
      );

      expect(rulings, {'scores': RunRuling.earned});
    });

    test("a runner's taint does not carry into the next half", () {
      final b = EventBuilder();
      final rulings = reconstructEarnedRuns(
        resolveVisibleLogicalOrder([
          b.inningHalfStart(
            id: 'top1',
            inning: 1,
            half: Half.TOP,
            battingTeamId: 'away',
          ),
          // b1 reaches on the boot and is stranded.
          ...bootThenSingle(b).take(4),
          b.inningHalfEnd(id: 'end', reason: InningHalfEndReason.THREE_OUTS),
          b.inningHalfStart(
            id: 'top2',
            inning: 2,
            half: Half.TOP,
            battingTeamId: 'away',
          ),
          // Next time up she singles cleanly and scores.
          ...twoSingles(EventBuilder()).map(
            (e) => b.make(id: '${e.id}-2', type: e.type, payload: e.payload),
          ),
        ]),
      );

      expect(rulings, {'scores-2': RunRuling.earned});
    });
  });
}

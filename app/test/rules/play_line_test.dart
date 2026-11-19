import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/rules/official_scoring.dart';
import 'package:diamond/src/rules/play_line.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

/// DIA-024's grammar, against the examples Mark wrote it from
/// (2026-09-28/29). These are the acceptance cases: if they stop rendering
/// verbatim, the grammar has drifted from what a scorer says.
void main() {
  /// Names, so the lines read the way Mark wrote them. Identity itself
  /// belongs to roster building; this is the seam that work fills.
  String named(String id) => const {'b1': 'Jones', 'r1': 'Simmons'}[id] ?? id;

  List<String> linesFor(List<GameEvent> events) => [
    for (final line in playLines(foldOfficialScoring(events), label: named))
      line.text,
  ];

  /// §15.6's happenings — everything that occurs between pitches, each
  /// enterable from the idle field. *Left early* and the *look-back rule*
  /// gained their writer in DIA-019 slice H.
  group('between pitches', () {
    List<String> after(List<GameEvent> tail) {
      final b = EventBuilder();
      return linesFor([
        b.pitch(
          id: 'p',
          batterId: 'b1',
          pitcherId: 'pit',
          outcome: Outcome.BALL,
        ),
        ...tail,
      ]);
    }

    test('a stolen base', () {
      final b = EventBuilder();
      expect(
        after([
          b.runnerAdvance(
            id: 'sb',
            runnerId: 'r1',
            from: 1,
            to: 2,
            reason: RunnerAdvanceReason.STOLEN_BASE,
          ),
        ]),
        ['Simmons stole second.'],
      );
    });

    test('a wild pitch leads with the ball, not with the runner', () {
      final b = EventBuilder();
      expect(
        after([
          b.runnerAdvance(
            id: 'wp',
            runnerId: 'r1',
            from: 2,
            to: 3,
            reason: RunnerAdvanceReason.WILD_PITCH,
          ),
        ]),
        ['Wild pitch, Simmons advanced to third.'],
      );
    });

    test('a passed ball, with the catcher miss §13.2 pairs it with', () {
      // The touch is recorded and charges nothing — a passed ball is not an
      // error — so it earns no sentence of its own.
      final b = EventBuilder();
      expect(
        after([
          b.fielderTouch(
            id: 'pb',
            anchorEventId: 'p',
            position: 2,
            touchType: TouchType.MISSED_CATCH,
          ),
          b.runnerAdvance(
            id: 'adv',
            runnerId: 'r1',
            from: 2,
            to: 3,
            reason: RunnerAdvanceReason.PASSED_BALL,
            enabledByTouchId: 'pb',
          ),
        ]),
        ['Passed ball, Simmons advanced to third.'],
      );
    });

    test('defensive indifference says so rather than crediting a steal', () {
      final b = EventBuilder();
      expect(
        after([
          b.runnerAdvance(
            id: 'di',
            runnerId: 'r1',
            from: 1,
            to: 2,
            reason: RunnerAdvanceReason.DEFENSIVE_INDIFFERENCE,
          ),
        ]),
        ['Simmons advanced to second on defensive indifference.'],
      );
    });

    test('caught stealing', () {
      final b = EventBuilder();
      expect(
        after([
          b.runnerOut(
            id: 'cs',
            runnerId: 'r1',
            atBase: 2,
            how: How.CAUGHT_STEALING,
          ),
        ]),
        ['Simmons caught stealing second.'],
      );
    });

    test('a pickoff', () {
      final b = EventBuilder();
      expect(
        after([
          b.runnerOut(id: 'po', runnerId: 'r1', atBase: 1, how: How.PICKED_OFF),
        ]),
        ['Simmons picked off first.'],
      );
    });

    test('a runner who left early', () {
      final b = EventBuilder();
      expect(
        after([
          b.runnerOut(id: 'le', runnerId: 'r1', atBase: 1, how: How.LEFT_EARLY),
        ]),
        ['Simmons out, left early.'],
      );
    });

    test('a runner out on the look-back rule', () {
      final b = EventBuilder();
      expect(
        after([
          b.runnerOut(
            id: 'lb',
            runnerId: 'r1',
            atBase: 1,
            how: How.LOOK_BACK_RULE,
          ),
        ]),
        ['Simmons out on the look-back rule.'],
      );
    });

    test('a pitch that was only a pitch gets no line at all', () {
      expect(after(const []), isEmpty);
    });
  });

  test('a hit says where she ended up, so nothing trails it', () {
    // "Jones doubled to left, Simmons advanced to third."
    final b = EventBuilder();
    expect(
      linesFor([
        b.pitch(
          id: 'p',
          batterId: 'b1',
          pitcherId: 'pit',
          outcome: Outcome.IN_PLAY,
        ),
        b.ballInPlay(
          id: 'bip',
          pitchEventId: 'p',
          trajectory: Trajectory.LINE,
          landing: FieldCoord(x: -150, y: 150),
        ),
        b.runnerAdvance(
          id: 'a1',
          runnerId: 'b1',
          from: 0,
          to: 2,
          reason: RunnerAdvanceReason.BATTED_BALL,
        ),
        b.runnerAdvance(
          id: 'a2',
          runnerId: 'r1',
          from: 1,
          to: 3,
          reason: RunnerAdvanceReason.BATTED_BALL,
        ),
      ]),
      ['Jones doubled to left, Simmons advanced to third.'],
    );
  });

  test("a fielder's choice names the ball, then the out, then her", () {
    // "Jones grounded to SS, Simmons out at second on a fielder's choice,
    //  Jones to first."
    final b = EventBuilder();
    expect(
      linesFor([
        b.pitch(
          id: 'p',
          batterId: 'b1',
          pitcherId: 'pit',
          outcome: Outcome.IN_PLAY,
        ),
        b.ballInPlay(
          id: 'bip',
          pitchEventId: 'p',
          landing: FieldCoord(x: -50, y: 95),
        ),
        b.fielderTouch(
          id: 't',
          anchorEventId: 'bip',
          position: 6,
          touchType: TouchType.FIELDED,
        ),
        b.runnerOut(id: 'o', runnerId: 'r1', atBase: 2, how: How.FORCE),
        b.runnerAdvance(
          id: 'a',
          runnerId: 'b1',
          from: 0,
          to: 1,
          reason: RunnerAdvanceReason.FIELDERS_CHOICE,
        ),
      ]),
      [
        // One expected line, wrapped to fit the column limit — not two
        // list entries.
        // ignore: no_adjacent_strings_in_list
        'Jones grounded to SS, Simmons out at second '
            "on a fielder's choice, Jones to first.",
      ],
    );
  });

  test('an out closes the sentence it belongs to, not the one before it', () {
    // She bunted, reached first on the throw, then was thrown out trying
    // for second. Rendering the out with the bunt put it ahead of the reach
    // it followed (Mark, 2026-10-12) — and joining it to the advances with
    // "and" would read as though the error caused it, which it did not.
    final b = EventBuilder();
    expect(
      linesFor([
        b.pitch(
          id: 'p',
          batterId: 'b1',
          pitcherId: 'pit',
          outcome: Outcome.IN_PLAY,
        ),
        b.ballInPlay(
          id: 'bip',
          pitchEventId: 'p',
          trajectory: Trajectory.BUNT,
          landing: FieldCoord(x: -40, y: 50),
        ),
        b.fielderTouch(
          id: 't',
          anchorEventId: 'bip',
          position: 5,
          touchType: TouchType.FIELDED,
        ),
        b.fielderTouch(
          id: 'wt',
          anchorEventId: 'bip',
          position: 5,
          touchType: TouchType.WILD_THROW,
        ),
        b.runnerAdvance(
          id: 'a',
          runnerId: 'b1',
          from: 0,
          to: 1,
          reason: RunnerAdvanceReason.ERROR,
          enabledByTouchId: 'wt',
        ),
        b.runnerOut(id: 'o', runnerId: 'b1', atBase: 2, how: How.TAG),
      ]),
      [
        // One expected line, wrapped to fit the column limit.
        // ignore: no_adjacent_strings_in_list
        'Jones bunted to 3B. On a throwing error by the 3B, '
            'Jones advanced to first, Jones out advancing to second.',
      ],
    );
  });

  test('a runner doubled off is not advancing — she is tagged where she '
      'started', () {
    // The other half of the rule. A force is compelled, so it is not an
    // attempt at anything; and being out at a base she had already reached
    // is the opposite of trying for an extra one (Mark, 2026-10-13).
    final b = EventBuilder();
    expect(
      linesFor([
        b.pitch(
          id: 'p',
          batterId: 'b1',
          pitcherId: 'pit',
          outcome: Outcome.IN_PLAY,
        ),
        b.ballInPlay(
          id: 'bip',
          pitchEventId: 'p',
          trajectory: Trajectory.LINE,
          landing: FieldCoord(x: -40, y: 95),
        ),
        b.fielderTouch(
          id: 'c',
          anchorEventId: 'bip',
          position: 6,
          touchType: TouchType.CAUGHT,
        ),
        b.runnerOut(id: 'o1', runnerId: 'b1', atBase: 1, how: How.FLY_OUT),
        // Off the bag when it was caught, and thrown back to first.
        b.fielderTouch(
          id: 'back',
          anchorEventId: 'bip',
          position: 3,
          touchType: TouchType.RECEIVED_THROW,
        ),
        b.runnerOut(
          id: 'o2',
          runnerId: 'r1',
          atBase: 1,
          how: How.TAG,
          putoutTouchId: 'back',
        ),
      ]),
      ['Jones lined out to SS, Simmons out SS to 1B.'],
    );
  });

  test('a leg past her hit is said, on the throw when one enabled it '
      '(v0.71)', () {
    // "singled" says first and no more, so second needs its own clause.
    final b = EventBuilder();
    expect(
      linesFor([
        b.pitch(
          id: 'p',
          batterId: 'b1',
          pitcherId: 'pit',
          outcome: Outcome.IN_PLAY,
        ),
        b.ballInPlay(
          id: 'bip',
          pitchEventId: 'p',
          trajectory: Trajectory.LINE,
          landing: FieldCoord(x: 110, y: 160),
        ),
        b.runnerAdvance(
          id: 'a1',
          runnerId: 'b1',
          from: 0,
          to: 1,
          reason: RunnerAdvanceReason.BATTED_BALL,
        ),
        b.fielderTouch(
          id: 'rf',
          anchorEventId: 'bip',
          position: 9,
          touchType: TouchType.FIELDED,
        ),
        b.fielderTouch(
          id: 'c',
          anchorEventId: 'bip',
          position: 2,
          touchType: TouchType.RECEIVED_THROW,
        ),
        b.runnerAdvance(
          id: 'a2',
          runnerId: 'b1',
          from: 1,
          to: 2,
          reason: RunnerAdvanceReason.BATTED_BALL,
          enabledByTouchId: 'rf',
        ),
      ]),
      ['Jones singled to right, Jones advanced to second on the throw.'],
    );
  });

  group('the putout chain (v0.71)', () {
    // A rundown, 6-5-6-5: Simmons, caught between second and third.
    List<GameEvent> rundown({bool dropped = false}) {
      final b = EventBuilder();
      return [
        b.pitch(
          id: 'p',
          batterId: 'b1',
          pitcherId: 'pit',
          outcome: Outcome.IN_PLAY,
        ),
        b.ballInPlay(
          id: 'bip',
          pitchEventId: 'p',
          landing: FieldCoord(x: -40, y: 95),
        ),
        b.fielderTouch(
          id: 't1',
          anchorEventId: 'bip',
          position: 6,
          touchType: TouchType.FIELDED,
        ),
        b.fielderTouch(
          id: 't2',
          anchorEventId: 'bip',
          position: 5,
          touchType: dropped ? TouchType.DROPPED : TouchType.RECEIVED_THROW,
        ),
        if (dropped)
          b.fielderTouch(
            id: 't2b',
            anchorEventId: 'bip',
            position: 5,
            touchType: TouchType.FIELDED,
          ),
        b.fielderTouch(
          id: 't3',
          anchorEventId: 'bip',
          position: 6,
          touchType: TouchType.RECEIVED_THROW,
        ),
        b.fielderTouch(
          id: 't4',
          anchorEventId: 'bip',
          position: 5,
          touchType: TouchType.RECEIVED_THROW,
        ),
        b.fielderTouch(
          id: 't5',
          anchorEventId: 'bip',
          position: 5,
          touchType: TouchType.TAG_APPLIED,
        ),
        b.runnerOut(
          id: 'o',
          runnerId: 'r1',
          atBase: 3,
          how: How.TAG,
          putoutTouchId: 't5',
        ),
      ];
    }

    test('names two throws at most, the last ones; the box credits all', () {
      // Mark, 2026-11-19: "We don't want more than two throws showing up."
      final events = rundown();
      expect(linesFor(events).single, contains('3B to SS to 3B'));
      expect(linesFor(events).single, isNot(contains('SS to 3B to SS')));
      final scoring = foldOfficialScoring(events);
      expect(scoring.assistsByPosition, {6: 1});
      expect(scoring.putoutsByPosition, {5: 1});
    });

    test('a misplay restarts it: nothing before the drop assists', () {
      // The third baseman drops the first throw, picks it up, and the
      // rundown goes on from her: 5-6-5, and the shortstop's first throw
      // earns nothing.
      final events = rundown(dropped: true);
      expect(linesFor(events).single, contains('3B to SS to 3B'));
      expect(foldOfficialScoring(events).assistsByPosition, {6: 1});
    });

    test('putoutChain is the ordered handlers, repeats in a row merged', () {
      final events = rundown();
      final touches = [
        for (final e in events)
          if (e.type == 'FielderTouch')
            (eventId: e.id, payload: FielderTouch.fromJson(e.payload)),
      ];
      expect(putoutChain(touches, 't5'), [6, 5, 6, 5]);
      expect(putoutChain(touches, 'nope'), isEmpty);
    });
  });

  test('an error is its own sentence, led by the charge', () {
    // "Jones doubled to left, Simmons advanced to third.
    //  On a fielding error by LF, Simmons scored and Jones advanced to third."
    final b = EventBuilder();
    expect(
      linesFor([
        b.pitch(
          id: 'p',
          batterId: 'b1',
          pitcherId: 'pit',
          outcome: Outcome.IN_PLAY,
        ),
        b.ballInPlay(
          id: 'bip',
          pitchEventId: 'p',
          trajectory: Trajectory.LINE,
          landing: FieldCoord(x: -150, y: 150),
        ),
        b.runnerAdvance(
          id: 'a1',
          runnerId: 'b1',
          from: 0,
          to: 2,
          reason: RunnerAdvanceReason.BATTED_BALL,
        ),
        b.runnerAdvance(
          id: 'a2',
          runnerId: 'r1',
          from: 1,
          to: 3,
          reason: RunnerAdvanceReason.BATTED_BALL,
        ),
        b.fielderTouch(
          id: 'boot',
          anchorEventId: 'bip',
          position: 7,
          touchType: TouchType.BOOTED,
        ),
        b.runnerAdvance(
          id: 'a3',
          runnerId: 'r1',
          from: 3,
          to: 4,
          reason: RunnerAdvanceReason.ERROR,
          enabledByTouchId: 'boot',
        ),
        b.runnerAdvance(
          id: 'a4',
          runnerId: 'b1',
          from: 2,
          to: 3,
          reason: RunnerAdvanceReason.ERROR,
          enabledByTouchId: 'boot',
        ),
      ]),
      [
        // One expected line, wrapped to fit the column limit — not two
        // list entries.
        // ignore: no_adjacent_strings_in_list
        'Jones doubled to left, Simmons advanced to third. '
            'On a fielding error by the LF, Simmons scored '
            'and Jones advanced to third.',
      ],
    );
  });
}

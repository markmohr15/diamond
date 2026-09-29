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

  /// §15.6's happenings — everything that occurs between pitches. All
  /// seven read from the model today; only *left early* is not yet
  /// enterable, since `How.LEFT_EARLY` has no writer in the UI (DIA-019
  /// slice H). The formatter carries it regardless, so it renders the day
  /// H makes it recordable.
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

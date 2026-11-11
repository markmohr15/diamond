import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/ui/loop/pitch_flow.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../rules/test_helpers.dart';

/// The top-bar undo names **what happened** (Mark, 2026-11-10): UNDO
/// SINGLE, UNDO FC, UNDO K — with wild pitch and passed ball abbreviated
/// (2026-11-09). A play's words come from official scoring, so the button
/// says what the play log says.
void main() {
  late EventBuilder b;
  setUp(() => b = EventBuilder());

  GameEvent pitch(String id, Outcome outcome, {String batter = 'b1'}) =>
      b.pitch(id: id, batterId: batter, pitcherId: 'pit', outcome: outcome);

  /// An in-play pitch and its ball, then whatever the play did.
  List<GameEvent> play({
    Trajectory trajectory = Trajectory.GROUND,
    List<GameEvent> Function()? then,
  }) => [
    pitch('p1', Outcome.IN_PLAY),
    b.ballInPlay(id: 'bip', pitchEventId: 'p1', trajectory: trajectory),
    ...?then?.call(),
  ];

  String label(List<GameEvent> stream, String rootId) =>
      undoLabelFor(stream.firstWhere((e) => e.id == rootId), stream);

  group('a pitch, by its outcome', () {
    test('ball, strike, foul', () {
      final stream = [
        pitch('p1', Outcome.BALL),
        pitch('p2', Outcome.SWINGING_STRIKE),
        pitch('p3', Outcome.FOUL),
      ];
      expect(label(stream, 'p1'), 'UNDO BALL');
      expect(label(stream, 'p2'), 'UNDO STRIKE');
      expect(label(stream, 'p3'), 'UNDO FOUL');
    });

    test('ball four is a WALK', () {
      final stream = [
        for (var i = 1; i <= 4; i++) pitch('p$i', Outcome.BALL),
        b.runnerAdvance(
          id: 'w',
          runnerId: 'b1',
          from: 0,
          to: 1,
          reason: RunnerAdvanceReason.WALK,
        ),
      ];
      expect(label(stream, 'p3'), 'UNDO BALL');
      expect(label(stream, 'p4'), 'UNDO WALK');
    });

    test('strike three is a K', () {
      final stream = [
        for (var i = 1; i <= 3; i++) pitch('p$i', Outcome.CALLED_STRIKE),
        b.runnerOut(id: 'k', runnerId: 'b1', atBase: 0, how: How.STRIKEOUT),
      ];
      expect(label(stream, 'p3'), 'UNDO K');
    });

    test('an in-play pitch whose play is already gone', () {
      expect(label([pitch('p1', Outcome.IN_PLAY)], 'p1'), 'UNDO IN PLAY');
    });
  });

  group('a committed play, by what it scored as', () {
    test('a single', () {
      final stream = play(
        then: () => [
          b.fielderTouch(
            id: 't',
            anchorEventId: 'bip',
            position: 8,
            touchType: TouchType.FIELDED,
          ),
          b.runnerAdvance(
            id: 'a',
            runnerId: 'b1',
            from: 0,
            to: 1,
            reason: RunnerAdvanceReason.BATTED_BALL,
          ),
        ],
      );
      expect(label(stream, 'bip'), 'UNDO SINGLE');
    });

    test('a groundout to first', () {
      final stream = play(
        then: () => [
          b.fielderTouch(
            id: 't6',
            anchorEventId: 'bip',
            position: 6,
            touchType: TouchType.FIELDED,
          ),
          b.fielderTouch(
            id: 't3',
            anchorEventId: 'bip',
            position: 3,
            touchType: TouchType.RECEIVED_THROW,
          ),
          b.runnerOut(
            id: 'o',
            runnerId: 'b1',
            atBase: 1,
            how: How.FORCE,
            putoutTouchId: 't3',
          ),
        ],
      );
      expect(label(stream, 'bip'), 'UNDO GROUNDOUT');
    });

    test('a caught line drive', () {
      final stream = play(
        trajectory: Trajectory.LINE,
        then: () => [
          b.fielderTouch(
            id: 't',
            anchorEventId: 'bip',
            position: 4,
            touchType: TouchType.CAUGHT,
          ),
          b.runnerOut(
            id: 'o',
            runnerId: 'b1',
            atBase: 0,
            how: How.FLY_OUT,
            putoutTouchId: 't',
          ),
        ],
      );
      expect(label(stream, 'bip'), 'UNDO LINEOUT');
    });

    test('two outs on the play is a DP', () {
      final stream = play(
        then: () => [
          b.runnerOut(id: 'o1', runnerId: 'r1', atBase: 2, how: How.FORCE),
          b.runnerOut(id: 'o2', runnerId: 'b1', atBase: 1, how: How.FORCE),
        ],
      );
      expect(label(stream, 'bip'), 'UNDO DP');
    });
  });

  group('between pitches', () {
    for (final (reason, words) in [
      ('wild_pitch', 'UNDO WP'),
      ('passed_ball', 'UNDO PB'),
      ('stolen_base', 'UNDO STEAL'),
      ('defensive_indifference', 'UNDO INDIFFERENCE'),
    ]) {
      test('a $reason reads $words', () {
        final root = b.make(
          id: 'adv',
          type: 'RunnerAdvance',
          payload: {'runnerId': 'r1', 'from': 1, 'to': 2, 'reason': reason},
        );
        expect(undoLabelFor(root, [root]), words);
      });
    }

    for (final (how, words) in [
      ('caught_stealing', 'UNDO CAUGHT STEALING'),
      ('picked_off', 'UNDO PICKOFF'),
    ]) {
      test('a $how reads $words', () {
        final root = b.make(
          id: 'out',
          type: 'RunnerOut',
          payload: {'runnerId': 'r1', 'atBase': 2, 'how': how},
        );
        expect(undoLabelFor(root, [root]), words);
      });
    }
  });

  test('a count correction', () {
    final root = b.make(
      id: 'cc',
      type: 'CountCorrection',
      payload: const {'balls': 2, 'strikes': 1},
    );
    expect(undoLabelFor(root, [root]), 'UNDO COUNT FIX');
  });
}

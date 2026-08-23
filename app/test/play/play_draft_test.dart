import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/play/play_draft.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const base = PlayDraft(pitchEventId: 'pitch-1', batterId: 'opp-1');

  group('PlayDraft JSON (the §15.5 journal format)', () {
    test('round-trips a full draft', () {
      final draft = base
          .copyWith(
            landing: FieldCoord(x: -45, y: 120),
            retrieved: FieldCoord(x: -80, y: 180),
            trajectory: Trajectory.LINE,
            offWall: true,
          )
          .movingRunner('opp-1', from: 0, to: 2)
          .movingRunner('opp-9', from: 2, to: 4);

      final back = PlayDraft.fromJson(draft.toJson());
      expect(back.pitchEventId, 'pitch-1');
      expect(back.batterId, 'opp-1');
      expect(back.landing!.x, -45);
      expect(back.retrieved!.y, 180);
      expect(back.trajectory, Trajectory.LINE);
      expect(back.offWall, isTrue);
      expect(back.landingIsCaught, isFalse);
      expect(back.runnerMoves, hasLength(2));
      expect(back.runnerMoves.first.runnerId, 'opp-1');
      expect(back.runnerMoves.last.to, 4);
    });

    test('round-trips the empty draft the surface opens with', () {
      final back = PlayDraft.fromJson(base.toJson());
      expect(back.landing, isNull);
      expect(back.retrieved, isNull);
      expect(back.trajectory, isNull);
      expect(back.runnerMoves, isEmpty);
    });
  });

  group('runner moves: one per runner, net advance', () {
    test('a re-drag replaces the target, keeping origin and entry order', () {
      final draft = base
          .movingRunner('opp-1', from: 0, to: 1)
          .movingRunner('opp-9', from: 1, to: 2)
          .movingRunner('opp-1', from: 0, to: 3);
      expect(draft.runnerMoves, hasLength(2));
      expect(draft.runnerMoves.first.runnerId, 'opp-1');
      expect(draft.runnerMoves.first.from, 0);
      expect(draft.runnerMoves.first.to, 3);
      expect(draft.runnerMoves.last.runnerId, 'opp-9');
    });
  });

  group('cascadeRunnerMove: runners never pass each other', () {
    test('bases-loaded single: the whole chain walks up, run included', () {
      final moves = cascadeRunnerMove(
        [
          (runnerId: 'b', origin: 0, base: 0),
          (runnerId: 'r1', origin: 1, base: 1),
          (runnerId: 'r2', origin: 2, base: 2),
          (runnerId: 'r3', origin: 3, base: 3),
        ],
        movedId: 'b',
        to: 1,
      );
      expect(moves.map((m) => (m.runnerId, m.from, m.to)), [
        ('b', 0, 1),
        ('r1', 1, 2),
        ('r2', 2, 3),
        ('r3', 3, 4),
      ]);
    });

    test('double with R1: the batter passing first pushes R1 to third', () {
      final moves = cascadeRunnerMove(
        [
          (runnerId: 'b', origin: 0, base: 0),
          (runnerId: 'r1', origin: 1, base: 1),
        ],
        movedId: 'b',
        to: 2,
      );
      expect(moves.map((m) => (m.runnerId, m.from, m.to)), [
        ('b', 0, 2),
        ('r1', 1, 3),
      ]);
    });

    test('no force, no push: R2 holds on a single behind her', () {
      final moves = cascadeRunnerMove(
        [
          (runnerId: 'b', origin: 0, base: 0),
          (runnerId: 'r2', origin: 2, base: 2),
        ],
        movedId: 'b',
        to: 1,
      );
      expect(moves.map((m) => (m.runnerId, m.to)), [('b', 1)]);
    });

    test('a leader already moved ahead in the draft absorbs the chain', () {
      // R1 was dragged to third earlier this play; the batter reaching
      // first displaces nobody.
      final moves = cascadeRunnerMove(
        [
          (runnerId: 'b', origin: 0, base: 0),
          (runnerId: 'r1', origin: 1, base: 3),
        ],
        movedId: 'b',
        to: 1,
      );
      expect(moves, hasLength(1));
    });

    test('a scored leader is out of the way, never re-pushed', () {
      final moves = cascadeRunnerMove(
        [
          (runnerId: 'b', origin: 0, base: 0),
          (runnerId: 'r1', origin: 1, base: 4),
        ],
        movedId: 'b',
        to: 1,
      );
      expect(moves, hasLength(1));
    });

    test('trailing runners never move automatically', () {
      // R1 dragged to third: the batter stays put behind her.
      final moves = cascadeRunnerMove(
        [
          (runnerId: 'b', origin: 0, base: 0),
          (runnerId: 'r1', origin: 1, base: 1),
        ],
        movedId: 'r1',
        to: 3,
      );
      expect(moves.map((m) => (m.runnerId, m.to)), [('r1', 3)]);
    });
  });

  group('copyWith', () {
    test('an explicit null retrieved clears it — a re-tap after a drag', () {
      final rolled = base.copyWith(
        landing: FieldCoord(x: 10, y: 100),
        retrieved: FieldCoord(x: 10, y: 150),
      );
      final retapped = rolled.copyWith(
        landing: FieldCoord(x: 20, y: 110),
        retrieved: null,
      );
      expect(retapped.retrieved, isNull);
      expect(rolled.copyWith(trajectory: Trajectory.FLY).retrieved, isNotNull);
    });
  });

  group('toEvents (§15.5 atomic commit)', () {
    test('refuses an incomplete draft — the ✓ should never have fired', () {
      expect(base.toEvents, throwsStateError);
      expect(
        base.copyWith(landing: FieldCoord(x: 0, y: 100)).toEvents,
        throwsStateError,
      );
      expect(base.committable, isFalse);
    });

    test('a clean single: BallInPlay, then the advance, in order', () {
      final draft = base
          .copyWith(
            landing: FieldCoord(x: 110, y: 180),
            trajectory: Trajectory.LINE,
          )
          .movingRunner('opp-1', from: 0, to: 1);
      expect(draft.committable, isTrue);

      final events = draft.toEvents();
      expect(events.map((e) => e.type), ['BallInPlay', 'RunnerAdvance']);

      final ball = BallInPlay.fromJson(events.first.payload);
      expect(ball.pitchEventId, 'pitch-1');
      expect(ball.fair, isTrue);
      expect(ball.trajectory, Trajectory.LINE);
      expect(ball.landing.x, 110);
      expect(ball.landingIsCaught, isFalse);
      expect(ball.retrieved, isNull);
      // Not suggested, not asserted: absent, never `false` noise.
      expect(events.first.payload['offWall'], isNull);

      final advance = RunnerAdvance.fromJson(events.last.payload);
      expect(advance.runnerId, 'opp-1');
      expect(advance.from, 0);
      expect(advance.to, 1);
      expect(advance.reason, RunnerAdvanceReason.BATTED_BALL);
    });

    test('carries the roll and the wall when present', () {
      final draft = base.copyWith(
        landing: FieldCoord(x: 0, y: 208),
        retrieved: FieldCoord(x: 30, y: 180),
        trajectory: Trajectory.FLY,
        offWall: true,
      );
      final ball = BallInPlay.fromJson(draft.toEvents().single.payload);
      expect(ball.retrieved!.x, 30);
      expect(ball.offWall, isTrue);
    });
  });
}

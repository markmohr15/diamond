import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/rules/game_state.dart';
import 'package:diamond/src/rules/game_state_fold.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

void main() {
  test(
    'LineupSet seeds batting order; InningHalfStart resets per-half state',
    () {
      final b = EventBuilder();
      final events = [
        b.lineupSet(
          id: 'lineup-home',
          teamId: 'home',
          battingOrder: ['h1', 'h2', 'h3'],
        ),
        b.inningHalfStart(
          id: 'half1',
          inning: 1,
          half: Half.BOTTOM,
          battingTeamId: 'home',
        ),
      ];

      final state = foldGameState(events);

      expect(state.inning, 1);
      expect(state.half, Half.BOTTOM);
      expect(state.battingTeamId, 'home');
      expect(state.balls, 0);
      expect(state.strikes, 0);
      expect(state.outs, 0);
      expect(state.batterDue('home'), 'h1');
    },
  );

  test('a batter change resets the count even mid-half', () {
    final b = EventBuilder();
    final events = [
      b.lineupSet(id: 'lineup', teamId: 'home', battingOrder: ['h1', 'h2']),
      b.inningHalfStart(
        id: 'half1',
        inning: 1,
        half: Half.BOTTOM,
        battingTeamId: 'home',
      ),
      b.pitch(id: 'p1', batterId: 'h1', pitcherId: 'p', outcome: Outcome.BALL),
      b.pitch(id: 'p2', batterId: 'h1', pitcherId: 'p', outcome: Outcome.BALL),
      // h1's AB ends via a ball in play (no explicit walk/strikeout needed
      // to demonstrate the reset — in_play always ends the AB).
      b.pitch(
        id: 'p3',
        batterId: 'h1',
        pitcherId: 'p',
        outcome: Outcome.IN_PLAY,
      ),
      b.pitch(
        id: 'p4',
        batterId: 'h2',
        pitcherId: 'p',
        outcome: Outcome.CALLED_STRIKE,
      ),
    ];

    final state = foldGameState(events);

    expect(state.balls, 0);
    expect(state.strikes, 1);
    expect(state.batterDue('home'), 'h2');
  });

  test('a walk ends the AB and advances batterDue', () {
    final b = EventBuilder();
    final events = [
      b.lineupSet(id: 'lineup', teamId: 'home', battingOrder: ['h1', 'h2']),
      b.inningHalfStart(
        id: 'half1',
        inning: 1,
        half: Half.BOTTOM,
        battingTeamId: 'home',
      ),
      for (var i = 0; i < 4; i++)
        b.pitch(
          id: 'p$i',
          batterId: 'h1',
          pitcherId: 'p',
          outcome: Outcome.BALL,
        ),
    ];

    final state = foldGameState(events);

    expect(state.balls, 0, reason: 'the AB-ending pitch resets the count');
    expect(state.batterDue('home'), 'h2');
  });

  test('RunnerOut increments outs and clears the runner from base', () {
    final b = EventBuilder();
    final events = [
      b.lineupSet(id: 'lineup', teamId: 'away', battingOrder: ['a1']),
      b.inningHalfStart(
        id: 'half1',
        inning: 1,
        half: Half.TOP,
        battingTeamId: 'away',
      ),
      b.runnerAdvance(
        id: 'adv1',
        runnerId: 'r1',
        from: 0,
        to: 1,
        reason: RunnerAdvanceReason.WALK,
      ),
      b.runnerOut(
        id: 'out1',
        runnerId: 'r1',
        atBase: 2,
        how: How.CAUGHT_STEALING,
      ),
    ];

    final state = foldGameState(events);

    expect(state.outs, 1);
    expect(state.bases.first, isNull);
    expect(state.halfEnded, isFalse);
  });

  test('three outs auto-ends the half without an explicit InningHalfEnd', () {
    final b = EventBuilder();
    final events = [
      b.lineupSet(id: 'lineup', teamId: 'away', battingOrder: ['a1']),
      b.inningHalfStart(
        id: 'half1',
        inning: 1,
        half: Half.TOP,
        battingTeamId: 'away',
      ),
      b.runnerOut(id: 'o1', runnerId: 'r1', atBase: 1, how: How.STRIKEOUT),
      b.runnerOut(id: 'o2', runnerId: 'r2', atBase: 1, how: How.STRIKEOUT),
      b.runnerOut(id: 'o3', runnerId: 'r3', atBase: 1, how: How.STRIKEOUT),
    ];

    final state = foldGameState(events);

    expect(state.outs, 3);
    expect(state.halfEnded, isTrue);
    expect(state.halfEndReason, InningHalfEndReason.THREE_OUTS);
  });

  test('run_cap closes the half early, with outs still under 3', () {
    final b = EventBuilder();
    final events = [
      b.lineupSet(id: 'lineup', teamId: 'home', battingOrder: ['h1']),
      b.inningHalfStart(
        id: 'half1',
        inning: 4,
        half: Half.BOTTOM,
        battingTeamId: 'home',
      ),
      b.runnerOut(id: 'o1', runnerId: 'r1', atBase: 1, how: How.STRIKEOUT),
      b.inningHalfEnd(id: 'end1', reason: InningHalfEndReason.RUN_CAP),
    ];

    final state = foldGameState(events);

    expect(state.outs, 1);
    expect(state.halfEnded, isTrue);
    expect(state.halfEndReason, InningHalfEndReason.RUN_CAP);
  });

  test('a stolen base moves the runner without changing outs or the AB', () {
    final b = EventBuilder();
    final events = [
      b.lineupSet(id: 'lineup', teamId: 'away', battingOrder: ['a1']),
      b.inningHalfStart(
        id: 'half1',
        inning: 1,
        half: Half.TOP,
        battingTeamId: 'away',
      ),
      b.runnerAdvance(
        id: 'adv1',
        runnerId: 'r1',
        from: 0,
        to: 1,
        reason: RunnerAdvanceReason.WALK,
      ),
      b.runnerAdvance(
        id: 'steal',
        runnerId: 'r1',
        from: 1,
        to: 2,
        reason: RunnerAdvanceReason.STOLEN_BASE,
      ),
    ];

    final state = foldGameState(events);

    expect(state.bases.first, isNull);
    expect(state.bases.second, 'r1');
  });

  test('a run scores and credits the batting team', () {
    final b = EventBuilder();
    final events = [
      b.lineupSet(id: 'lineup', teamId: 'home', battingOrder: ['h1']),
      b.inningHalfStart(
        id: 'half1',
        inning: 1,
        half: Half.BOTTOM,
        battingTeamId: 'home',
      ),
      b.runnerAdvance(
        id: 'adv1',
        runnerId: 'r1',
        from: 0,
        to: 3,
        reason: RunnerAdvanceReason.BATTED_BALL,
      ),
      b.runnerAdvance(
        id: 'score',
        runnerId: 'r1',
        from: 3,
        to: 4,
        reason: RunnerAdvanceReason.BATTED_BALL,
      ),
    ];

    final state = foldGameState(events);

    expect(state.bases.third, isNull);
    expect(state.runsByTeam['home'], 1);
  });

  test('from == to records surviving a play with no base change', () {
    final b = EventBuilder();
    final events = [
      b.lineupSet(id: 'lineup', teamId: 'away', battingOrder: ['a1']),
      b.inningHalfStart(
        id: 'half1',
        inning: 1,
        half: Half.TOP,
        battingTeamId: 'away',
      ),
      b.runnerAdvance(
        id: 'adv1',
        runnerId: 'r1',
        from: 0,
        to: 1,
        reason: RunnerAdvanceReason.WALK,
      ),
      b.runnerAdvance(
        id: 'survive',
        runnerId: 'r1',
        from: 1,
        to: 1,
        reason: RunnerAdvanceReason.ERROR,
      ),
    ];

    final state = foldGameState(events);

    expect(state.bases.first, 'r1');
  });

  test(
    "AB-boundary refusal: a prior batter's dangling unknown pitch is never "
    "touched by a later batter's CountCorrection, regardless of whether "
    'the arithmetic would happen to line up',
    () {
      final b = EventBuilder();
      final events = [
        b.lineupSet(id: 'lineup', teamId: 'home', battingOrder: ['A', 'B']),
        b.inningHalfStart(
          id: 'half1',
          inning: 1,
          half: Half.BOTTOM,
          battingTeamId: 'home',
        ),
        // Batter A: one unknown pitch, then the AB ends — this unknown is
        // never resolved by any CountCorrection and stays unknown forever.
        b.pitch(
          id: 'a-unknown',
          batterId: 'A',
          pitcherId: 'p',
          outcome: Outcome.UNKNOWN,
        ),
        b.pitch(
          id: 'a-end',
          batterId: 'A',
          pitcherId: 'p',
          outcome: Outcome.IN_PLAY,
        ),
        // Batter B: one unknown pitch, then a checkpoint that uniquely
        // resolves B's own pitch alone.
        b.pitch(
          id: 'b-unknown',
          batterId: 'B',
          pitcherId: 'p',
          outcome: Outcome.UNKNOWN,
        ),
        b.countCorrection(id: 'cc', balls: 1, strikes: 0),
      ];

      final state = foldGameState(events);

      expect(
        state.inferredPitchEffects['a-unknown'],
        isNull,
        reason: "batter A's pitch belongs to a different, already-closed AB",
      );
      expect(
        state.inferredPitchEffects['b-unknown'],
        InferredCountEffect.ball,
      );
    },
  );

  test('InningHalfStart with a snapshot adopts cumulative state', () {
    final b = EventBuilder();
    final events = [
      b.lineupSet(
        id: 'lineup',
        teamId: 'home',
        battingOrder: ['h1', 'h2', 'h3'],
      ),
      b.inningHalfStart(
        id: 'half3',
        inning: 3,
        half: Half.BOTTOM,
        battingTeamId: 'home',
        snapshot: GameStateSnapshot(
          runsByTeam: const {'home': 4, 'away': 2},
          nextBatterIndexByTeam: const {'home': 2},
          pitchCountByPitcher: const {'p': 37},
        ),
      ),
    ];

    final state = foldGameState(events);

    expect(state.runsByTeam['home'], 4);
    expect(state.runsByTeam['away'], 2);
    expect(state.pitchCountByPitcher['p'], 37);
    // Per-half state still resets regardless of the snapshot.
    expect(state.outs, 0);
    expect(state.balls, 0);
    // nextBatterIndexByTeam came from the snapshot, not from LineupSet.
    expect(state.batterDue('home'), 'h3');
  });
}

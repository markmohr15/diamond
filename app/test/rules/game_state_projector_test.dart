import 'package:diamond/src/events/database/app_database.dart';
import 'package:diamond/src/events/event_store.dart';
import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/rules/game_state.dart';
import 'package:diamond/src/rules/game_state_fold.dart';
import 'package:diamond/src/rules/game_state_projector.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

/// Every event of a small two-half-inning game, in recording order. The
/// snapshot embedded in the second InningHalfStart reflects cumulative
/// state as of that point — this is what a real DIA-007 pitch loop would
/// have written when it appended that event.
List<GameEvent> _gameEvents(EventBuilder b) {
  List<GameEvent> strikeout(String batter, String pitcher, String outId) {
    return [
      for (var i = 1; i <= 3; i++)
        b.pitch(
          id: '$batter-s$i',
          batterId: batter,
          pitcherId: pitcher,
          outcome: Outcome.CALLED_STRIKE,
        ),
      b.runnerOut(id: outId, runnerId: batter, atBase: 1, how: How.STRIKEOUT),
    ];
  }

  return [
    b.lineupSet(
      id: 'lineup-away',
      teamId: 'away',
      battingOrder: ['a1', 'a2', 'a3'],
    ),
    b.inningHalfStart(
      id: 'h1-top',
      inning: 1,
      half: Half.TOP,
      battingTeamId: 'away',
    ),

    // a1: an unknown first pitch resolved by a checkpoint — from 0-0 only
    // a foul reaches 0-1, so back-inference marks it strike_effect. This
    // inferred effect must survive into the snapshot fast path below.
    b.pitch(
      id: 'a1-u',
      batterId: 'a1',
      pitcherId: 'p1',
      outcome: Outcome.UNKNOWN,
    ),
    b.countCorrection(id: 'a1-cc', balls: 0, strikes: 1),
    b.pitch(
      id: 'a1-s2',
      batterId: 'a1',
      pitcherId: 'p1',
      outcome: Outcome.CALLED_STRIKE,
    ),
    b.pitch(
      id: 'a1-s3',
      batterId: 'a1',
      pitcherId: 'p1',
      outcome: Outcome.CALLED_STRIKE,
    ),
    b.runnerOut(id: 'a1-out', runnerId: 'a1', atBase: 1, how: How.STRIKEOUT),

    ...strikeout('a2', 'p1', 'a2-out'),
    // a3's strikeout is the third out — the half ends automatically.
    ...strikeout('a3', 'p1', 'a3-out'),

    b.lineupSet(
      id: 'lineup-home',
      teamId: 'home',
      battingOrder: ['h1', 'h2', 'h3'],
    ),
    b.inningHalfStart(
      id: 'h1-bottom',
      inning: 1,
      half: Half.BOTTOM,
      battingTeamId: 'home',
      snapshot: GameStateSnapshot(
        runsByTeam: const {'away': 0},
        nextBatterIndexByTeam: const {'away': 3},
        pitchCountByPitcher: const {'p1': 9},
        inferredPitchEffects: const {
          'a1-u': InferredPitchEffect.STRIKE_EFFECT,
        },
      ),
    ),

    // h1: walks
    for (var i = 1; i <= 4; i++)
      b.pitch(
        id: 'h1-b$i',
        batterId: 'h1',
        pitcherId: 'p2',
        outcome: Outcome.BALL,
      ),
    b.runnerAdvance(
      id: 'h1-walk',
      runnerId: 'h1',
      from: 0,
      to: 1,
      reason: RunnerAdvanceReason.WALK,
    ),

    // h2: singles, h1 scores (simplified straight to a score for brevity)
    b.pitch(
      id: 'h2-inplay',
      batterId: 'h2',
      pitcherId: 'p2',
      outcome: Outcome.IN_PLAY,
    ),
    b.runnerAdvance(
      id: 'h1-scores',
      runnerId: 'h1',
      from: 1,
      to: 4,
      reason: RunnerAdvanceReason.BATTED_BALL,
    ),
    b.runnerAdvance(
      id: 'h2-on-first',
      runnerId: 'h2',
      from: 0,
      to: 1,
      reason: RunnerAdvanceReason.BATTED_BALL,
    ),

    ...strikeout('h3', 'p2', 'h3-out'),
  ];
}

void expectSameState(GameState a, GameState b) {
  expect(a.balls, b.balls, reason: 'balls');
  expect(a.strikes, b.strikes, reason: 'strikes');
  expect(a.outs, b.outs, reason: 'outs');
  expect(a.inning, b.inning, reason: 'inning');
  expect(a.half, b.half, reason: 'half');
  expect(a.battingTeamId, b.battingTeamId, reason: 'battingTeamId');
  expect(a.bases.sameAs(b.bases), isTrue, reason: 'bases');
  expect(a.halfEnded, b.halfEnded, reason: 'halfEnded');
  expect(a.halfEndReason, b.halfEndReason, reason: 'halfEndReason');
  expect(a.runsByTeam, b.runsByTeam, reason: 'runsByTeam');
  expect(
    a.nextBatterIndexByTeam,
    b.nextBatterIndexByTeam,
    reason: 'nextBatterIndexByTeam',
  );
  expect(
    a.pitchCountByPitcher,
    b.pitchCountByPitcher,
    reason: 'pitchCountByPitcher',
  );
  expect(
    a.inferredPitchEffects,
    b.inferredPitchEffects,
    reason: 'inferredPitchEffects',
  );
}

void main() {
  late EventStore store;

  setUp(() {
    store = EventStore(AppDatabase(NativeDatabase.memory()));
  });

  test(
    'property test: projecting via the snapshot fast path equals folding '
    'the whole stream from genesis',
    () async {
      final b = EventBuilder();
      for (final event in _gameEvents(b)) {
        await store.append(event);
      }

      final viaSnapshot = await GameStateProjector(store).project('game-1');
      final fromGenesis = foldGameState(await store.readStream('game-1'));

      expectSameState(viaSnapshot, fromGenesis);
      // Sanity-check the scenario actually reached the state we designed:
      // home scored 1, is 1 out into their half, away is retired.
      expect(fromGenesis.runsByTeam['home'], 1);
      expect(fromGenesis.outs, 1);
      expect(fromGenesis.battingTeamId, 'home');
    },
  );

  test(
    'a correction landing at-or-before the snapshot boundary invalidates '
    'it, and the projected result still matches a full replay',
    () async {
      final b = EventBuilder();
      for (final event in _gameEvents(b)) {
        await store.append(event);
      }

      // Long after the snapshot was cached, someone corrects a1's second
      // strike to a foul instead — a1's strikeout never actually
      // happened, so away's whole half reshapes: only 2 outs, not 3, and
      // the half never actually ended.
      await store.append(
        b.pitch(
          id: 'a1-s2-corrected',
          batterId: 'a1',
          pitcherId: 'p1',
          outcome: Outcome.FOUL,
          corrects: 'a1-s2',
        ),
      );

      final viaSnapshot = await GameStateProjector(store).project('game-1');
      final fromGenesis = foldGameState(await store.readStream('game-1'));

      expectSameState(viaSnapshot, fromGenesis);
    },
  );

  test(
    'a void landing at-or-before the snapshot boundary invalidates it too',
    () async {
      final b = EventBuilder();
      for (final event in _gameEvents(b)) {
        await store.append(event);
      }

      // Undo a2's putout — away never actually got that second out.
      await store.append(b.voidEvent(id: 'undo-a2-out', targetId: 'a2-out'));

      final viaSnapshot = await GameStateProjector(store).project('game-1');
      final fromGenesis = foldGameState(await store.readStream('game-1'));

      expectSameState(viaSnapshot, fromGenesis);
      expect(
        fromGenesis.outs,
        1,
        reason: 'only a1 and a3 are still out; a2 was un-called',
      );
    },
  );

  test(
    'a backdated insert anchored at-or-before the snapshot boundary '
    'invalidates it too',
    () async {
      final b = EventBuilder();
      for (final event in _gameEvents(b)) {
        await store.append(event);
      }

      // Long after the fact: a2 actually stole second between two of
      // their own pitches, in the half the snapshot already accounts for.
      await store.append(
        b.runnerAdvance(
          id: 'late-steal',
          runnerId: 'a2',
          from: 1,
          to: 2,
          reason: RunnerAdvanceReason.STOLEN_BASE,
          effectiveAfter: 'a2-s1',
        ),
      );

      final viaSnapshot = await GameStateProjector(store).project('game-1');
      final fromGenesis = foldGameState(await store.readStream('game-1'));

      expectSameState(viaSnapshot, fromGenesis);
    },
  );
}

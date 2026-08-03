import 'package:diamond/src/events/database/app_database.dart';
import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/game/game_controller.dart';
import 'package:diamond/src/game/game_session.dart';
import 'package:diamond/src/rules/game_state.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  /// A fresh container over the same database — "the app restarted."
  ProviderContainer restart() => ProviderContainer(
    overrides: [appDatabaseProvider.overrideWith((ref) => db)],
  );

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<GameState> ready(ProviderContainer c) =>
      c.read(gameControllerProvider.future);

  Map<String, dynamic> pitch(GameState gs, GameSession s, Outcome outcome) =>
      PitchThrown(
        batterId: gs.currentBatterId ?? gs.batterDue(gs.battingTeamId!)!,
        batterSide: BatterSide.R,
        pitcherId: s.pitcherId,
        outcome: outcome,
      ).toJson();

  test('first build seeds the M1 half-inning: their lineup, top 1, '
      'opp-1 due up', () async {
    final c = restart();
    addTearDown(c.dispose);
    final gs = await ready(c);

    expect(gs.inning, 1);
    expect(gs.half, Half.TOP);
    expect(gs.battingTeamId, 'opp');
    expect(gs.batterDue('opp'), 'opp-1');
    expect(gs.balls, 0);
    expect(gs.strikes, 0);
  });

  test('bootstrap is idempotent across restarts, and seq resumes rather '
      'than colliding', () async {
    final first = restart();
    final session = first.read(gameSessionProvider);
    var gs = await ready(first);
    await first
        .read(gameControllerProvider.notifier)
        .append(type: 'PitchThrown', payload: pitch(gs, session, Outcome.BALL));
    final rawBefore = await first
        .read(eventStoreProvider)
        .readRawStream(session.gameId);
    first.dispose();

    final second = restart();
    addTearDown(second.dispose);
    gs = await ready(second);
    // Restart did not re-seed: same stream, count folded from it.
    expect(gs.balls, 1);
    await second
        .read(gameControllerProvider.notifier)
        .append(type: 'PitchThrown', payload: pitch(gs, session, Outcome.BALL));

    final rawAfter = await second
        .read(eventStoreProvider)
        .readRawStream(session.gameId);
    expect(rawAfter.length, rawBefore.length + 1);

    // Every id unique, every seq strictly increasing in recording order —
    // the restart picked up where the first run left off.
    final ids = rawAfter.map((e) => e.id).toSet();
    expect(ids.length, rawAfter.length);
    for (var i = 1; i < rawAfter.length; i++) {
      expect(rawAfter[i].seq, greaterThan(rawAfter[i - 1].seq));
    }
  });

  test('append refolds: the exposed state is always fold(stream)', () async {
    final c = restart();
    addTearDown(c.dispose);
    final session = c.read(gameSessionProvider);
    var gs = await ready(c);

    final controller = c.read(gameControllerProvider.notifier);
    await controller.append(
      type: 'PitchThrown',
      payload: pitch(gs, session, Outcome.CALLED_STRIKE),
    );
    gs = c.read(gameControllerProvider).requireValue;
    expect(gs.strikes, 1);
    expect(gs.currentBatterId, 'opp-1');
    expect(gs.pitchCountByPitcher[session.pitcherId], 1);
  });

  group('top-level undo (§6)', () {
    test('voids the last loop-authored event; unlimited depth walks '
        'backward one event per call', () async {
      final c = restart();
      addTearDown(c.dispose);
      final session = c.read(gameSessionProvider);
      var gs = await ready(c);
      final controller = c.read(gameControllerProvider.notifier);

      await controller.append(
        type: 'PitchThrown',
        payload: pitch(gs, session, Outcome.BALL),
      );
      gs = c.read(gameControllerProvider).requireValue;
      await controller.append(
        type: 'PitchThrown',
        payload: pitch(gs, session, Outcome.CALLED_STRIKE),
      );
      expect(c.read(gameControllerProvider).requireValue.strikes, 1);

      await controller.undoLast(); // voids the strike
      gs = c.read(gameControllerProvider).requireValue;
      expect(gs.strikes, 0);
      expect(gs.balls, 1);

      await controller.undoLast(); // voids the ball
      gs = c.read(gameControllerProvider).requireValue;
      expect(gs.balls, 0);
    });

    test('never voids structural events: with no pitches left, undo is a '
        'no-op rather than unmaking the game', () async {
      final c = restart();
      addTearDown(c.dispose);
      final session = c.read(gameSessionProvider);
      await ready(c);
      final controller = c.read(gameControllerProvider.notifier);

      await controller.undoLast();
      final raw = await c
          .read(eventStoreProvider)
          .readRawStream(session.gameId);
      // Bootstrap only — no VoidEvent was appended.
      expect(raw.map((e) => e.type), ['LineupSet', 'InningHalfStart']);
      expect(
        c.read(gameControllerProvider).requireValue.battingTeamId,
        'opp',
      );
    });
  });
}

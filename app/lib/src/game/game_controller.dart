import 'package:diamond/src/events/event_store.dart';
import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/game/game_session.dart';
import 'package:diamond/src/rules/game_state.dart';
import 'package:diamond/src/rules/game_state_projector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Event types the top-level undo will void — the events the loop itself
/// emits. Structural events (LineupSet, InningHalfStart) are deliberately not
/// undoable from here: voiding one would not reverse a scorer's last action,
/// it would unmake the game.
const _undoableTypes = {
  'PitchThrown',
  'RunnerOut',
  'RunnerAdvance',
  'CountCorrection',
};

/// The UI's one writer and one reader of the event stream: append an event,
/// re-project [GameState] (§5's pure fold, snapshot-aware via
/// [GameStateProjector]).
///
/// Append-then-refold rather than a Drift watch query, on purpose: the store's
/// API stays append + read (its whole design), the fold is cheap at M1 stream
/// lengths, and every state this exposes is provably `fold(stream)` — there is
/// no second code path that could disagree with it.
class GameController extends AsyncNotifier<GameState> {
  late EventStore _store;
  late GameSession _session;
  late GameStateProjector _projector;

  /// Next envelope `seq` for this device — resumed from the raw stream on
  /// build, so a restart continues the sequence instead of colliding with it.
  late int _nextSeq;

  @override
  Future<GameState> build() async {
    _store = ref.watch(eventStoreProvider);
    _session = ref.watch(gameSessionProvider);
    _projector = GameStateProjector(_store);

    final raw = await _store.readRawStream(_session.gameId);
    _nextSeq = raw.isEmpty
        ? 0
        : raw.map((e) => e.seq).reduce((a, b) => a > b ? a : b) + 1;

    // First launch: seed the M1 half-inning — their lineup, top 1, us in the
    // field. DIA-009's scripted game replaces this with a real bootstrap.
    // Idempotent across restarts by construction: it only fires on an empty
    // stream.
    if (raw.isEmpty) {
      await _append(
        type: 'LineupSet',
        payload: LineupSet(
          teamId: _session.opponentTeamId,
          battingOrder: [for (var i = 1; i <= 9; i++) 'opp-$i'],
        ).toJson(),
      );
      await _append(
        type: 'InningHalfStart',
        payload: InningHalfStart(
          inning: 1,
          half: Half.TOP,
          battingTeamId: _session.opponentTeamId,
        ).toJson(),
      );
    }

    return _projector.project(_session.gameId);
  }

  /// Appends one event and refolds. The only write path the UI has.
  Future<void> append({
    required String type,
    required Map<String, dynamic> payload,
    String? corrects,
  }) async {
    await _append(type: type, payload: payload, corrects: corrects);
    state = AsyncData(await _projector.project(_session.gameId));
  }

  /// Top-level undo (§6): voids the most recent visible loop-authored event.
  /// Unlimited depth — each call voids one more event, and a pitch's
  /// consequence (a strikeout's RunnerOut) is voided before the pitch itself,
  /// in the reverse of the order they were recorded.
  Future<void> undoLast() async {
    final visible = await _store.readStream(_session.gameId);
    for (final event in visible.reversed) {
      if (!_undoableTypes.contains(event.type)) continue;
      await append(
        type: 'VoidEvent',
        payload: VoidEvent(targetId: event.id).toJson(),
      );
      return;
    }
    // Nothing undoable left — a no-op, not an error.
  }

  /// Raw append: envelope construction + store write, no refold. `build`
  /// uses this directly because assigning state mid-build is not allowed.
  Future<void> _append({
    required String type,
    required Map<String, dynamic> payload,
    String? corrects,
  }) async {
    final seq = _nextSeq++;
    await _store.append(
      GameEvent(
        // Unique per device: seq strictly increases and survives restarts.
        id: '${_session.deviceId}-$seq',
        gameId: _session.gameId,
        seq: seq,
        deviceId: _session.deviceId,
        createdBy: _session.createdBy,
        wallClock: DateTime.now().toUtc(),
        type: type,
        payload: payload,
        corrects: corrects,
      ),
    );
  }
}

final gameControllerProvider = AsyncNotifierProvider<GameController, GameState>(
  GameController.new,
);

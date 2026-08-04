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
  'FielderTouch',
  'CountCorrection',
};

/// Action roots (§11.3 v0.41): the events a scorer authors directly, one per
/// action. Everything the loop auto-appends after a root — a strikeout's
/// RunnerOut, a walk's forced chain, a D3K resolution — belongs to that
/// root's undo unit.
const _actionRootTypes = {'PitchThrown', 'CountCorrection'};

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
  ///
  /// Returns the appended event, envelope included — a correction (§6) needs
  /// the id of what it corrects, and "record last pitch" (§11.1 v0.39) needs
  /// the original payload to correct on top of.
  Future<GameEvent> append({
    required String type,
    required Map<String, dynamic> payload,
    String? corrects,
  }) async {
    final event = await _append(
      type: type,
      payload: payload,
      corrects: corrects,
    );
    state = AsyncData(await _projector.project(_session.gameId));
    return event;
  }

  /// Top-level undo (§6), **action-scoped** (§11.3 v0.41): one tap reverses
  /// the most recent scorer action — the last action-root event plus
  /// everything the loop auto-appended for it — so a bases-loaded walk
  /// reverses as one unit, not five taps. Unlimited depth: each call peels
  /// one more action.
  ///
  /// When the last action was itself a §6 correction ("record last pitch"),
  /// undo **counter-corrects** instead of voiding: it re-appends the
  /// superseded payload, collapsing the chain back to what it showed before
  /// the action. Voiding would hide the *whole* chain — original included
  /// (see `resolveVisibleLogicalOrder`) — undoing more than the action. Once
  /// a chain is back at its origin there is no further correction to unwind,
  /// so the next undo voids it, removing the underlying entry — which is by
  /// then the most recent action still standing.
  Future<void> undoLast() async {
    final visible = await _store.readStream(_session.gameId);
    final unit = <GameEvent>[];
    for (final event in visible.reversed) {
      if (!_undoableTypes.contains(event.type)) break;
      unit.add(event);
      if (_actionRootTypes.contains(event.type)) break;
    }
    // No complete action to undo (bootstrap only, or consequences with no
    // root — which the loop never writes): a no-op, not an error.
    if (unit.isEmpty || !_actionRootTypes.contains(unit.last.type)) return;

    final root = unit.last;
    if (root.corrects != null) {
      final raw = await _store.readRawStream(_session.gameId);
      final byId = {for (final e in raw) e.id: e};

      var origin = root;
      while (origin.corrects != null && byId.containsKey(origin.corrects)) {
        origin = byId[origin.corrects]!;
      }

      // A chain already showing its origin's payload has nothing left to
      // unwind — the standing action is the original entry, handled by the
      // void path below. Otherwise, one correction step comes off.
      if (!_deepEquals(root.payload, origin.payload)) {
        final predecessor = byId[root.corrects];
        if (predecessor != null) {
          await _append(
            type: root.type,
            payload: predecessor.payload,
            corrects: root.id,
          );
          state = AsyncData(await _projector.project(_session.gameId));
          return;
        }
      }
    }

    for (final event in unit) {
      await _append(
        type: 'VoidEvent',
        payload: VoidEvent(targetId: event.id).toJson(),
      );
    }
    state = AsyncData(await _projector.project(_session.gameId));
  }

  /// Structural equality for JSON-shaped payloads (maps, lists, scalars).
  bool _deepEquals(Object? a, Object? b) {
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final key in a.keys) {
        if (!b.containsKey(key) || !_deepEquals(a[key], b[key])) return false;
      }
      return true;
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_deepEquals(a[i], b[i])) return false;
      }
      return true;
    }
    return a == b;
  }

  /// Raw append: envelope construction + store write, no refold. `build`
  /// uses this directly because assigning state mid-build is not allowed.
  Future<GameEvent> _append({
    required String type,
    required Map<String, dynamic> payload,
    String? corrects,
  }) async {
    final seq = _nextSeq++;
    final event = GameEvent(
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
    );
    await _store.append(event);
    return event;
  }
}

final gameControllerProvider = AsyncNotifierProvider<GameController, GameState>(
  GameController.new,
);

import 'package:diamond/src/events/event_store.dart';
import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/rules/game_state.dart';
import 'package:diamond/src/rules/game_state_fold.dart';
import 'package:diamond/src/rules/logical_order.dart';

const _voidEventType = 'VoidEvent';
const _inningHalfStartType = 'InningHalfStart';

/// Projects [GameState] for a game, using an InningHalfStart's cached
/// GameStateSnapshot (§7) as a fast path when it's still safe to trust —
/// falling back to a full replay from genesis otherwise. Either path must
/// produce the exact same result; the snapshot is cache, never truth.
class GameStateProjector {
  GameStateProjector(this._eventStore);

  final EventStore _eventStore;

  Future<GameState> project(String gameId) async {
    final raw = await _eventStore.readRawStream(gameId);
    final visible = resolveVisibleLogicalOrder(raw);

    final boundary = _latestUsableSnapshotBoundary(raw, visible);
    if (boundary == null) {
      return foldGameState(visible);
    }

    final boundaryIndex = visible.indexWhere((e) => e.id == boundary.id);
    if (boundaryIndex == -1) {
      // Defensive: the boundary was visible when selected above; this
      // shouldn't happen. Fall back to a full replay rather than guess.
      return foldGameState(visible);
    }

    // LineupSet events land long before most snapshot boundaries, so the
    // fast path still needs them folded — reuse the ordinary fold's own
    // InningHalfStart handling (which adopts the embedded snapshot) by
    // folding lineups, then the boundary event itself, then the tail.
    final lineupsAndEarlier = visible
        .sublist(0, boundaryIndex + 1)
        .where((e) => e.type == 'LineupSet')
        .toList();
    final seeded = foldGameState([...lineupsAndEarlier, boundary]);

    final tail = visible.sublist(boundaryIndex + 1);
    return foldGameState(tail, startingFrom: seeded);
  }

  /// The most recent visible InningHalfStart carrying a snapshot that
  /// remains safe to trust, or null if none exists / none are safe.
  GameEvent? _latestUsableSnapshotBoundary(
    List<GameEvent> raw,
    List<GameEvent> visible,
  ) {
    for (final event in visible.reversed) {
      if (event.type != _inningHalfStartType) continue;
      final payload = InningHalfStart.fromJson(event.payload);
      if (payload.snapshot == null) continue;
      if (_isSafeBoundary(raw, event)) return event;
    }
    return null;
  }

  /// A snapshot at [boundary] is safe iff no event recorded after it
  /// corrects, voids, or effectiveAfter-anchors something at or before
  /// it — compared by the same `(wallClock, deviceId, seq)` ordering the
  /// envelope itself defines (§2), not by list position.
  bool _isSafeBoundary(List<GameEvent> raw, GameEvent boundary) {
    final byId = {for (final e in raw) e.id: e};

    bool isAtOrBeforeBoundary(String? targetId) {
      if (targetId == null) return false;
      final target = byId[targetId];
      if (target == null) return false; // dangling reference; ignore
      return _compareOrder(target, boundary) <= 0;
    }

    for (final event in raw) {
      if (_compareOrder(event, boundary) <= 0) continue;

      if (event.type == _voidEventType) {
        final targetId = VoidEvent.fromJson(event.payload).targetId;
        if (isAtOrBeforeBoundary(targetId)) return false;
      }
      if (isAtOrBeforeBoundary(event.corrects)) return false;
      if (isAtOrBeforeBoundary(event.effectiveAfter)) return false;
    }
    return true;
  }

  int _compareOrder(GameEvent a, GameEvent b) {
    final wallClock = a.wallClock.compareTo(b.wallClock);
    if (wallClock != 0) return wallClock;
    final deviceId = a.deviceId.compareTo(b.deviceId);
    if (deviceId != 0) return deviceId;
    return a.seq.compareTo(b.seq);
  }
}

import 'dart:convert';

import 'package:diamond/src/events/database/app_database.dart';
import 'package:diamond/src/events/generated/events.dart';
import 'package:drift/drift.dart';

/// Append-only event store (spec §2, §6). Wraps [AppDatabase]; exposes only
/// append + read — there is no update or delete, by design.
class EventStore {
  EventStore(this._db);

  static const _voidEventType = 'VoidEvent';

  final AppDatabase _db;

  Future<void> append(GameEvent event) {
    return _db.into(_db.events).insert(
      EventsCompanion.insert(
        id: event.id,
        gameId: event.gameId,
        seq: event.seq,
        deviceId: event.deviceId,
        createdBy: event.createdBy,
        wallClock: event.wallClock,
        type: event.type,
        payload: jsonEncode(event.payload),
        corrects: Value(event.corrects),
      ),
    );
  }

  /// Reads the resolved stream for [gameId]: ordered by
  /// `(wallClock, deviceId, seq)` (§2), with voided events hidden and
  /// correction chains (§6) collapsed to their latest version, surfaced at
  /// the position of the chain's original (earliest) event.
  Future<List<GameEvent>> readStream(String gameId) async {
    final query = _db.select(_db.events)
      ..where((tbl) => tbl.gameId.equals(gameId))
      ..orderBy([
        (tbl) => OrderingTerm.asc(tbl.wallClock),
        (tbl) => OrderingTerm.asc(tbl.deviceId),
        (tbl) => OrderingTerm.asc(tbl.seq),
      ]);
    final rows = await query.get();
    return _resolve(rows.map(_toGameEvent).toList());
  }

  GameEvent _toGameEvent(Event row) => GameEvent(
        id: row.id,
        gameId: row.gameId,
        seq: row.seq,
        deviceId: row.deviceId,
        createdBy: row.createdBy,
        wallClock: row.wallClock,
        type: row.type,
        payload: jsonDecode(row.payload) as Map<String, dynamic>,
        corrects: row.corrects,
      );

  List<GameEvent> _resolve(List<GameEvent> ordered) {
    final byId = {for (final e in ordered) e.id: e};

    // Chronological order means the last write for a given target is the
    // active correction — matches "projections use the latest version".
    final latestChildOf = <String, GameEvent>{};
    for (final e in ordered) {
      final target = e.corrects;
      if (target != null) {
        latestChildOf[target] = e;
      }
    }

    String headOf(String id) {
      var current = id;
      while (latestChildOf.containsKey(current)) {
        current = latestChildOf[current]!.id;
      }
      return current;
    }

    String rootOf(String id) {
      var current = id;
      var next = byId[current]?.corrects;
      while (next != null && byId.containsKey(next)) {
        current = next;
        next = byId[current]?.corrects;
      }
      return current;
    }

    final voidedRoots = <String>{};
    for (final e in ordered) {
      if (e.type == _voidEventType) {
        final target = VoidEvent.fromJson(e.payload).targetId;
        if (byId.containsKey(target)) {
          voidedRoots.add(rootOf(target));
        }
      }
    }

    final resolved = <GameEvent>[];
    for (final e in ordered) {
      if (e.type == _voidEventType) continue;
      if (e.corrects != null) continue; // only shown via its chain's root
      if (voidedRoots.contains(e.id)) continue;
      resolved.add(byId[headOf(e.id)]!);
    }
    return resolved;
  }
}

import 'dart:convert';

import 'package:diamond/src/events/database/app_database.dart';
import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/rules/logical_order.dart';
import 'package:drift/drift.dart';

/// Append-only event store (spec §2, §6). Wraps [AppDatabase]; exposes only
/// append + read — there is no update or delete, by design.
class EventStore {
  EventStore(this._db);

  final AppDatabase _db;

  /// Appends [events] in one database transaction — §15.5's atomic play
  /// commit. All-or-nothing at the storage layer: a crash mid-commit leaves
  /// the stream without the play, never with half of it.
  Future<void> appendAll(List<GameEvent> events) {
    return _db.transaction(() async {
      for (final event in events) {
        await append(event);
      }
    });
  }

  Future<void> append(GameEvent event) {
    return _db
        .into(_db.events)
        .insert(
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
            effectiveAfter: Value(event.effectiveAfter),
          ),
        );
  }

  /// Reads the visible, logically-ordered stream for [gameId] (§5, §6, §7):
  /// backdated inserts repositioned, voided events hidden, correction chains
  /// collapsed to their latest version. See [resolveVisibleLogicalOrder].
  Future<List<GameEvent>> readStream(String gameId) async {
    return resolveVisibleLogicalOrder(await readRawStream(gameId));
  }

  /// Reads every event for [gameId] — including voided and superseded ones
  /// — ordered purely by `(wallClock, deviceId, seq)` (§2). This is the raw
  /// log; projections that need to resolve `effectiveAfter` anchors against
  /// events that are no longer visible (voided or corrected) start here.
  Future<List<GameEvent>> readRawStream(String gameId) async {
    final query = _db.select(_db.events)
      ..where((tbl) => tbl.gameId.equals(gameId))
      ..orderBy([
        (tbl) => OrderingTerm.asc(tbl.wallClock),
        (tbl) => OrderingTerm.asc(tbl.deviceId),
        (tbl) => OrderingTerm.asc(tbl.seq),
      ]);
    final rows = await query.get();
    return rows.map(_toGameEvent).toList();
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
    effectiveAfter: row.effectiveAfter,
  );
}

import 'package:diamond/src/events/database/app_database.dart';
import 'package:diamond/src/events/event_store.dart';
import 'package:diamond/src/events/generated/events.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// The v3 → v4 upgrade (§6 v0.70): `events` gains a nullable `batch_id`.
/// A tablet already holding a game opens it after the update, so the old
/// rows have to survive and read back with no batch.
void main() {
  test('a v3 database gains batch_id and keeps its rows', () async {
    final db = AppDatabase(
      NativeDatabase.memory(
        setup: (raw) {
          raw
            ..execute('''
              CREATE TABLE events (
                id TEXT NOT NULL PRIMARY KEY,
                game_id TEXT NOT NULL,
                seq INTEGER NOT NULL,
                device_id TEXT NOT NULL,
                created_by TEXT NOT NULL,
                wall_clock INTEGER NOT NULL,
                type TEXT NOT NULL,
                payload TEXT NOT NULL,
                corrects TEXT NULL,
                effective_after TEXT NULL
              )''')
            ..execute(
              'CREATE TABLE play_journals (game_id TEXT NOT NULL PRIMARY KEY, '
              'draft TEXT NOT NULL)',
            )
            ..execute(
              'CREATE TABLE app_settings (key TEXT NOT NULL PRIMARY KEY, '
              'value TEXT NOT NULL)',
            )
            ..execute('''
              INSERT INTO events VALUES
                ('old-1', 'g', 1, 'd', 'u', 0, 'LineupSet', '{}', NULL, NULL)
            ''')
            ..execute('PRAGMA user_version = 3');
        },
      ),
    );
    addTearDown(db.close);
    final store = EventStore(db);

    final before = await store.readRawStream('g');
    expect(before.single.id, 'old-1');
    expect(before.single.batchId, isNull);

    await store.append(
      GameEvent(
        id: 'new-1',
        gameId: 'g',
        seq: 2,
        deviceId: 'd',
        createdBy: 'u',
        wallClock: DateTime.utc(2026, 11, 18),
        type: 'RunnerAdvance',
        payload: const {},
        batchId: 'new-1',
      ),
    );
    final after = await store.readRawStream('g');
    expect(after.map((e) => e.batchId), [null, 'new-1']);
  });
}

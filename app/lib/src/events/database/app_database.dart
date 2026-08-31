import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

/// Append-only store for `GameEvent` envelopes (spec §2). Mirrors the
/// envelope schema exactly; the event catalog itself lives in `payload`.
class Events extends Table {
  TextColumn get id => text()();
  TextColumn get gameId => text()();
  IntColumn get seq => integer()();
  TextColumn get deviceId => text()();
  TextColumn get createdBy => text()();
  DateTimeColumn get wallClock => dateTime()();
  TextColumn get type => text()();
  TextColumn get payload => text()();
  TextColumn get corrects => text().nullable()();
  TextColumn get effectiveAfter => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Crash journal for the one uncommitted play per game (spec §15.5): the
/// field-canvas draft, as JSON, restored on relaunch. Not an event and never
/// synced — the stream stays append-only; this is the scratch row that makes
/// atomic commit survivable. At most one row per game: a new draft replaces,
/// commit/discard deletes.
class PlayJournals extends Table {
  TextColumn get gameId => text()();
  TextColumn get draft => text()();

  @override
  Set<Column> get primaryKey => {gameId};
}

/// Device-local preferences: one row per key, value as text.
///
/// Deliberately **not** an event. A theme choice is a property of this tablet
/// in this dugout, not a fact about the game — syncing it would push one
/// scorer's night-game setting onto everyone else's device (§12).
class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(tables: [Events, PlayJournals, AppSettings])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(playJournals);
      }
      if (from < 3) {
        await m.createTable(appSettings);
      }
    },
  );

  static LazyDatabase _openConnection() {
    return LazyDatabase(() async {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, 'diamond.sqlite'));
      return NativeDatabase.createInBackground(file);
    });
  }
}

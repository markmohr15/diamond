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

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [Events])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 1;

  static LazyDatabase _openConnection() {
    return LazyDatabase(() async {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, 'diamond.sqlite'));
      return NativeDatabase.createInBackground(file);
    });
  }
}

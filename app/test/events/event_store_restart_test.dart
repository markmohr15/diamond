import 'dart:io';

import 'package:diamond/src/events/database/app_database.dart';
import 'package:diamond/src/events/event_store.dart';
import 'package:diamond/src/events/temp_types.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('the event store survives an app restart', () async {
    final dbFile = File(
      p.join(Directory.systemTemp.path, 'diamond_restart_test.sqlite'),
    );
    if (dbFile.existsSync()) {
      dbFile.deleteSync();
    }
    addTearDown(() {
      if (dbFile.existsSync()) {
        dbFile.deleteSync();
      }
    });

    final firstRun = AppDatabase(NativeDatabase(dbFile));
    await EventStore(firstRun).append(
      GameEvent(
        id: 'a',
        gameId: 'game-1',
        seq: 0,
        deviceId: 'device-1',
        createdBy: 'scorer-1',
        wallClock: DateTime.utc(2026, 4, 2),
        type: 'PitchThrown',
        payload: const {'zone': 'inside'},
      ),
    );
    await firstRun.close();

    // Reopen against the same file — simulates the process restarting.
    final secondRun = AppDatabase(NativeDatabase(dbFile));
    final stream = await EventStore(secondRun).readStream('game-1');
    await secondRun.close();

    expect(stream, hasLength(1));
    expect(stream.single.id, 'a');
    expect(stream.single.payload, {'zone': 'inside'});
  });
}

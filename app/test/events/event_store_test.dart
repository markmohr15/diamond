import 'package:diamond/src/events/database/app_database.dart';
import 'package:diamond/src/events/event_store.dart';
import 'package:diamond/src/events/generated/events.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

GameEvent _event({
  required String id,
  required DateTime wallClock,
  String gameId = 'game-1',
  int seq = 0,
  String deviceId = 'device-1',
  String type = 'PitchThrown',
  Map<String, dynamic> payload = const {},
  String? corrects,
}) {
  return GameEvent(
    id: id,
    gameId: gameId,
    seq: seq,
    deviceId: deviceId,
    createdBy: 'scorer-1',
    wallClock: wallClock,
    type: type,
    payload: payload,
    corrects: corrects,
  );
}

void main() {
  late EventStore store;

  setUp(() {
    store = EventStore(AppDatabase(NativeDatabase.memory()));
  });

  final t0 = DateTime.utc(2026, 4, 2);

  test('readStream orders by (wallClock, deviceId, seq)', () async {
    await store.append(
      _event(id: 'c', wallClock: t0.add(const Duration(seconds: 2))),
    );
    await store.append(
      _event(id: 'a', wallClock: t0.add(const Duration(seconds: 1))),
    );
    await store.append(
      _event(
        id: 'b-device-1',
        wallClock: t0.add(const Duration(seconds: 1)),
        deviceId: 'device-2',
      ),
    );

    final stream = await store.readStream('game-1');

    expect(stream.map((e) => e.id).toList(), ['a', 'b-device-1', 'c']);
  });

  test('readStream ignores events from other games', () async {
    await store.append(_event(id: 'a', wallClock: t0));
    await store.append(_event(id: 'x', gameId: 'game-2', wallClock: t0));

    final stream = await store.readStream('game-1');

    expect(stream.map((e) => e.id).toList(), ['a']);
  });

  test('a VoidEvent hides its target', () async {
    await store.append(_event(id: 'a', wallClock: t0));
    await store.append(
      _event(id: 'b', wallClock: t0.add(const Duration(seconds: 1))),
    );
    await store.append(
      _event(
        id: 'void-a',
        wallClock: t0.add(const Duration(seconds: 2)),
        type: 'VoidEvent',
        payload: VoidEvent(targetId: 'a').toJson(),
      ),
    );

    final stream = await store.readStream('game-1');

    expect(stream.map((e) => e.id).toList(), ['b']);
  });

  test('a correction chain returns only the latest version', () async {
    await store.append(
      _event(id: 'a', wallClock: t0, payload: const {'balls': 1}),
    );
    await store.append(
      _event(
        id: 'b',
        wallClock: t0.add(const Duration(seconds: 1)),
        payload: const {'balls': 2},
        corrects: 'a',
      ),
    );
    await store.append(
      _event(
        id: 'c',
        wallClock: t0.add(const Duration(seconds: 2)),
        payload: const {'balls': 3},
        corrects: 'b',
      ),
    );

    final stream = await store.readStream('game-1');

    expect(stream, hasLength(1));
    expect(stream.single.id, 'c');
    expect(stream.single.payload, {'balls': 3});
  });

  test(
    "a correction chain is surfaced at the original event's position",
    () async {
      await store.append(_event(id: 'first', wallClock: t0));
      await store.append(
        _event(id: 'a', wallClock: t0.add(const Duration(seconds: 1))),
      );
      await store.append(
        _event(id: 'last', wallClock: t0.add(const Duration(seconds: 3))),
      );
      await store.append(
        _event(
          id: 'b',
          wallClock: t0.add(const Duration(seconds: 2)),
          corrects: 'a',
        ),
      );

      final stream = await store.readStream('game-1');

      expect(stream.map((e) => e.id).toList(), ['first', 'b', 'last']);
    },
  );

  test(
    'voiding any event in a correction chain hides the whole chain',
    () async {
      await store.append(_event(id: 'a', wallClock: t0));
      await store.append(
        _event(
          id: 'b',
          wallClock: t0.add(const Duration(seconds: 1)),
          corrects: 'a',
        ),
      );
      await store.append(
        _event(
          id: 'void-b',
          wallClock: t0.add(const Duration(seconds: 2)),
          type: 'VoidEvent',
          payload: VoidEvent(targetId: 'b').toJson(),
        ),
      );

      final stream = await store.readStream('game-1');

      expect(stream, isEmpty);
    },
  );
}

import 'dart:convert';
import 'dart:io';

import 'package:diamond/src/events/generated/events.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

final _roundtripByType =
    <String, Map<String, dynamic> Function(Map<String, dynamic>)>{
      'PitchThrown': (json) => PitchThrown.fromJson(json).toJson(),
      'BallInPlay': (json) => BallInPlay.fromJson(json).toJson(),
      'FielderTouch': (json) => FielderTouch.fromJson(json).toJson(),
      'RunnerAdvance': (json) => RunnerAdvance.fromJson(json).toJson(),
      'RunnerOut': (json) => RunnerOut.fromJson(json).toJson(),
      'RuleCall': (json) => RuleCall.fromJson(json).toJson(),
      'VoidEvent': (json) => VoidEvent.fromJson(json).toJson(),
      'CountCorrection': (json) => CountCorrection.fromJson(json).toJson(),
    };

void main() {
  final fixturesDir = Directory(
    p.join(Directory.current.path, '..', 'fixtures', 'plays'),
  );

  test('fixtures/plays is reachable', () {
    expect(fixturesDir.existsSync(), isTrue, reason: fixturesDir.path);
  });

  final fixtureFiles =
      fixturesDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList(growable: false)
        ..sort((a, b) => a.path.compareTo(b.path));

  test('at least one fixture file was found', () {
    expect(fixtureFiles, isNotEmpty);
  });

  for (final file in fixtureFiles) {
    final fixture = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final events = (fixture['events'] as List).cast<Map<String, dynamic>>();

    for (final event in events) {
      final type = event['type'] as String;
      final payload = (event['payload'] as Map).cast<String, dynamic>();
      final label = '${p.basename(file.path)} ${event['id']} ($type)';

      test('$label round-trips exactly through the generated type', () {
        final roundtrip = _roundtripByType[type];
        expect(
          roundtrip,
          isNotNull,
          reason: 'no generated type registered for event type "$type"',
        );
        // Generated toJson() always emits every key, writing null for unset
        // optionals rather than omitting them — fixtures omit absent
        // optionals entirely (matching the schema, which never permits an
        // explicit null for these string/enum/object-typed fields). Absent
        // and explicit-null are the same value for our purposes, so strip
        // nulls before comparing; see tools/codegen/README.md.
        final withNullsStripped = Map<String, dynamic>.fromEntries(
          roundtrip!(payload).entries.where((e) => e.value != null),
        );
        expect(withNullsStripped, payload);
      });
    }
  }

  // BounceCoord (§3.3) is exercised by no §14 acceptance play (none of the
  // six involve a pitch in the dirt), so it gets direct round-trip coverage
  // here rather than a fixture with invented projection expectations.
  group('BounceCoord (§3.3) round-trips through the generated types', () {
    test('a bare BounceCoord survives fromJson->toJson, both depth signs', () {
      for (final json in const [
        {'x': 0.4, 'depth': 3.5}, // bounced out front, arm-side
        {'x': -0.2, 'depth': -1.4}, // skipped past the back edge
      ]) {
        expect(BounceCoord.fromJson(json).toJson(), json);
      }
    });

    test('depth is optional — "in the dirt, depth unknown" (§11.1)', () {
      // The hinge always yields x (the dirt-band release gives it) and may
      // yield no depth, if the coach skips the second placement. Absent depth
      // is a real recorded observation, distinct from a bounce at depth 0
      // (which means "on the plate's front edge").
      const json = {'x': 0.9};
      final coord = BounceCoord.fromJson(json);
      expect(coord.depth, isNull);
      expect(coord.x, 0.9);

      final withNullsStripped = Map<String, dynamic>.fromEntries(
        coord.toJson().entries.where((e) => e.value != null),
      );
      expect(withNullsStripped, json);
    });

    test('a PitchThrown carrying bounceLocation round-trips exactly', () {
      final payload = <String, dynamic>{
        'pitcherId': 'p1',
        'batterId': 'b1',
        'batterSide': 'R',
        'bounceLocation': {'x': -0.3, 'depth': 2.0},
        'outcome': 'ball',
      };
      final withNullsStripped = Map<String, dynamic>.fromEntries(
        PitchThrown.fromJson(
          payload,
        ).toJson().entries.where((e) => e.value != null),
      );
      expect(withNullsStripped, payload);
    });
  });
}

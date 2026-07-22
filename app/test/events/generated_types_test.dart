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

  final fixtureFiles = fixturesDir
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
}

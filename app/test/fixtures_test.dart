import 'dart:convert';
import 'dart:io';

import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/rules/game_state.dart';
import 'package:diamond/src/rules/game_state_fold.dart';
import 'package:diamond/src/rules/official_scoring.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs every §14 acceptance play in `fixtures/plays/` against the rules
/// engine (spec §14, CLAUDE.md non-negotiable: these pass at all times).
/// Single command: `flutter test test/fixtures_test.dart`.
///
/// Envelope wrapping per the fixtures README: payloads are wrapped
/// preserving the fixture's own event ids, in file order. Setup state is
/// constructed directly (not synthesized as prelude events) — the engine
/// is a pure fold, so the starting state is just a value.
void main() {
  final dir = Directory('../fixtures/plays');
  final files =
      dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  test('fixture directory is present and non-empty', () {
    expect(files, isNotEmpty, reason: 'no fixtures found at ${dir.path}');
  });

  for (final file in files) {
    final fixture = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final id = fixture['id'] as String;
    final title = fixture['title'] as String;

    test('$id: $title', () {
      _checkKnownKeys(id, fixture, const {
        'id',
        'title',
        'specRef',
        'setup',
        'events',
        'expect',
      });

      final events = _wrapEvents(fixture['events'] as List<dynamic>);
      final setup = _setupState(
        fixture['setup'] as Map<String, dynamic>,
        events,
      );

      final state = foldGameState(events, startingFrom: setup);
      final scoring = foldOfficialScoring(events, startingFrom: setup);

      _assertExpectations(
        id,
        fixture['expect'] as Map<String, dynamic>,
        state,
        scoring,
      );
    });
  }
}

const _battingTeam = 'batting';

List<GameEvent> _wrapEvents(List<dynamic> raw) {
  final base = DateTime.utc(2026, 4, 2);
  return [
    for (final (i, e) in raw.cast<Map<String, dynamic>>().indexed)
      GameEvent(
        id: e['id'] as String,
        gameId: 'fixture',
        seq: i,
        deviceId: 'fixture-device',
        createdBy: 'fixture-scorer',
        wallClock: base.add(Duration(seconds: i)),
        type: e['type'] as String,
        payload: e['payload'] as Map<String, dynamic>,
      ),
  ];
}

GameState _setupState(Map<String, dynamic> setup, List<GameEvent> events) {
  _checkKnownKeys('setup', setup, const {'outs', 'count', 'runners'});
  final count = setup['count'] as Map<String, dynamic>;
  final runners = (setup['runners'] as Map<String, dynamic>).map(
    (base, runnerId) => MapEntry(base, runnerId as String),
  );

  // The setup count belongs to an in-progress at-bat: seed the batter from
  // the first pitch so the fold's batter-change reset doesn't wipe it.
  String? batter;
  for (final event in events) {
    if (event.type == 'PitchThrown') {
      batter = PitchThrown.fromJson(event.payload).batterId;
      break;
    }
  }

  final balls = count['balls'] as int;
  final strikes = count['strikes'] as int;
  return GameState(
    balls: balls,
    strikes: strikes,
    spanStartBalls: balls,
    spanStartStrikes: strikes,
    outs: setup['outs'] as int,
    half: Half.TOP,
    battingTeamId: _battingTeam,
    bases: BaseState(
      first: runners['1'],
      second: runners['2'],
      third: runners['3'],
    ),
    currentBatterId: batter,
    runsByTeam: const {_battingTeam: 0},
  );
}

void _assertExpectations(
  String id,
  Map<String, dynamic> expects,
  GameState state,
  OfficialScoring scoring,
) {
  // 'note' and 'variant' are documentation; every other key must be one
  // the runner actually asserts, so new expectations can't silently no-op.
  _checkKnownKeys(id, expects, const {
    'outs',
    'runs',
    'count',
    'sameBatterStillUp',
    'officialErrors',
    'misplays',
    'batterResult',
    'runnerBases',
    'earnedRunFlags',
    'pitcherStrikeouts',
    'note',
    'variant',
  });

  for (final MapEntry(:key, :value) in expects.entries) {
    switch (key) {
      case 'note' || 'variant':
        break;
      case 'outs':
        expect(state.outs, value, reason: '$id: outs');
      case 'runs':
        expect(state.runsByTeam[_battingTeam], value, reason: '$id: runs');
      case 'count':
        final count = value as Map<String, dynamic>;
        expect(state.balls, count['balls'], reason: '$id: balls');
        expect(state.strikes, count['strikes'], reason: '$id: strikes');
      case 'sameBatterStillUp':
        final batter = scoring.batterOutcomes.lastOrNull?.batterId;
        expect(
          state.currentBatterId != null && state.currentBatterId == batter,
          value,
          reason: '$id: sameBatterStillUp',
        );
      case 'officialErrors':
        final expected = (value as List<dynamic>).cast<Map<String, dynamic>>();
        expect(
          scoring.errors.length,
          expected.length,
          reason:
              '$id: officialErrors count '
              '(got ${scoring.errors.map((e) => e.kind.wire).toList()})',
        );
        for (final (i, want) in expected.indexed) {
          final got = scoring.errors[i];
          _matchFragment(id, 'officialErrors[$i]', want, {
            'position': got.position,
            'kind': got.kind.wire,
            'basis': got.basis.wire,
          });
        }
      case 'misplays':
        final expected = (value as List<dynamic>).cast<Map<String, dynamic>>();
        expect(
          scoring.misplays.length,
          expected.length,
          reason: '$id: misplays count',
        );
        for (final (i, want) in expected.indexed) {
          final got = scoring.misplays[i];
          _matchFragment(id, 'misplays[$i]', want, {
            'position': got.position,
            'touchType': touchTypeValues.reverse[got.touchType],
          });
        }
      case 'batterResult':
        final want = value as Map<String, dynamic>;
        final outcome = scoring.outcomeFor(want['batterId'] as String);
        expect(outcome, isNotNull, reason: '$id: no outcome for batter');
        _matchFragment(id, 'batterResult', want, {
          'batterId': outcome!.batterId,
          'scoring': outcome.scoring,
          'hit': outcome.hit,
          'rbi': outcome.rbi,
        });
      case 'runnerBases':
        for (final MapEntry(key: runnerId, value: base)
            in (value as Map<String, dynamic>).entries) {
          final actual = switch (runnerId) {
            _ when state.bases.first == runnerId => 1,
            _ when state.bases.second == runnerId => 2,
            _ when state.bases.third == runnerId => 3,
            _ => null,
          };
          expect(actual, base, reason: '$id: base of runner $runnerId');
        }
      case 'earnedRunFlags':
        for (final MapEntry(key: runnerId, value: flag)
            in (value as Map<String, dynamic>).entries) {
          expect(
            scoring.unearnedConditions[runnerId],
            flag,
            reason: '$id: earnedRunFlags[$runnerId]',
          );
        }
      case 'pitcherStrikeouts':
        for (final MapEntry(key: pitcherId, value: delta)
            in (value as Map<String, dynamic>).entries) {
          final want = int.parse((delta as String).replaceFirst('+', ''));
          expect(
            scoring.strikeoutsByPitcher[pitcherId] ?? 0,
            want,
            reason: '$id: strikeouts for $pitcherId',
          );
        }
    }
  }
}

void _matchFragment(
  String id,
  String label,
  Map<String, dynamic> want,
  Map<String, dynamic> got,
) {
  for (final MapEntry(:key, :value) in want.entries) {
    expect(
      got.containsKey(key),
      isTrue,
      reason: '$id: $label asserts unknown field "$key"',
    );
    expect(got[key], value, reason: '$id: $label.$key');
  }
}

void _checkKnownKeys(
  String context,
  Map<String, dynamic> map,
  Set<String> known,
) {
  final unknown = map.keys.where((k) => !known.contains(k)).toList();
  expect(
    unknown,
    isEmpty,
    reason:
        '$context: unknown keys $unknown — teach the runner to assert '
        'them; unasserted expectations must fail loudly',
  );
}

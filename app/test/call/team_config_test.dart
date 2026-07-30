import 'package:diamond/src/call/team_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group("the stub layouts sit at both ends of §10.1's ladder", () {
    test(
      'coarse groups the ring into four chase zones; fine separates all 25',
      () {
        expect(StubTeamCallConfig.coarseLayout().zones, hasLength(13));
        expect(StubTeamCallConfig.fineLayout().zones, hasLength(25));
      },
    );

    test('both are valid partitions of the same canonical cells', () {
      // Construction validates; reaching here at all is the assertion. The
      // finer point is that two layouts of different sizes cover the same
      // frame, which is what makes them roll up to each other (§22).
      final coarseCells = StubTeamCallConfig.coarseLayout().zones
          .expand((zone) => zone.cells)
          .toSet();
      final fineCells = StubTeamCallConfig.fineLayout().zones
          .expand((zone) => zone.cells)
          .toSet();
      expect(coarseCells, fineCells);
      expect(coarseCells, hasLength(25));
    });

    test('coarse labels are batter-relative', () {
      final labels = StubTeamCallConfig.coarseLayout().zones
          .map((zone) => zone.label)
          .toList();
      expect(labels, contains('Low-In'));
      expect(labels, contains('Up-Away'));
      expect(labels, contains('Bury'));
    });
  });

  group('callable sets', () {
    test("default to every zone for every type — narrowing is the coach's "
        'act, never inferred', () {
      final config = TeamCallConfig(
        teamId: 'own',
        arsenal: StubTeamCallConfig.arsenal,
        layout: StubTeamCallConfig.coarseLayout(),
      );
      for (final type in config.arsenal) {
        expect(
          config.callableZones(type.id),
          hasLength(config.layout.zones.length),
          reason: '${type.id} should start all-callable',
        );
      }
    });

    test('a high drop and a low rise are callable — Diamond has no view about '
        'which locations suit which pitch (§10.1)', () {
      final config = TeamCallConfig(
        teamId: 'own',
        arsenal: StubTeamCallConfig.arsenal,
        layout: StubTeamCallConfig.coarseLayout(),
      );
      expect(config.isCallable('dr', 'chase-high'), isTrue);
      expect(config.isCallable('ri', 'chase-low'), isTrue);
    });

    test('the mocked card is sparse — each pitch has its own locations, which '
        'is what a real wristband looks like', () {
      final config = StubTeamCallConfig.config();
      for (final type in config.arsenal) {
        expect(
          config.callableZones(type.id).length,
          lessThan(config.layout.zones.length),
          reason: '${type.id} should not be callable everywhere',
        );
      }
      // Different pitches, different sets — not one subset applied to all.
      expect(
        config.callableZonesByType['dr'],
        isNot(config.callableZonesByType['ri']),
      );
    });

    test(
      'narrowing removes zones for one type without touching the others',
      () {
        final config = StubTeamCallConfig.narrowedConfig();

        expect(config.isCallable('ch', 'chase-high'), isFalse);
        expect(config.callableZones('ch'), hasLength(9));
        for (final zone in config.callableZones('ch')) {
          expect(zone.isChase, isFalse);
        }

        // Every other type is untouched.
        expect(config.callableZones('ff'), hasLength(13));
        expect(config.isCallable('ff', 'chase-high'), isTrue);
      },
    );

    test('rejects a type configured for a zone the layout does not define', () {
      expect(
        () => TeamCallConfig(
          teamId: 'own',
          arsenal: StubTeamCallConfig.arsenal,
          layout: StubTeamCallConfig.coarseLayout(),
          callableZonesByType: const {
            'ff': {'no-such-zone'},
          },
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects a type with no callable zones at all', () {
      expect(
        () => TeamCallConfig(
          teamId: 'own',
          arsenal: StubTeamCallConfig.arsenal,
          layout: StubTeamCallConfig.coarseLayout(),
          callableZonesByType: const {'ff': <String>{}},
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('asking about a type outside the arsenal is an error, not an empty '
        'list — a silent empty would read as "narrowed to nothing"', () {
      expect(
        () => StubTeamCallConfig.config().callableZones('knuckleball'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('call count is the sum over types, not the cross product', () {
    test('all-callable is the ceiling: 4 types x 13 zones', () {
      final all = TeamCallConfig(
        teamId: 'own',
        arsenal: StubTeamCallConfig.arsenal,
        layout: StubTeamCallConfig.coarseLayout(),
      );
      expect(all.callCount, 4 * 13);
    });

    test(
      'a sparse card sits well under it, which is what keeps it printable',
      () {
        final sparse = StubTeamCallConfig.config();
        expect(sparse.callCount, lessThan(4 * 13));
        // Summed per type, never the cross product.
        expect(
          sparse.callCount,
          sparse.arsenal.fold<int>(
            0,
            (sum, type) => sum + sparse.callableZones(type.id).length,
          ),
        );
      },
    );
  });
}

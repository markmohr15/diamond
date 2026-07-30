import 'dart:math';

import 'package:diamond/src/call/team_config.dart';
import 'package:diamond/src/call/wristband_card.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Seeded so the shuffle and every pick are reproducible: a card whose
  // contents changed run to run would make these assertions meaningless.
  Random seeded() => Random(20260729);

  group('card generation', () {
    test('carries k codes for every callable call, and nothing else', () {
      final config = StubTeamCallConfig.config();
      final card = WristbandCard.forConfig(config, random: seeded());

      expect(card.entries, hasLength(config.callCount * 4));
      for (final type in config.arsenal) {
        for (final zone in config.callableZones(type.id)) {
          final call = Call(pitchTypeId: type.id, zoneId: zone.id);
          expect(card.codesFor(call), hasLength(4), reason: '$call');
        }
      }
    });

    test('cannot express a call the coach narrowed away', () {
      final card = WristbandCard.forConfig(
        StubTeamCallConfig.narrowedConfig(),
        random: seeded(),
      );

      const narrowed = Call(pitchTypeId: 'ch', zoneId: 'chase-high');
      expect(card.canExpress(narrowed), isFalse);
      expect(card.codesFor(narrowed), isEmpty);

      // Same zone, a type that was not narrowed.
      expect(
        card.canExpress(const Call(pitchTypeId: 'ff', zoneId: 'chase-high')),
        isTrue,
      );
    });

    test('every code is unique — a code that meant two calls would be worse '
        'than useless at speed', () {
      final card = WristbandCard.forConfig(
        StubTeamCallConfig.config(),
        random: seeded(),
      );
      final codes = card.entries.map((entry) => entry.code).toList();
      expect(codes.toSet(), hasLength(codes.length));
    });

    test('codes read as grid coordinates: a row digit then a column label', () {
      final card = WristbandCard.forConfig(
        StubTeamCallConfig.config(),
        random: seeded(),
      );
      for (final entry in card.entries) {
        expect(entry.code, matches(RegExp(r'^[1-9]\d{2}$')));
      }
    });

    test('the codes use the whole row range — a card crammed into one row '
        'throws away the fast half of the lookup', () {
      final card = WristbandCard.forConfig(
        StubTeamCallConfig.config(),
        random: seeded(),
      );
      final rows = card.entries.map((e) => e.code[0]).toSet();

      // 20 calls x k=4 is 80 cells, which fills all nine rows.
      expect(rows, hasLength(9));
    });

    test('a pitch is spread across the card, not sitting in one row', () {
      final config = StubTeamCallConfig.config();
      final card = WristbandCard.forConfig(config, random: seeded());

      for (final type in config.arsenal) {
        final codes = [
          for (final zone in config.callableZones(type.id))
            ...card.codesFor(Call(pitchTypeId: type.id, zoneId: zone.id)),
        ];
        expect(codes, hasLength(20), reason: '${type.id}: 5 zones x k=4');
        expect(
          codes.map((c) => c[0]).toSet().length,
          greaterThan(1),
          reason: '${type.id} sits in a single row',
        );
      }
    });

    test('column labels are spread across the two-digit range, not a run '
        'starting at 10', () {
      final card = WristbandCard.forConfig(
        StubTeamCallConfig.config(),
        random: seeded(),
      );
      final labels =
          card.entries
              .map((e) => int.parse(e.code.substring(1)))
              .toSet()
              .toList()
            ..sort();

      for (final label in labels) {
        expect(label, inInclusiveRange(10, 99));
      }
      // Nine columns squeezed into 10..18 is the pattern this guards against.
      expect(labels.last - labels.first, greaterThan(labels.length));
    });

    test('k is honored — the card shrinks with it', () {
      final config = StubTeamCallConfig.config();
      final small = WristbandCard.forConfig(
        config,
        random: seeded(),
        codesPerCall: 2,
      );
      expect(small.entries, hasLength(config.callCount * 2));
    });
  });

  group('code selection', () {
    test('returns a code belonging to the call asked for', () {
      final card = WristbandCard.forConfig(
        StubTeamCallConfig.config(),
        random: seeded(),
      );
      final selector = CodeSelector(card: card, random: seeded());

      const call = Call(pitchTypeId: 'ri', zoneId: 'c2r4');
      expect(card.codesFor(call), contains(selector.next(call)));
    });

    test('never repeats the code just used for the same call (§10.2)', () {
      final card = WristbandCard.forConfig(
        StubTeamCallConfig.config(),
        random: seeded(),
      );
      final selector = CodeSelector(card: card, random: seeded());
      const call = Call(pitchTypeId: 'ff', zoneId: 'c2r2');

      var previous = selector.next(call);
      for (var i = 0; i < 200; i++) {
        final current = selector.next(call);
        expect(current, isNot(previous), reason: 'repeated on pitch $i');
        previous = current;
      }
    });

    test('re-roll changes the code without changing the call', () {
      final card = WristbandCard.forConfig(
        StubTeamCallConfig.config(),
        random: seeded(),
      );
      final selector = CodeSelector(card: card, random: seeded());
      const call = Call(pitchTypeId: 'dr', zoneId: 'c2r0');

      final first = selector.next(call);
      final rerolled = selector.reroll(call);

      expect(rerolled, isNot(first));
      expect(card.codesFor(call), contains(rerolled));
    });

    test('uses more than one code over time — rotation is the whole point', () {
      final card = WristbandCard.forConfig(
        StubTeamCallConfig.config(),
        random: seeded(),
      );
      final selector = CodeSelector(card: card, random: seeded());
      const call = Call(pitchTypeId: 'ff', zoneId: 'c2r2');

      final seen = {for (var i = 0; i < 50; i++) selector.next(call)};
      expect(seen, hasLength(4), reason: 'all k codes should come up');
    });

    test('two calls rotate independently', () {
      final card = WristbandCard.forConfig(
        StubTeamCallConfig.config(),
        random: seeded(),
      );
      final selector = CodeSelector(card: card, random: seeded());
      const a = Call(pitchTypeId: 'ff', zoneId: 'c2r2');
      const b = Call(pitchTypeId: 'ch', zoneId: 'c2r2');

      final firstA = selector.next(a);
      selector.next(b);
      // b's pick must not have consumed a's no-repeat memory.
      expect(selector.next(a), isNot(firstA));
    });

    test('returns null rather than inventing a code the card lacks', () {
      final card = WristbandCard.forConfig(
        StubTeamCallConfig.narrowedConfig(),
        random: seeded(),
      );
      final selector = CodeSelector(card: card, random: seeded());

      expect(
        selector.next(const Call(pitchTypeId: 'ch', zoneId: 'chase-high')),
        isNull,
      );
    });

    test(
      'with k = 1 it repeats rather than refusing to give the coach a code',
      () {
        final card = WristbandCard.forConfig(
          StubTeamCallConfig.config(),
          random: seeded(),
          codesPerCall: 1,
        );
        final selector = CodeSelector(card: card, random: seeded());
        const call = Call(pitchTypeId: 'ff', zoneId: 'c2r2');

        final only = card.codesFor(call).single;
        expect(selector.next(call), only);
        expect(selector.next(call), only);
      },
    );
  });
}

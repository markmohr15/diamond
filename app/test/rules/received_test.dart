import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/rules/official_scoring.dart';
import 'package:diamond/src/rules/received.dart';
import 'package:flutter_test/flutter_test.dart';

/// What a fielder was receiving is derived from the chain, never stored in
/// the touch type (DIA-025): "did she miss a fly or miss a throw?" has one
/// answer, and the error's kind reads it.
void main() {
  Received received(
    int position,
    List<(int, TouchType)> earlier, {
    bool anchorIsPitch = false,
  }) => receivedBy(
    position: position,
    anchorIsPitch: anchorIsPitch,
    earlier: [for (final (p, t) in earlier) (position: p, touchType: t)],
  );

  group('off the bat', () {
    test('the first fielder to play it is on the live ball', () {
      expect(received(9, []), Received.liveBall);
    });

    test('after a fielder who had it, the next one is taking her throw', () {
      expect(received(3, [(6, TouchType.FIELDED)]), Received.thrownBall);
      expect(received(6, [(8, TouchType.CAUGHT)]), Received.thrownBall);
      expect(received(2, [(4, TouchType.RECEIVED_THROW)]), Received.thrownBall);
    });

    test('a ball that got past the fielder before her is still live — the '
        'RF misplays it, and the CF is not taking a throw', () {
      expect(received(8, [(9, TouchType.BOOTED)]), Received.liveBall);
      expect(received(8, [(9, TouchType.MISSED_CATCH)]), Received.liveBall);
      expect(received(8, [(9, TouchType.DROPPED)]), Received.liveBall);
    });

    test('nobody receives a wild throw', () {
      expect(
        received(7, [(6, TouchType.FIELDED), (6, TouchType.WILD_THROW)]),
        Received.liveBall,
      );
    });

    test('a deflection is not a throw', () {
      expect(received(6, [(5, TouchType.DEFLECTED)]), Received.liveBall);
    });

    test('her own pickup after her own boot is not a throw to herself', () {
      expect(received(6, [(6, TouchType.BOOTED)]), Received.liveBall);
    });
  });

  group('between pitches', () {
    test('the catcher first on a pitch is taking the pitch', () {
      expect(received(2, [], anchorIsPitch: true), Received.pitch);
    });

    test('anyone else first is taking a throw — a pickoff has no recorded '
        'thrower', () {
      expect(received(3, [], anchorIsPitch: true), Received.thrownBall);
    });

    test('the pitcher covering on a ball the catcher missed is on a live '
        'ball', () {
      expect(
        received(1, [(2, TouchType.MISSED_CATCH)], anchorIsPitch: true),
        Received.liveBall,
      );
    });
  });

  group('the error it names', () {
    test('a missed or dropped batted ball is a fielding error', () {
      for (final type in [TouchType.DROPPED, TouchType.MISSED_CATCH]) {
        expect(
          officialErrorKindOf(type, received: Received.liveBall),
          OfficialErrorKind.fielding,
        );
      }
    });

    test('a missed or dropped throw is a catching error', () {
      for (final type in [TouchType.DROPPED, TouchType.MISSED_CATCH]) {
        expect(
          officialErrorKindOf(type, received: Received.thrownBall),
          OfficialErrorKind.catching,
        );
      }
    });

    test('the rest do not depend on it', () {
      for (final received in Received.values) {
        expect(
          officialErrorKindOf(TouchType.BOOTED, received: received),
          OfficialErrorKind.fielding,
        );
        expect(
          officialErrorKindOf(TouchType.WILD_THROW, received: received),
          OfficialErrorKind.throwing,
        );
      }
    });
  });
}

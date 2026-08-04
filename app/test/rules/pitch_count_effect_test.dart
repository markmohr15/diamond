import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/rules/pitch_count_effect.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ball-like outcomes advance balls only', () {
    for (final outcome in [
      Outcome.BALL,
      Outcome.BALL_INTENTIONAL,
      Outcome.ILLEGAL_PITCH,
    ]) {
      test('$outcome: 0-0 -> 1-0', () {
        final effect = applyPitchCountEffect(0, 0, outcome);
        expect(effect.balls, 1);
        expect(effect.strikes, 0);
        expect(effect.endsPlateAppearance, isFalse);
      });

      test('$outcome: 3-0 -> walk (ends AB)', () {
        final effect = applyPitchCountEffect(3, 0, outcome);
        expect(effect.balls, 4);
        expect(effect.endsPlateAppearance, isTrue);
      });
    }
  });

  group('strike-like outcomes always advance, even at 2 strikes', () {
    for (final outcome in [
      Outcome.CALLED_STRIKE,
      Outcome.SWINGING_STRIKE,
      Outcome.SWINGING_STRIKE_BLOCKED,
      // v0.41, bailout's word (§11.2): kind unknown, count effect certain —
      // at two strikes the scorer distinguishes FOUL from STRIKE by whether
      // the at-bat ended, so strike three here is real.
      Outcome.STRIKE_UNSPECIFIED,
      Outcome.FOUL_TIP,
      Outcome.FOUL_BUNT,
    ]) {
      test('$outcome: 0-0 -> 0-1', () {
        final effect = applyPitchCountEffect(0, 0, outcome);
        expect(effect.strikes, 1);
        expect(effect.strikesAdvanced, isTrue);
        expect(effect.endsPlateAppearance, isFalse);
      });

      test('$outcome: 0-2 -> strikeout (ends AB)', () {
        final effect = applyPitchCountEffect(0, 2, outcome);
        expect(effect.strikes, 3);
        expect(effect.endsPlateAppearance, isTrue);
      });
    }
  });

  group('plain foul: strike below 2, no-op at 2 (spec §4.1)', () {
    test('0-0 -> 0-1', () {
      final effect = applyPitchCountEffect(0, 0, Outcome.FOUL);
      expect(effect.strikes, 1);
      expect(effect.strikesAdvanced, isTrue);
      expect(effect.endsPlateAppearance, isFalse);
    });

    test('0-1 -> 0-2', () {
      final effect = applyPitchCountEffect(0, 1, Outcome.FOUL);
      expect(effect.strikes, 2);
      expect(effect.strikesAdvanced, isTrue);
    });

    test('0-2 -> 0-2, no-op, never a strikeout', () {
      final effect = applyPitchCountEffect(0, 2, Outcome.FOUL);
      expect(effect.strikes, 2);
      expect(effect.strikesAdvanced, isFalse);
      expect(effect.endsPlateAppearance, isFalse);
    });
  });

  group('AB-ending outcomes end the AB without touching the count', () {
    test('in_play ends the AB regardless of count', () {
      final effect = applyPitchCountEffect(1, 1, Outcome.IN_PLAY);
      expect(effect.balls, 1);
      expect(effect.strikes, 1);
      expect(effect.endsPlateAppearance, isTrue);
    });

    test('hit_by_pitch ends the AB regardless of count', () {
      final effect = applyPitchCountEffect(2, 2, Outcome.HIT_BY_PITCH);
      expect(effect.balls, 2);
      expect(effect.strikes, 2);
      expect(effect.endsPlateAppearance, isTrue);
    });
  });

  test('no_pitch is a total no-op', () {
    final effect = applyPitchCountEffect(1, 1, Outcome.NO_PITCH);
    expect(effect.balls, 1);
    expect(effect.strikes, 1);
    expect(effect.endsPlateAppearance, isFalse);
    expect(effect.strikesAdvanced, isFalse);
  });
}

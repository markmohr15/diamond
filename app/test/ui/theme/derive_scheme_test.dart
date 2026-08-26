import 'package:diamond/src/ui/theme/brand_baseline.dart';
import 'package:diamond/src/ui/theme/derive_scheme.dart';
import 'package:diamond/src/ui/theme/diamond_semantics.dart';
import 'package:diamond/src/ui/theme/team_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'scheme_tokens.dart';

void main() {
  // Two seeds far apart in hue, plus one that lands in §23.2's reserved band,
  // because "the baseline never moves" has to hold for the awkward case too.
  const blue = Color(0xFF0A84FF);
  const crimson = Color(0xFFB3122F);
  const teamOrange = Color(0xFFE07B00);

  for (final brightness in Brightness.values) {
    group('deriveScheme (${brightness.name})', () {
      test('is pure: identical seeds produce identical schemes', () {
        final first = deriveScheme(accentSeed: blue, brightness: brightness);
        final second = deriveScheme(accentSeed: blue, brightness: brightness);

        expect(schemeTokens(first), schemeTokens(second));
        expect(first.brightness, brightness);
      });

      test('the accent is the seed itself — the datum carries the team '
          'color, not a tonal approximation of it (§23.1.3)', () {
        expect(
          deriveScheme(accentSeed: crimson, brightness: brightness).primary,
          crimson,
        );
      });

      test('only accent tokens differ between two seeds; every brand-baseline '
          'token is byte-identical (§23.3)', () {
        final own = schemeTokens(
          deriveScheme(accentSeed: blue, brightness: brightness),
        );
        final opponent = schemeTokens(
          deriveScheme(accentSeed: crimson, brightness: brightness),
        );

        final differing = {
          for (final name in own.keys)
            if (own[name] != opponent[name]) name,
        };

        expect(differing, isNotEmpty, reason: 'the accent must actually move');
        expect(
          differing.difference(accentTokenNames),
          isEmpty,
          reason: 'a non-accent token changed with the seed',
        );
      });

      test('a seed inside the reserved amber/red band still leaves §23.2 '
          'intact — the reservations outrank team color', () {
        final baseline = BrandBaseline.of(brightness);
        final scheme = deriveScheme(
          accentSeed: teamOrange,
          brightness: brightness,
        );

        expect(scheme.error, baseline.error);
        expect(scheme.onError, baseline.onError);
        // Open Question #10 — the accent itself is still allowed to collide
        // with the reserved band today. When that is solved it is solved in
        // deriveScheme, and this expectation is what will change.
        expect(scheme.primary, teamOrange);
      });

      test('secondary and tertiary are held neutral: no second accent '
          '(§23.1.2)', () {
        final baseline = BrandBaseline.of(brightness);
        final scheme = deriveScheme(
          accentSeed: crimson,
          brightness: brightness,
        );

        expect(scheme.secondary, baseline.neutralHold);
        expect(scheme.tertiary, baseline.neutralHold);
      });

      test('surfaces and ink come from the baseline', () {
        final baseline = BrandBaseline.of(brightness);
        final scheme = deriveScheme(
          accentSeed: crimson,
          brightness: brightness,
        );

        expect(scheme.surface, baseline.surface);
        expect(scheme.surfaceBright, baseline.surfaceBright);
        expect(scheme.onSurface, baseline.ink);
        expect(scheme.outline, baseline.outline);
      });
    });
  }

  group('buildTheme', () {
    test('carries §23.2 semantics for both brightnesses', () {
      for (final brightness in Brightness.values) {
        final baseline = BrandBaseline.of(brightness);
        final theme = buildTheme(
          deriveScheme(accentSeed: blue, brightness: brightness),
        );
        final semantics = theme.extension<DiamondSemantics>()!;

        expect(semantics.uncertainty, baseline.uncertainty);
        expect(semantics.misplay, baseline.misplay);
      }
    });

    test('chrome is baseline in every context (§23.3)', () {
      final own = buildTheme(
        deriveScheme(accentSeed: blue, brightness: Brightness.light),
      );
      final opponent = buildTheme(
        deriveScheme(accentSeed: crimson, brightness: Brightness.light),
      );

      expect(own.appBarTheme.backgroundColor, BrandBaseline.light.chrome);
      expect(
        opponent.appBarTheme.backgroundColor,
        own.appBarTheme.backgroundColor,
      );
      expect(
        opponent.appBarTheme.foregroundColor,
        own.appBarTheme.foregroundColor,
      );
    });
  });

  group('parseHexColor', () {
    test('accepts #RRGGBB and #AARRGGBB, with or without the hash', () {
      expect(parseHexColor('#0A84FF'), const Color(0xFF0A84FF));
      expect(parseHexColor('0A84FF'), const Color(0xFF0A84FF));
      expect(parseHexColor('#800A84FF'), const Color(0x800A84FF));
    });

    test('throws rather than substituting a color nobody chose', () {
      expect(() => parseHexColor('#GGG'), throwsFormatException);
      expect(() => parseHexColor('#12345'), throwsFormatException);
      expect(() => parseHexColor('#ZZZZZZ'), throwsFormatException);
    });
  });
}

import 'package:diamond/src/ui/theme/brand_baseline.dart';
import 'package:diamond/src/ui/theme/brand_metrics.dart';
import 'package:diamond/src/ui/theme/derive_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ThemeData _theme(Brightness brightness) => buildTheme(
  deriveScheme(accentSeed: BrandBaseline.grass, brightness: brightness),
);

/// The three button kinds, which must agree about everything except fill.
Map<String, ButtonStyle> _buttonStyles(ThemeData t) => {
  'filled': t.filledButtonTheme.style!,
  'outlined': t.outlinedButtonTheme.style!,
  'text': t.textButtonTheme.style!,
};

void main() {
  group('the touch floor', () {
    test('every button kind is at least minTouchTarget in both themes', () {
      // §23.1.4: big touch targets, a dugout, no hover-dependent anything.
      // Material's own default minimumSize is smaller than ours, so an unset
      // theme is what would let a 32px control ship.
      for (final brightness in Brightness.values) {
        for (final entry in _buttonStyles(_theme(brightness)).entries) {
          final size = entry.value.minimumSize?.resolve({});
          expect(size, isNotNull, reason: '${entry.key} sets no minimum size');
          expect(
            size!.height,
            greaterThanOrEqualTo(BrandMetrics.minTouchTarget),
            reason: '${entry.key} in $brightness',
          );
          expect(size.width, greaterThanOrEqualTo(BrandMetrics.minTouchTarget));
        }
      }
    });

    test('a chip clears the floor through its padding', () {
      // A Chip sizes to its label, so it has no minimumSize to set — padding
      // is the only lever that reaches both axes. Label box plus both paddings
      // has to clear the floor on its own.
      final chip = _theme(Brightness.light).chipTheme;
      final padding = (chip.padding! as EdgeInsets).vertical;
      final labelHeight = chip.labelStyle!.fontSize!;
      expect(
        padding + labelHeight,
        greaterThanOrEqualTo(BrandMetrics.minTouchTarget),
      );
    });
  });

  group('the button vocabulary', () {
    test('the three kinds differ in fill, never in size or shape', () {
      // A filled button and an outlined one in the same row that disagree
      // about their height is exactly what §18.7 means by "serviceable".
      final styles = _buttonStyles(_theme(Brightness.light));
      final reference = styles['filled']!;
      for (final entry in styles.entries) {
        expect(
          entry.value.minimumSize?.resolve({}),
          reference.minimumSize?.resolve({}),
          reason: entry.key,
        );
        expect(
          entry.value.padding?.resolve({}),
          reference.padding?.resolve({}),
          reason: entry.key,
        );
        expect(
          entry.value.shape?.resolve({}),
          reference.shape?.resolve({}),
          reason: entry.key,
        );
      }
    });

    test('geometry does not vary with brightness', () {
      // Metrics are tier 1 (§23.3): a dark theme changes what things are made
      // of, never how big they are.
      final light = _buttonStyles(_theme(Brightness.light));
      final dark = _buttonStyles(_theme(Brightness.dark));
      for (final key in light.keys) {
        expect(
          dark[key]!.minimumSize?.resolve({}),
          light[key]!.minimumSize?.resolve({}),
          reason: key,
        );
        expect(
          dark[key]!.shape?.resolve({}),
          light[key]!.shape?.resolve({}),
          reason: key,
        );
      }
    });
  });

  group('the shadow set', () {
    /// What a shadow actually does to the surface under it.
    int luminanceDelta(Color shadow, Color under) {
      final a = shadow.a;
      int channel(double s, double u) => ((a * s + (1 - a) * u) * 255).round();
      final out =
          channel(shadow.r, under.r) +
          channel(shadow.g, under.g) +
          channel(shadow.b, under.b);
      final before = ((under.r + under.g + under.b) * 255).round();
      return out - before;
    }

    test('it darkens in light — a real shadow', () {
      final shadow = BrandMetrics.raised.single.color;
      expect(luminanceDelta(shadow, BrandBaseline.light.surface), lessThan(0));
    });

    test('it does nothing in dark, which is the intent not a bug', () {
      // The design reuses one shadow across both themes (§23.3 v0.48), and in
      // dark it composites to nothing — separation there comes from the
      // surface ladder instead. Pinned so that a future palette change which
      // silently turns this into a visible halo has to be a decision.
      final shadow = BrandMetrics.raised.single.color;
      final onCard = luminanceDelta(
        shadow,
        BrandBaseline.dark.surfaceContainerLow,
      );
      expect(onCard, 0, reason: 'a shadow the color of the card it falls on');

      final onGround = luminanceDelta(shadow, BrandBaseline.dark.surface);
      expect(
        onGround,
        greaterThanOrEqualTo(0),
        reason: 'never darker than the dark ground',
      );
    });

    test('the sheet shadow casts upward', () {
      // It lifts off the bottom edge, so the cast goes onto the page above it.
      expect(BrandMetrics.sheet.single.offset.dy, lessThan(0));
      expect(BrandMetrics.raised.single.offset.dy, greaterThan(0));
    });
  });

  group('surfaces', () {
    test('a dialog is never the same color as the page behind it', () {
      // The failure this guards is specific: Material's container ladder runs
      // in opposite directions in the two themes, so a slot that is a card in
      // light can be the ground in dark — which renders a dialog invisible
      // against the page.
      for (final brightness in Brightness.values) {
        final t = _theme(brightness);
        expect(
          t.dialogTheme.backgroundColor,
          isNot(t.colorScheme.surface),
          reason: '$brightness',
        );
      }
    });

    test('dialogs and cards take their radii from the token set', () {
      final t = _theme(Brightness.light);
      RoundedRectangleBorder shape(ShapeBorder? s) =>
          s! as RoundedRectangleBorder;
      expect(
        shape(t.dialogTheme.shape).borderRadius,
        BorderRadius.circular(BrandMetrics.radiusXl),
      );
      expect(
        shape(t.cardTheme.shape).borderRadius,
        BorderRadius.circular(BrandMetrics.radiusLg),
      );
      expect(
        shape(t.chipTheme.shape).borderRadius,
        BorderRadius.circular(BrandMetrics.radiusSm),
      );
    });
  });
}

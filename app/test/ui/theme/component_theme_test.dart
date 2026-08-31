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

  group('legibility', () {
    /// WCAG relative-luminance contrast — the measure the 4.5:1 threshold is
    /// actually defined against.
    double contrast(Color a, Color b) {
      final l1 = a.computeLuminance() + 0.05;
      final l2 = b.computeLuminance() + 0.05;
      return l1 > l2 ? l1 / l2 : l2 / l1;
    }

    test('a filled button is readable in both themes', () {
      // This failed at **1.73:1 in dark** until DIA-014a's golden rendered one
      // at size. `deriveScheme` sets `primary` to the seed itself rather than
      // a tonal approximation, so Material's `onPrimary` — derived *for* the
      // tonal one — assumed a light primary in dark and returned a dark green
      // on Grass. Every primary on the outcome sheet was illegible, in an
      // accent no team can change.
      for (final brightness in Brightness.values) {
        final scheme = deriveScheme(
          accentSeed: BrandBaseline.grass,
          brightness: brightness,
        );
        expect(
          contrast(scheme.primary, scheme.onPrimary),
          greaterThan(4.5),
          reason: '$brightness',
        );
      }
    });

    test('every theme slot handed a style directly carries a color', () {
      // The class of bug, not the instances. `BrandType`'s styles carry no
      // color on purpose so `ThemeData` can merge brightness-appropriate ink
      // into `textTheme` — but slots like `ChipThemeData.labelStyle` and
      // `ListTileThemeData.titleTextStyle` are read *directly* and never see
      // that merge, so a colorless style there renders in whatever
      // `DefaultTextStyle` is ambient. Both shipped that way and both were
      // found by looking at a screen: white-on-white chips in a dialog, then
      // an unreadable Remove action four lines below the fix.
      for (final brightness in Brightness.values) {
        final t = _theme(brightness);
        final slots = <String, TextStyle?>{
          'chipTheme.labelStyle': t.chipTheme.labelStyle,
          'chipTheme.secondaryLabelStyle': t.chipTheme.secondaryLabelStyle,
          'listTileTheme.titleTextStyle': t.listTileTheme.titleTextStyle,
        };
        for (final entry in slots.entries) {
          expect(
            entry.value?.color,
            isNotNull,
            reason: '${entry.key} in $brightness has no color',
          );
        }
      }
    });

    test('an outlined button label is readable in both themes', () {
      // The third thing to need this guardrail, and they share one cause:
      // `primary` is the seed itself rather than a tonal approximation, so
      // every Material default derived from it is suspect. A filled button's
      // `onPrimary` was 1.73:1; an outlined button draws its *label* in
      // `primary` directly, which was 2.20:1 on Grass in dark.
      for (final brightness in Brightness.values) {
        final theme = _theme(brightness);
        final base = BrandBaseline.of(brightness);
        final label = theme.outlinedButtonTheme.style!.foregroundColor!.resolve(
          {},
        )!;
        expect(
          contrast(label, base.surfaceContainerLow),
          greaterThan(4.5),
          reason: '$brightness',
        );
      }
    });

    test('it holds for a light accent too, not just Grass', () {
      // The guardrail picks the on-color by contrast rather than by theme,
      // because the accent belongs to a team (§23.3) and may be light or dark
      // in either. A yellow team is the case that breaks a brightness rule.
      const yellow = Color(0xFFF2D024);
      for (final brightness in Brightness.values) {
        final scheme = deriveScheme(accentSeed: yellow, brightness: brightness);
        expect(
          contrast(scheme.primary, scheme.onPrimary),
          greaterThan(4.5),
          reason: '$brightness',
        );
      }
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

    test('the role ladder holds its order in both themes', () {
      // Ground -> Card -> Raised is the one ordering that survives the theme
      // flip. Lightness does not: in light the page is tinted and a card is
      // bleached toward Chalk, in dark the page is the blackest thing and
      // everything stacks upward from it. Components ask for the role.
      double lum(Color c) => c.r + c.g + c.b;

      const light = BrandBaseline.light;
      expect(lum(light.card), greaterThan(lum(light.raised)));
      expect(lum(light.raised), greaterThan(lum(light.ground)));

      const dark = BrandBaseline.dark;
      expect(lum(dark.raised), greaterThan(lum(dark.card)));
      expect(lum(dark.card), greaterThan(lum(dark.ground)));
    });

    test('no role collides with another in either theme', () {
      // Two roles resolving to one value is a ladder with a missing rung: the
      // card would be invisible against whatever it sits on.
      for (final b in [BrandBaseline.light, BrandBaseline.dark]) {
        final roles = {b.ground, b.card, b.raised};
        expect(roles, hasLength(3), reason: '${b.brightness}');
      }
    });

    test('purity would not have worked, which is why roles exist', () {
      // Pinned as an explanation, not a preference. The purest surface — the
      // one nearest the theme's extreme — is the Card in light and the Ground
      // in dark, so a name based on purity would hand a component a card in
      // one theme and the page in the other.
      expect(
        BrandBaseline.light.card,
        BrandBaseline.light.surfaceBright,
        reason: 'in light the purest surface is the card',
      );
      expect(
        BrandBaseline.dark.ground,
        BrandBaseline.dark.surfaceContainerLowest,
        reason: 'in dark the purest surface is the page',
      );
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

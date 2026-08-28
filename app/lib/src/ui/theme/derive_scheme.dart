import 'package:diamond/src/ui/theme/brand_baseline.dart';
import 'package:diamond/src/ui/theme/brand_metrics.dart';
import 'package:diamond/src/ui/theme/brand_type.dart';
import 'package:diamond/src/ui/theme/diamond_semantics.dart';
import 'package:flutter/material.dart';

/// Color is data; the scheme is derived (§23.3). A pure function from one
/// accent seed plus the brand baseline to a full [ColorScheme] — no widget
/// tree, no navigation, no state, so it is testable on its own and cannot
/// silently disagree with its source the way a stored palette can.
///
/// What the accent owns is exactly Material's primary family; **everything
/// else comes from [BrandBaseline] and is byte-identical for every seed**.
/// That includes `secondary` and `tertiary`, which a seeded Material scheme
/// would fill with a second and third accent that §23.1.2 does not permit us to
/// have — they are pinned to neutral ink instead.
///
/// [ColorScheme.fromSeed] is used only for the *on* and *container* colors of
/// the accent family: that is Material's tonal derivation doing the legibility
/// work, which §23.3 makes the derivation's responsibility and never an
/// assumption about the seed.
ColorScheme deriveScheme({
  required Color accentSeed,
  required Brightness brightness,
  BrandBaseline? baseline,
}) {
  final base = baseline ?? BrandBaseline.of(brightness);
  final accent = _resolveAccent(accentSeed, base);
  final family = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: brightness,
  );

  return family.copyWith(
    // The accent goes to the datum (§23.1.3), and the datum should carry the
    // team's actual color rather than a tonal approximation of it — so
    // `primary` is the seed itself, not `family.primary`. The on/container
    // colors around it stay tonal.
    primary: accent,
    // **The contrast guardrail** (§23.3: "derivation guarantees legibility;
    // the seed does not"). `primary` is the seed itself rather than a tonal
    // approximation, so Material's `onPrimary` — derived for the tonal one —
    // can disagree with it badly. In dark it assumes a *light* primary and
    // returns a dark green, which on Grass measures **1.73:1**: a filled
    // button whose label is invisible, in both an accent no team can change.
    //
    // Chosen by contrast against the accent rather than by brightness, since
    // the accent is a team's color and may be light or dark in either theme.
    onPrimary: _onFill(accent),
    surfaceTint: accent,

    // Tier 1 from here down: never overridden, including under an opponent
    // accent (§23.3). Chrome staying Diamond's own is what keeps the product
    // identifiable at the moment the user is deepest in another team's data.
    // Including the `*Fixed` variants: they are the same second and third
    // accent under another name, and Material fills them from the seed too.
    secondary: base.neutralHold,
    onSecondary: base.onNeutralHold,
    secondaryContainer: base.surfaceContainerHigh,
    onSecondaryContainer: base.ink,
    secondaryFixed: base.surfaceContainerHigh,
    secondaryFixedDim: base.surfaceContainerHighest,
    onSecondaryFixed: base.ink,
    onSecondaryFixedVariant: base.inkVariant,
    tertiary: base.neutralHold,
    onTertiary: base.onNeutralHold,
    tertiaryContainer: base.surfaceContainerHigh,
    onTertiaryContainer: base.ink,
    tertiaryFixed: base.surfaceContainerHigh,
    tertiaryFixedDim: base.surfaceContainerHighest,
    onTertiaryFixed: base.ink,
    onTertiaryFixedVariant: base.inkVariant,

    error: base.error,
    onError: base.onError,
    errorContainer: base.errorContainer,
    onErrorContainer: base.onErrorContainer,

    surface: base.surface,
    onSurface: base.ink,
    onSurfaceVariant: base.inkVariant,
    surfaceDim: base.surfaceDim,
    surfaceBright: base.surfaceBright,
    surfaceContainerLowest: base.surfaceContainerLowest,
    surfaceContainerLow: base.surfaceContainerLow,
    surfaceContainer: base.surfaceContainer,
    surfaceContainerHigh: base.surfaceContainerHigh,
    surfaceContainerHighest: base.surfaceContainerHighest,
    outline: base.outline,
    outlineVariant: base.outlineVariant,
    inverseSurface: base.inverseSurface,
    onInverseSurface: base.onInverseSurface,
  );
}

/// The single home for the contrast guardrail (§23.3: "derivation guarantees
/// legibility; the seed does not") and for Open Question #10, the seed that
/// lands in §23.2's reserved amber/red band — a team whose color *is* orange.
///
/// Today it is the identity function. It exists as a named seam so that when
/// either is solved it is solved in one place rather than at call sites, and so
/// that nothing downstream is written assuming the rendered accent is the
/// stored seed.
Color _resolveAccent(Color seed, BrandBaseline baseline) => seed;

/// What to write on a fill of [fill]: the brand's near-white, or its dark
/// counterpart. **Neither varies with the theme, because the fill does not.**
///
/// Relative luminance per WCAG, which is the measure the 4.5:1 threshold is
/// defined against — not `Color.computeLuminance`'s cousin by another name,
/// but the same thing, so the comparison is against a real standard rather
/// than a guess about what looks right.
Color _onFill(Color fill) => fill.computeLuminance() > 0.4
    ? BrandBaseline.onLightFill
    : BrandBaseline.onBrandFill;

/// The scheme wrapped in a [ThemeData], with §23.2's reservations attached as a
/// [DiamondSemantics] extension. The only place a [ThemeData] is constructed.
ThemeData buildTheme(ColorScheme scheme) {
  final baseline = BrandBaseline.of(scheme.brightness);
  const theme = BrandType.textTheme;
  return ThemeData(
    colorScheme: scheme,
    // Tier 1, and brightness-independent: the same scale in both themes
    // (BrandType). Passed with null colors so Material's brightness-appropriate
    // defaults still supply ink and only face, size, weight and tracking come
    // from us.
    textTheme: BrandType.textTheme,
    // Tier 1: nav chrome is baseline, and stays baseline under an opponent
    // accent (§23.3).
    appBarTheme: AppBarTheme(
      backgroundColor: baseline.chrome,
      foregroundColor: baseline.onChrome,
    ),
    scaffoldBackgroundColor: scheme.surface,

    // The component vocabulary (§23.1.4, DIA-016d). Sized for a coach
    // standing in a dugout with the sun on the screen, and stated once here
    // rather than at each call site — which is how `field_dialog.dart` ended
    // up scaling its own chips, buttons and list tiles, and why every popup on
    // the field surface inherited from that one function by accident.
    //
    // `minimumSize` is the touch floor doing its work: Material's own default
    // is smaller than BrandMetrics.minTouchTarget, so leaving these unset is
    // what would let a 32px control ship.
    filledButtonTheme: FilledButtonThemeData(style: _buttonStyle(theme)),
    outlinedButtonTheme: OutlinedButtonThemeData(style: _buttonStyle(theme)),
    textButtonTheme: TextButtonThemeData(style: _buttonStyle(theme)),
    chipTheme: ChipThemeData(
      // **Colored explicitly, unlike every other slot here.** `BrandType`'s
      // styles deliberately carry no color so `ThemeData` can merge Material's
      // brightness-appropriate ink into them — but `ChipThemeData.labelStyle`
      // is read *directly* by the chip and never goes through that merge, so
      // handing it a colorless style strips the label's color and leaves it
      // inheriting whatever `DefaultTextStyle` happens to be. In a dialog that
      // rendered white-on-white.
      labelStyle: theme.titleMedium?.copyWith(color: scheme.onSurface),
      // The selected label sits on `secondaryContainer`, which is a different
      // surface and needs its own on-color for the same reason.
      secondaryLabelStyle: theme.titleMedium?.copyWith(
        color: scheme.onSecondaryContainer,
      ),
      // Vertical padding rather than a minimumSize: a Chip sizes to its label,
      // and padding is the only lever that reaches both axes.
      padding: const EdgeInsets.symmetric(
        horizontal: BrandMetrics.spaceLg,
        vertical: BrandMetrics.spaceLg,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(BrandMetrics.radiusSm)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(BrandMetrics.radiusXl)),
      ),
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(BrandMetrics.radiusLg)),
      ),
    ),
    listTileTheme: ListTileThemeData(
      titleTextStyle: theme.titleMedium,
      minVerticalPadding: BrandMetrics.spaceMd,
    ),
    extensions: [DiamondSemantics.fromBaseline(baseline)],
  );
}

/// One shape for all three button kinds. They differ in *fill* — which is
/// Material's job and the accent's — never in size, because a filled button
/// and an outlined one sitting in the same row that disagree about their
/// height is the kind of thing §18.7 calls serviceable.
ButtonStyle _buttonStyle(TextTheme text) => ButtonStyle(
  textStyle: WidgetStatePropertyAll(text.titleMedium),
  minimumSize: const WidgetStatePropertyAll(
    Size(BrandMetrics.minTouchTarget, BrandMetrics.minTouchTarget),
  ),
  padding: const WidgetStatePropertyAll(
    EdgeInsets.symmetric(
      horizontal: BrandMetrics.space3xl,
      vertical: BrandMetrics.spaceXl,
    ),
  ),
  shape: const WidgetStatePropertyAll(
    RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(BrandMetrics.radiusMd)),
    ),
  ),
);

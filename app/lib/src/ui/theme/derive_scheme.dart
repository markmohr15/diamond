import 'package:diamond/src/ui/theme/brand_baseline.dart';
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

/// The scheme wrapped in a [ThemeData], with §23.2's reservations attached as a
/// [DiamondSemantics] extension. The only place a [ThemeData] is constructed.
ThemeData buildTheme(ColorScheme scheme) {
  final baseline = BrandBaseline.of(scheme.brightness);
  return ThemeData(
    colorScheme: scheme,
    // Tier 1: nav chrome is baseline, and stays baseline under an opponent
    // accent (§23.3).
    appBarTheme: AppBarTheme(
      backgroundColor: baseline.chrome,
      foregroundColor: baseline.onChrome,
    ),
    scaffoldBackgroundColor: scheme.surface,
    extensions: [DiamondSemantics.fromBaseline(baseline)],
  );
}

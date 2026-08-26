import 'package:flutter/material.dart';

/// Tier 1 of §23.3: the brand baseline. Surfaces, chrome, ink, and the §23.2
/// semantic reservations — everything that is Diamond's own and **never** moves
/// when the accent does. Chrome staying Diamond's is what keeps the product
/// identifiable at exactly the moment the user is deepest in another team's
/// data (§23.3).
///
/// **Every color in this file is a placeholder and is expected to be thrown
/// away.** The real palette is blocked on the logo/brand work (DIA-012's
/// out-of-scope list). What is *not* provisional is the seam: this is the only
/// file in `app/lib/src/ui/` permitted to contain color literals, enforced by
/// `test/ui/theme/no_color_literals_test.dart`. Everything else reads color
/// from `Theme.of(context)`.
///
/// The specific light/dark surface values below are inherited from DIA-011's
/// canvas rather than invented here, so that migrating the pitch canvas onto
/// the theme is a pure refactor with byte-identical goldens.
@immutable
class BrandBaseline {
  const BrandBaseline({
    required this.brightness,
    required this.surface,
    required this.surfaceBright,
    required this.surfaceDim,
    required this.surfaceContainerLowest,
    required this.surfaceContainerLow,
    required this.surfaceContainer,
    required this.surfaceContainerHigh,
    required this.surfaceContainerHighest,
    required this.ink,
    required this.inkVariant,
    required this.outline,
    required this.outlineVariant,
    required this.chrome,
    required this.onChrome,
    required this.neutralHold,
    required this.onNeutralHold,
    required this.inverseSurface,
    required this.onInverseSurface,
    required this.uncertainty,
    required this.onUncertainty,
    required this.misplay,
    required this.error,
    required this.onError,
    required this.errorContainer,
    required this.onErrorContainer,
  });

  final Brightness brightness;

  /// The page: the canvas's atmosphere, a screen's background.
  final Color surface;

  /// The brightest surface in either mode — a lifted plane on dark, paper on
  /// light. The pitch canvas's zone fill is this.
  final Color surfaceBright;

  final Color surfaceDim;
  final Color surfaceContainerLowest;
  final Color surfaceContainerLow;
  final Color surfaceContainer;
  final Color surfaceContainerHigh;
  final Color surfaceContainerHighest;

  /// Primary text and structural line work. §23.1.3: structural lines on a
  /// light field are dark, not tinted — light blue on white vanishes in
  /// sunlight.
  final Color ink;

  final Color inkVariant;
  final Color outline;
  final Color outlineVariant;

  /// Nav chrome and app bar. Baseline, never the accent (§23.3).
  final Color chrome;
  final Color onChrome;

  /// Fills Material's `secondary`/`tertiary` slots, which exist to hold second
  /// and third accents that §23.1.2 does not allow us to have. Holding them
  /// neutral is the enforcement: a widget reaching for `colorScheme.secondary`
  /// gets quiet ink rather than a competing highlight.
  ///
  /// Not to be confused with a team's *secondary color*, which is chart-series
  /// data and never enters the scheme at all — see `TeamColors.secondaryHex`.
  final Color neutralHold;
  final Color onNeutralHold;

  final Color inverseSurface;
  final Color onInverseSurface;

  /// §23.2: uncertainty — the count is ambiguous (§12.5, §11.2). Reserved
  /// app-wide and unavailable to any accent.
  final Color uncertainty;
  final Color onUncertainty;

  /// §23.2: misplay — physical, fault not yet adjudicated (§13, §15.3). The
  /// same amber as [uncertainty] deliberately: both mean "this needs your
  /// judgement later," which is one idea. Kept as its own field because the two
  /// meanings are separate and either may need to diverge; call sites should
  /// name the one they mean.
  final Color misplay;


  /// §23.2: error state / invalid input.
  final Color error;
  final Color onError;
  final Color errorContainer;
  final Color onErrorContainer;

  /// 1A's two brand accents, named once so everything that needs them —
  /// including the categorical pitch-type scale — references rather than
  /// copies. These are **fills**: they keep their light-theme values in both
  /// themes, with Chalk sitting on top. Strokes, icons and text use the
  /// lifted values (§23.3, v0.47).
  static const Color grass = Color(0xFF2E5E3E);
  static const Color clay = Color(0xFFB4643C);

  /// The lifted values, for line work and text only — at their light values
  /// Grass and Clay disappear against Ink.
  static const Color grassLit = Color(0xFF5FA97A);
  static const Color clayLit = Color(0xFFD07E4E);

  static const BrandBaseline light = BrandBaseline(
    brightness: Brightness.light,
    surface: Color(0xFFE7E5DE),
    surfaceBright: Color(0xFFFFFEF9),
    surfaceDim: Color(0xFFDCD8CB),
    surfaceContainerLowest: Color(0xFFFFFEF9),
    surfaceContainerLow: Color(0xFFF4F2EB),
    surfaceContainer: Color(0xFFF4F2EB),
    surfaceContainerHigh: Color(0xFFE7E5DE),
    surfaceContainerHighest: Color(0xFFDCD8CB),
    ink: Color(0xFF16211C),
    inkVariant: Color(0xFF4A4A44),
    outline: Color(0xFF8A8A80),
    outlineVariant: Color(0xFFD6D3C8),
    chrome: Color(0xFF16211C),
    onChrome: Color(0xFFF4F2EB),
    neutralHold: Color(0xFF4A4A44),
    onNeutralHold: Color(0xFFFFFEF9),
    inverseSurface: Color(0xFF16211C),
    onInverseSurface: Color(0xFFF4F2EB),
    uncertainty: Color(0xFF5A47A0),
    onUncertainty: Color(0xFFFFFEF9),
    misplay: Color(0xFFE8A81C),
    error: Color(0xFFBB1E3C),
    onError: Color(0xFFFFFEF9),
    errorContainer: Color(0xFFFBEEF0),
    onErrorContainer: Color(0xFF16211C),
  );

  static const BrandBaseline dark = BrandBaseline(
    brightness: Brightness.dark,
    surface: Color(0xFF0E1613),
    surfaceBright: Color(0xFF26352E),
    surfaceDim: Color(0xFF0E1613),
    surfaceContainerLowest: Color(0xFF0E1613),
    surfaceContainerLow: Color(0xFF16211C),
    surfaceContainer: Color(0xFF16211C),
    surfaceContainerHigh: Color(0xFF1E2C25),
    surfaceContainerHighest: Color(0xFF26352E),
    ink: Color(0xFFF4F2EB),
    inkVariant: Color(0xFFA9C0AF),
    outline: Color(0xFF8FA396),
    outlineVariant: Color(0xFF2A3A32),
    chrome: Color(0xFF16211C),
    onChrome: Color(0xFFF4F2EB),
    neutralHold: Color(0xFF8FA396),
    onNeutralHold: Color(0xFF16211C),
    inverseSurface: Color(0xFFF4F2EB),
    onInverseSurface: Color(0xFF16211C),
    uncertainty: Color(0xFF9B85E8),
    onUncertainty: Color(0xFF16211C),
    misplay: Color(0xFFF2B935),
    error: Color(0xFFF4667B),
    onError: Color(0xFF16211C),
    errorContainer: Color(0xFF2B1418),
    onErrorContainer: Color(0xFFF4F2EB),
  );

  static BrandBaseline of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;
}

import 'package:flutter/material.dart';

/// Tier 1 of §23.3: the brand baseline. Surfaces, chrome, ink, and the §23.2
/// semantic reservations — everything that is Diamond's own and **never** moves
/// when the accent does. Chrome staying Diamond's is what keeps the product
/// identifiable at exactly the moment the user is deepest in another team's
/// data (§23.3).
///
/// **Every colour in this file is a placeholder and is expected to be thrown
/// away.** The real palette is blocked on the logo/brand work (DIA-012's
/// out-of-scope list). What is *not* provisional is the seam: this is the only
/// file in `app/lib/src/ui/` permitted to contain colour literals, enforced by
/// `test/ui/theme/no_color_literals_test.dart`. Everything else reads colour
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
    required this.uncertaintyAmber,
    required this.onUncertaintyAmber,
    required this.misplayAmber,
    required this.errorRed,
    required this.onErrorRed,
    required this.errorRedContainer,
    required this.onErrorRedContainer,
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
  /// Not to be confused with a team's *secondary colour*, which is chart-series
  /// data and never enters the scheme at all — see `TeamColors.secondaryHex`.
  final Color neutralHold;
  final Color onNeutralHold;

  final Color inverseSurface;
  final Color onInverseSurface;

  /// §23.2: uncertainty — the count is ambiguous (§12.5, §11.2). Reserved
  /// app-wide and unavailable to any accent.
  final Color uncertaintyAmber;
  final Color onUncertaintyAmber;

  /// §23.2: misplay — physical, fault not yet adjudicated (§13, §15.3). The
  /// same amber as [uncertaintyAmber] deliberately: both mean "this needs your
  /// judgement later," which is one idea. Kept as its own field because the two
  /// meanings are separate and either may need to diverge; call sites should
  /// name the one they mean.
  final Color misplayAmber;

  /// §23.2: error state / invalid input.
  final Color errorRed;
  final Color onErrorRed;
  final Color errorRedContainer;
  final Color onErrorRedContainer;

  static const BrandBaseline light = BrandBaseline(
    brightness: Brightness.light,
    surface: Color(0xFFF2F2F2),
    surfaceBright: Color(0xFFFFFFFF),
    surfaceDim: Color(0xFFDCDCE0),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFF7F7F8),
    surfaceContainer: Color(0xFFEDEDEF),
    surfaceContainerHigh: Color(0xFFE6E6E9),
    surfaceContainerHighest: Color(0xFFDFDFE3),
    ink: Color(0xFF1F1F22),
    inkVariant: Color(0xFF55555A),
    outline: Color(0xFF7A7A80),
    outlineVariant: Color(0xFFC7C7CC),
    chrome: Color(0xFF1F1F22),
    onChrome: Color(0xFFF2F2F2),
    neutralHold: Color(0xFF44444A),
    onNeutralHold: Color(0xFFFFFFFF),
    inverseSurface: Color(0xFF1F1F22),
    onInverseSurface: Color(0xFFF2F2F2),
    uncertaintyAmber: Color(0xFFB26A00),
    onUncertaintyAmber: Color(0xFFFFFFFF),
    misplayAmber: Color(0xFFB26A00),
    errorRed: Color(0xFFB3261E),
    onErrorRed: Color(0xFFFFFFFF),
    errorRedContainer: Color(0xFFF9DEDC),
    onErrorRedContainer: Color(0xFF410E0B),
  );

  static const BrandBaseline dark = BrandBaseline(
    brightness: Brightness.dark,
    surface: Color(0xFF1C1C1E),
    surfaceBright: Color(0xFF2C2C2E),
    surfaceDim: Color(0xFF121214),
    surfaceContainerLowest: Color(0xFF121214),
    surfaceContainerLow: Color(0xFF1F1F21),
    surfaceContainer: Color(0xFF232326),
    surfaceContainerHigh: Color(0xFF2C2C2E),
    surfaceContainerHighest: Color(0xFF37373A),
    ink: Color(0xFFE8E8EA),
    inkVariant: Color(0xFFB0B0B6),
    outline: Color(0xFF8A8A90),
    outlineVariant: Color(0xFF3A3A3E),
    chrome: Color(0xFF121214),
    onChrome: Color(0xFFE8E8EA),
    neutralHold: Color(0xFFC9C9CF),
    onNeutralHold: Color(0xFF1F1F22),
    inverseSurface: Color(0xFFE8E8EA),
    onInverseSurface: Color(0xFF1F1F22),
    uncertaintyAmber: Color(0xFFFFB74D),
    onUncertaintyAmber: Color(0xFF3A2400),
    misplayAmber: Color(0xFFFFB74D),
    errorRed: Color(0xFFF2B8B5),
    onErrorRed: Color(0xFF601410),
    errorRedContainer: Color(0xFF8C1D18),
    onErrorRedContainer: Color(0xFFF9DEDC),
  );

  static BrandBaseline of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;
}

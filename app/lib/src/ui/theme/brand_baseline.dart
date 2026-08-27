import 'package:flutter/material.dart';

/// Tier 1 of §23.3: the brand baseline. Surfaces, chrome, ink, and the §23.2
/// semantic reservations — everything that is Diamond's own and **never** moves
/// when the accent does. Chrome staying Diamond's is what keeps the product
/// identifiable at exactly the moment the user is deepest in another team's
/// data (§23.3).
///
/// The values are Claude Design's **1A "Infield"** (light) and **2A "Infield ·
/// dark"**, landed in DIA-016. They are no longer placeholders; DIA-012 built
/// the seam and said the colors filling it would be thrown away, and this is
/// what replaced them.
///
/// The seam is the durable part: this is the only file in `app/lib/src/ui/`
/// permitted to contain color literals, enforced by
/// `test/ui/theme/no_color_literals_test.dart`. Everything else reads color
/// from `Theme.of(context)`.
///
/// Dark is **not an inversion**. Ink is promoted from "the darkest color" to
/// *the card*, with the ground below it and one raised step above. The rule
/// that keeps this small: Grass and Clay hold their light values wherever they
/// are a **fill** with Chalk on top, and take the lifted values only as
/// strokes, icons and text, where the light values disappear against Ink.
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

  /// §23.2: misplay — physical, fault not yet adjudicated (§13, §15.3).
  ///
  /// **Rosin amber, and no longer the same value as [uncertainty]** (v0.47).
  /// The two were one color on the reasoning that both mean "this needs your
  /// judgment later." They do not ask the coach for the same thing: one says
  /// *I do not know what happened*, the other says *I know exactly what
  /// happened and someone muffed it*. Call sites name the one they mean.
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

  /// The shadow cast by a raised surface — Ink, at low alpha. **One value for
  /// both themes**, which is what the design panels do: 6A reuses 5A's shadow
  /// unchanged (§23.3, v0.48).
  ///
  /// It behaves differently in each theme, and that is the intent rather than
  /// an oversight. Over the light ground it darkens, as a shadow should. Over
  /// the dark ground it composites *lighter* than the surface, and over a dark
  /// card it lands on its own value and disappears entirely — so in dark the
  /// separation is carried by the surface ladder (ground → card → raised) and
  /// the shadow does nothing. Both facts are true at once: one shadow is
  /// defined, and no shadow reads in dark.
  static const Color shadow = Color(0xFF16211C);

  /// The upward shadow under a sheet lifting off the bottom edge. Black rather
  /// than Ink: a sheet occludes the whole page behind it, and the cast is a
  /// gap rather than a tint.
  static const Color sheetShadow = Color(0xFF000000);

  /// The design's own surface ladder: **Ground** is the page, **Card** sits on
  /// Ground, **Raised** sits on Card.
  ///
  /// These exist because that ordering is the only one that holds in both
  /// themes. Material's container ladder is consistent in *emphasis* but
  /// inverted in *lightness* — its own baseline schemes run
  /// `surfaceContainerLowest` from `#FFFFFF` in light to `#0F0D13` in dark —
  /// and 1A follows suit: in light the page is tinted and a card is bleached
  /// toward Chalk, while in dark the page is the blackest thing and everything
  /// stacks upward from it.
  ///
  /// The consequence is that **no single Material slot means "card" in both
  /// themes**, so a component picking one by hand gets a card in light and the
  /// page in dark — a dialog invisible against the page behind it. Naming by
  /// lightness or by "purity" would describe that honestly and still not fix
  /// it, because purity and role genuinely disagree: the purest surface is the
  /// Card in light and the Ground in dark. Role is the axis that does not
  /// move, so role is what components ask for.
  ///
  /// Material's slots are left exactly as they are — Flutter's own widgets
  /// read them, and they are correct on their own terms.
  Color get ground => surface;

  Color get card => brightness == Brightness.light
      ? surfaceContainerLowest
      : surfaceContainerLow;

  Color get raised => brightness == Brightness.light
      ? surfaceContainerLow
      : surfaceContainerHigh;

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

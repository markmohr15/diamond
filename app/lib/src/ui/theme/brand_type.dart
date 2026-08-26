import 'package:flutter/material.dart';

/// Tier 1 of §23.3 expressed in type: the two faces, the size scale, and the
/// rule deciding which face a given string takes.
///
/// Type is **tier 1 only**. It does not move with the accent (§23.3) and it
/// does not move with brightness — there is one scale, and both themes render
/// it. Light text on a dark ground reads optically bolder and some systems drop
/// a weight step to compensate; the design panels do not, so neither do we.
/// That is a decision to revisit on a full dark screen, not on a swatch.
///
/// **The scale is extracted from the panels, not invented.** 1A, 2A, 4A and 5A
/// already encode a consistent set of sizes, and reading it out is the whole
/// job — a second scale designed alongside the first would disagree with it
/// within a screen. The values were then rationalized to the smallest set that
/// covers what the panels do (30 folded into 32, the 12.5 note size into 13)
/// rather than one token per observed value.
///
/// **Line heights are the exception: they are chosen, not extracted.** The
/// panels' leading was not captured when the scale was read out, so these are
/// conventional values — tight for display, open for body. They are the one
/// thing here to re-measure against a real mock rather than trust.
abstract final class BrandType {
  /// Prose, at every size. Named rather than inlined because a family name is
  /// a string, and a typo in a string silently falls back to the system face
  /// instead of failing — `typography_test.dart` pins these against
  /// `pubspec.yaml`.
  static const String sans = 'Space Grotesk';

  /// Codes, never prose. See [DiamondCodeText.code] for the rule.
  static const String mono = 'JetBrains Mono';

  /// The scale. Colors are deliberately absent: `ThemeData` merges this over
  /// Material's brightness-appropriate defaults, so the defaults supply color
  /// while this supplies face, size, weight and tracking. Setting a color here
  /// would pin every string to one ink and defeat the color context (§23.3).
  ///
  /// Tracking is written as `size * ratio` because the panels specify it in em
  /// while Flutter's `letterSpacing` is logical pixels. Keeping the em value
  /// visible is what makes the two comparable.
  static const TextTheme textTheme = TextTheme(
    // Display — the wordmark and the count in the HUD. The tightest tracking
    // in the system (-0.045em) belongs to the wordmark alone; everything below
    // it settles at -0.02em.
    displayLarge: TextStyle(
      fontFamily: sans,
      fontSize: 44,
      fontWeight: FontWeight.w700,
      letterSpacing: 44 * -0.045,
      height: 1.05,
    ),
    // The outcome sheet's primaries: Ball, Called strike, Swinging, Foul, In
    // play (§11.1, DIA-014).
    displayMedium: TextStyle(
      fontFamily: sans,
      fontSize: 38,
      fontWeight: FontWeight.w700,
      letterSpacing: 38 * -0.02,
      height: 1.1,
    ),
    // Also carries the sheet's title, which the panels set at 30 — folded in
    // here rather than given a step of its own.
    displaySmall: TextStyle(
      fontFamily: sans,
      fontSize: 32,
      fontWeight: FontWeight.w700,
      letterSpacing: 32 * -0.02,
      height: 1.1,
    ),

    // Headline — section headings and the dugout sign.
    headlineLarge: TextStyle(
      fontFamily: sans,
      fontSize: 26,
      fontWeight: FontWeight.w700,
      letterSpacing: 26 * -0.02,
      height: 1.2,
    ),
    // Where the negative tracking stops. Below this the panels set type at
    // normal tracking, which is why these carry no `letterSpacing` at all
    // rather than a zero — an explicit zero would override Material's
    // per-slot defaults for no reason.
    headlineMedium: TextStyle(
      fontFamily: sans,
      fontSize: 21,
      fontWeight: FontWeight.w500,
      height: 1.25,
    ),
    headlineSmall: TextStyle(
      fontFamily: sans,
      fontSize: 19,
      fontWeight: FontWeight.w500,
      height: 1.3,
    ),

    // Title and body are the **same three sizes** — 17/15/13 — separated by
    // weight and leading rather than by scale. That is what the panels do, and
    // it is the reason the tier list is shorter than Material's slot list: a
    // title is a short string set in medium at tight leading, and the same
    // string set in regular at paragraph leading is body.
    titleLarge: TextStyle(
      fontFamily: sans,
      fontSize: 17,
      fontWeight: FontWeight.w500,
      height: 1.3,
    ),
    titleMedium: TextStyle(
      fontFamily: sans,
      fontSize: 15,
      fontWeight: FontWeight.w500,
      height: 1.3,
    ),
    titleSmall: TextStyle(
      fontFamily: sans,
      fontSize: 13,
      fontWeight: FontWeight.w500,
      height: 1.3,
    ),

    // Body — the only tier at w400.
    bodyLarge: TextStyle(
      fontFamily: sans,
      fontSize: 17,
      fontWeight: FontWeight.w400,
      height: 1.45,
    ),
    bodyMedium: TextStyle(
      fontFamily: sans,
      fontSize: 15,
      fontWeight: FontWeight.w400,
      height: 1.45,
    ),
    // Notes. The panels' prose floor.
    bodySmall: TextStyle(
      fontFamily: sans,
      fontSize: 13,
      fontWeight: FontWeight.w400,
      height: 1.4,
    ),

    // Label — button and chip text, which is prose and therefore sans. The
    // panels' letter-spaced uppercase tags are *not* these: they are
    // [eyebrow], a role rather than a size tier.
    labelLarge: TextStyle(
      fontFamily: sans,
      fontSize: 15,
      fontWeight: FontWeight.w500,
      height: 1.2,
    ),
    labelMedium: TextStyle(
      fontFamily: sans,
      fontSize: 13,
      fontWeight: FontWeight.w500,
      height: 1.2,
    ),
    // Below the panels' prose floor, and an extrapolation rather than an
    // extraction — Material requires the slot. Nothing should go smaller, and
    // call sites should reach for [TextTheme.labelMedium] first.
    labelSmall: TextStyle(
      fontFamily: sans,
      fontSize: 12,
      fontWeight: FontWeight.w500,
      height: 1.2,
    ),
  );

  /// Small uppercase letter-spaced labels — eyebrows, section tags, the chain
  /// strip's glyphs, "COUNT UNSURE".
  ///
  /// A role, not a size tier, which is why it sits outside [textTheme]: it is
  /// mono at one size with wide tracking wherever it appears, so mapping it
  /// onto a scale slot would imply a large and a small variant that the panels
  /// do not have. They run 8.5–14px at 0.08em–0.22em; this is the middle of
  /// that band.
  ///
  /// **Call sites uppercase the string themselves** — `TextStyle` has no case
  /// transform, and tracking this wide is wrong on lowercase.
  static const TextStyle eyebrow = TextStyle(
    fontFamily: mono,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    letterSpacing: 12 * 0.18,
    height: 1.2,
  );
}

/// The mono rule (§18.7): **mono for anything read as a code rather than as
/// prose.**
///
/// A code is a thing you look up, compare, or read digit by digit — the count,
/// a wristband code, a fielding position, a distance in feet, a jersey number,
/// a uniform ID. Prose is [BrandType.sans] at every size, *including prose
/// containing a number*: "2 outs" is a sentence and stays sans, while the `2`
/// standing alone in the HUD is a code and does not.
///
/// The distinction earns its keep on numbers that change in place. A count
/// ticking 1–1 → 2–1 in a proportional face reflows the whole field, and the
/// eye tracks the movement instead of the value; mono holds the digits still.
/// That is also why this applies to a scale slot rather than replacing one —
/// a code keeps the size and weight of the tier it sits in, so switching a
/// label to a code never resizes the row it lives on.
extension DiamondCodeText on TextStyle {
  TextStyle get code => copyWith(
    fontFamily: BrandType.mono,
    // The scale's negative tracking is a correction for a display face set
    // large and proportional; a monospaced face has its sidebearings built
    // into the advance width, and tightening it closes the gaps that make
    // digits countable.
    letterSpacing: 0,
  );
}

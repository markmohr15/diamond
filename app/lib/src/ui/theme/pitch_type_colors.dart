import 'package:diamond/src/ui/theme/brand_baseline.dart';
import 'package:flutter/material.dart';

/// §23's third colour tier: a **categorical scale**, which is neither brand
/// baseline nor team accent.
///
/// The baseline expresses identity and the accent expresses whose data you
/// are looking at (§23.3). These express *which of a fixed set* — and their
/// governing rule is different from both: the members must stay mutually
/// distinguishable at plot-marker size. They travel together or not at all,
/// which is why they live here rather than beside the brand.
///
/// Two of the four are brand colours doing double duty, and they **reference**
/// the baseline rather than copying its hexes, so a brand retune keeps the
/// chart in step. The thing to watch when Grass or Clay moves is that the
/// four-way separation survives it.
@immutable
class PitchTypeColors {
  const PitchTypeColors._();

  static const Color fastball = BrandBaseline.grass;
  static const Color slider = BrandBaseline.clay;
  static const Color curve = Color(0xFF6E8FA8);
  static const Color rise = Color(0xFFC9A277);

  /// Plot markers, the legend, and the pitch-mix table dots read this in
  /// order, so a caller never has to know the individual names.
  static const List<Color> series = [fastball, slider, curve, rise];
}

/// The dirt, in the "in the dirt" views (§3.3, §11.4).
///
/// [top] is the same value as [PitchTypeColors.rise] today and is
/// deliberately **not** that token: they are unrelated jobs that happen to
/// share a hex. Pointing the ground at the Rise series would mean a future
/// retune of one pitch type silently repaints the dirt.
@immutable
class DirtColors {
  const DirtColors._();

  static const Color top = Color(0xFFC9A277);
  static const Color bottom = Color(0xFFBE9265);
}

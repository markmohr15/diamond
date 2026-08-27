import 'package:diamond/src/ui/theme/brand_baseline.dart';
import 'package:flutter/material.dart';

/// Tier 1 of §23.3 in geometry: the spacing rhythm, the corner radii, the
/// touch floor, and the one shadow set.
///
/// Like the type scale, these are **read out of the design panels rather than
/// invented**, then rationalized to the smallest set that covers them. The
/// panels' gaps run 6/8/10/12/14/18/20/24/28 and their radii 8/12/14/16/20/28/
/// 32 — more values than there are distinct intentions. The odd steps are
/// optical adjustments at one call site, not rungs of a ladder, so they fold
/// to the nearest 4px step here.
///
/// None of this varies by theme or by accent. What is deliberately **not**
/// here: the component heights the panels use for the outcome sheet
/// (34/60/74/118/132). Those belong to the surface that has them, and DIA-014
/// has not built it — naming a height for a component nobody has written is
/// inventing a vocabulary with no consumer.
///
/// Canvas geometry is also not here and never will be. The pitch and field
/// canvases compute their layout from §3.1 and §11.4; §23's preamble is
/// explicit that a design pass does not get to relitigate a derived value.
abstract final class BrandMetrics {
  /// The spacing scale — a 4px grid.
  ///
  /// Gaps between related controls start at [spaceSm]; [spaceXs] is for the
  /// space inside a control, between an icon and its label.
  static const double spaceXs = 4;
  static const double spaceSm = 8;
  static const double spaceMd = 12;
  static const double spaceLg = 16;
  static const double spaceXl = 20;
  static const double space2xl = 24;

  /// Panel and dialog padding. The panels settle here more than anywhere
  /// else, which is why it is the largest named step rather than one of a
  /// run — 28 is "the inside of a surface", not "a big gap".
  static const double space3xl = 28;

  /// The outer margin on a full page. Not part of the ladder: it is the one
  /// value that scales with the screen rather than with the content.
  static const double pageMargin = 56;

  /// Chips and tooltips — small things whose corner should read as a detail.
  static const double radiusSm = 8;

  /// Buttons and other controls.
  static const double radiusMd = 12;

  /// Cards and raised panels.
  static const double radiusLg = 16;

  /// Dialogs and sheets. The largest radius, because the biggest surfaces are
  /// the ones whose corners are actually visible as a shape.
  static const double radiusXl = 28;

  /// **Nothing interactive is smaller than this** (§23.1.4: big touch
  /// targets, a dugout, no hover-dependent anything). The panels bear it out
  /// — their smallest interactive element is a 40px position chip, and the
  /// 34px label pill is not interactive.
  ///
  /// Enforced once, in the component themes, rather than remembered at 38 call
  /// sites.
  static const double minTouchTarget = 40;

  /// A raised surface: card, dialog, menu.
  ///
  /// **CSS blur-radius and Flutter's `blurRadius` are not the same unit**, and
  /// copying the panels' number across would over-blur by about 15%. CSS
  /// defines the blur as a gaussian of standard deviation `blur / 2`; Flutter
  /// converts with `radius * 0.57735`. Equating the two gives
  /// `flutter ≈ css * 0.866`, so the panels' `0 24px 60px` becomes 52 here and
  /// the sheet's 44 becomes 38.
  ///
  /// Reads as a shadow in light and as nothing in dark — see
  /// [BrandBaseline.shadow], where that is explained and intended.
  static List<BoxShadow> get raised => [
    BoxShadow(
      color: BrandBaseline.shadow.withValues(alpha: 0.28),
      offset: const Offset(0, 24),
      blurRadius: 52,
    ),
  ];

  /// A sheet lifting off the bottom edge — the shadow casts *upward*, onto the
  /// page it is covering.
  static List<BoxShadow> get sheet => [
    BoxShadow(
      color: BrandBaseline.sheetShadow.withValues(alpha: 0.3),
      offset: const Offset(0, -18),
      blurRadius: 38,
    ),
  ];
}

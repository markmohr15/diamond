import 'package:diamond/src/ui/theme/brand_baseline.dart';
import 'package:flutter/material.dart';

/// §23.2's reserved colors, carried on the theme so widgets read them the same
/// way they read every other color — `Theme.of(context)` — rather than
/// importing [BrandBaseline] directly. Material's [ColorScheme] has a slot for
/// `error` and none for "uncertainty" or "misplay", so they live here.
///
/// These are load-bearing meaning, not decoration: nothing in tiers 2–3 may
/// touch them, and no accent may be assigned a value in their band (§23.2
/// outranks team color; the collision case is Open Question #10).
///
/// §23.1.7 still applies at every call site: neither state may be signalled by
/// color alone. The non-color cue is the widget's job — this extension only
/// guarantees the color half is consistent app-wide.
@immutable
class DiamondSemantics extends ThemeExtension<DiamondSemantics> {
  const DiamondSemantics({
    required this.uncertainty,
    required this.onUncertainty,
    required this.misplay,
    required this.callable,
  });

  /// Built from the baseline, so a semantic color can never drift from the
  /// brand tier it belongs to.
  factory DiamondSemantics.fromBaseline(BrandBaseline baseline) =>
      DiamondSemantics(
        uncertainty: baseline.uncertaintyAmber,
        onUncertainty: baseline.onUncertaintyAmber,
        misplay: baseline.misplayAmber,
        callable: baseline.callableGreen,
      );

  /// Amber: the count is ambiguous (§12.5, §11.2).
  final Color uncertainty;

  final Color onUncertainty;

  /// Amber: a misplay — physical, fault not yet adjudicated (§13, §15.3).
  final Color misplay;

  /// Green: this zone can be called for the pitch in hand (§10.1). A property
  /// of the control, not of the datum — the accent still marks the one zone
  /// already chosen.
  final Color callable;

  /// The error color is [ColorScheme.error]; it is not duplicated here.
  static DiamondSemantics of(BuildContext context) =>
      Theme.of(context).extension<DiamondSemantics>()!;

  @override
  DiamondSemantics copyWith({
    Color? uncertainty,
    Color? onUncertainty,
    Color? misplay,
    Color? callable,
  }) => DiamondSemantics(
    uncertainty: uncertainty ?? this.uncertainty,
    onUncertainty: onUncertainty ?? this.onUncertainty,
    misplay: misplay ?? this.misplay,
    callable: callable ?? this.callable,
  );

  @override
  DiamondSemantics lerp(ThemeExtension<DiamondSemantics>? other, double t) {
    if (other is! DiamondSemantics) return this;
    return DiamondSemantics(
      uncertainty: Color.lerp(uncertainty, other.uncertainty, t)!,
      onUncertainty: Color.lerp(onUncertainty, other.onUncertainty, t)!,
      misplay: Color.lerp(misplay, other.misplay, t)!,
      callable: Color.lerp(callable, other.callable, t)!,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DiamondSemantics &&
      other.uncertainty == uncertainty &&
      other.onUncertainty == onUncertainty &&
      other.misplay == misplay &&
      other.callable == callable;

  @override
  int get hashCode =>
      Object.hash(uncertainty, onUncertainty, misplay, callable);
}

import 'package:flutter/material.dart';

/// Every color token on a [ColorScheme], by name.
///
/// Test-only: production code reads named getters, never the whole set. The
/// tests need the set so that "only accent tokens differ between contexts" can
/// be asserted exhaustively rather than over a handful of fields somebody
/// remembered to list — a new Material token appearing here is exactly the kind
/// of thing that would otherwise leak a seed color into the brand tier
/// unnoticed.
Map<String, Color> schemeTokens(ColorScheme s) => {
  'primary': s.primary,
  'onPrimary': s.onPrimary,
  'primaryContainer': s.primaryContainer,
  'onPrimaryContainer': s.onPrimaryContainer,
  'primaryFixed': s.primaryFixed,
  'primaryFixedDim': s.primaryFixedDim,
  'onPrimaryFixed': s.onPrimaryFixed,
  'onPrimaryFixedVariant': s.onPrimaryFixedVariant,
  'inversePrimary': s.inversePrimary,
  'surfaceTint': s.surfaceTint,
  'secondary': s.secondary,
  'onSecondary': s.onSecondary,
  'secondaryContainer': s.secondaryContainer,
  'onSecondaryContainer': s.onSecondaryContainer,
  'secondaryFixed': s.secondaryFixed,
  'secondaryFixedDim': s.secondaryFixedDim,
  'onSecondaryFixed': s.onSecondaryFixed,
  'onSecondaryFixedVariant': s.onSecondaryFixedVariant,
  'tertiary': s.tertiary,
  'onTertiary': s.onTertiary,
  'tertiaryContainer': s.tertiaryContainer,
  'onTertiaryContainer': s.onTertiaryContainer,
  'tertiaryFixed': s.tertiaryFixed,
  'tertiaryFixedDim': s.tertiaryFixedDim,
  'onTertiaryFixed': s.onTertiaryFixed,
  'onTertiaryFixedVariant': s.onTertiaryFixedVariant,
  'error': s.error,
  'onError': s.onError,
  'errorContainer': s.errorContainer,
  'onErrorContainer': s.onErrorContainer,
  'surface': s.surface,
  'onSurface': s.onSurface,
  'onSurfaceVariant': s.onSurfaceVariant,
  'surfaceDim': s.surfaceDim,
  'surfaceBright': s.surfaceBright,
  'surfaceContainerLowest': s.surfaceContainerLowest,
  'surfaceContainerLow': s.surfaceContainerLow,
  'surfaceContainer': s.surfaceContainer,
  'surfaceContainerHigh': s.surfaceContainerHigh,
  'surfaceContainerHighest': s.surfaceContainerHighest,
  'outline': s.outline,
  'outlineVariant': s.outlineVariant,
  'shadow': s.shadow,
  'scrim': s.scrim,
  'inverseSurface': s.inverseSurface,
  'onInverseSurface': s.onInverseSurface,
};

/// The tokens the accent slot owns — Material's primary family and nothing
/// else (§23.1.2: exactly one accent is live at a time).
///
/// Every other token in [schemeTokens] belongs to the brand baseline and must
/// be byte-identical for every seed. `secondary`/`tertiary` are deliberately
/// *not* here: a seeded Material scheme fills them with a second and third
/// accent, which §23.3 calls a violation rather than a feature.
const Set<String> accentTokenNames = {
  'primary',
  'onPrimary',
  'primaryContainer',
  'onPrimaryContainer',
  'primaryFixed',
  'primaryFixedDim',
  'onPrimaryFixed',
  'onPrimaryFixedVariant',
  'inversePrimary',
  'surfaceTint',
};

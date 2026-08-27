import 'package:diamond/src/ui/brand/diamond_mark.dart';
import 'package:diamond/src/ui/theme/brand_metrics.dart';
import 'package:diamond/src/ui/theme/brand_type.dart';
import 'package:diamond/src/ui/theme/diamond_semantics.dart';
import 'package:flutter/material.dart';

/// Keys the widget tests resolve against.
@visibleForTesting
const Key splashScreenKey = Key('splashScreen');

/// The splash, once Flutter is running (Claude Design, Turn 03).
///
/// There are two splashes and they are not the same thing. The **native** one
/// — configured in `pubspec.yaml` under `flutter_native_splash` — is the frame
/// the OS paints before any Dart executes, so it can only ever be a color and
/// an image. This is what replaces it a moment later, and it is where the
/// lockup the design actually specifies lives: the mark, the wordmark, the
/// tagline, and a progress track that can only exist once something is
/// genuinely loading.
///
/// The mark is drawn from the same PNG the native splash uses, so the handoff
/// between them does not move it.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key, this.status = 'Loading roster'});

  /// What the app is waiting on, in the design's small mono caps. A splash
  /// that names its wait is the difference between "slow" and "stuck".
  final String status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantics = DiamondSemantics.of(context);
    final light = theme.brightness == Brightness.light;

    // "Raised, not white" in light; "Field, no flash" in dark. Two different
    // roles for one intent — do not be the brightest surface on screen — and
    // the brightest surface is a card in light and a lifted panel in dark, so
    // the roles have to differ to mean the same thing.
    final ground = light ? scheme.surfaceContainerLow : scheme.surface;

    // Material, not a bare ColoredBox: without one in the ancestry every
    // Text on this screen renders with the framework's missing-material
    // debug decoration.
    return Material(
      key: splashScreenKey,
      color: ground,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(),
          DiamondMark(
            size: 104,
            line: semantics.grassLine,
            plate: semantics.clayLine,
          ),
          const SizedBox(height: 22),
          Text(
            'Diamond',
            style: theme.textTheme.displayLarge?.copyWith(
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: BrandMetrics.spaceMd),
          Text(
            // Uppercased here rather than stored shouting: BrandType.eyebrow
            // is tracked for caps and the string is prose everywhere else.
            'Coach the whole field'.toUpperCase(),
            style: BrandType.eyebrow.copyWith(color: semantics.grassLine),
          ),
          const Spacer(),
          _Progress(status: status),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

/// A determinate-looking track that is deliberately **not** animated.
///
/// §18.7 rules out decorative motion, and a bar that sweeps while nothing is
/// measured is exactly that — it claims progress it cannot know. This shows a
/// fixed first segment: the app has started, and the thing it is waiting on
/// has not finished.
class _Progress extends StatelessWidget {
  const _Progress({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final semantics = DiamondSemantics.of(context);

    return Column(
      children: [
        SizedBox(
          width: 96,
          height: 2,
          child: Stack(
            children: [
              ColoredBox(
                color: scheme.outlineVariant,
                child: const SizedBox(width: 96, height: 2),
              ),
              ColoredBox(
                color: semantics.clayLine,
                child: const SizedBox(width: 38, height: 2),
              ),
            ],
          ),
        ),
        const SizedBox(height: BrandMetrics.spaceMd),
        Text(
          status.toUpperCase(),
          style: BrandType.eyebrow.copyWith(
            fontSize: 9,
            letterSpacing: 9 * 0.14,
            // Exactly the design's value in light. Nominally a border role,
            // but it is the quiet-text step the ladder does not otherwise
            // name, and onSurfaceVariant is far too dark here.
            color: scheme.outline,
          ),
        ),
      ],
    );
  }
}

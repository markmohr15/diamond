import 'package:alchemist/alchemist.dart';
import 'package:diamond/src/ui/brand/splash_screen.dart';
import 'package:diamond/src/ui/theme/derive_scheme.dart';
import 'package:diamond/src/ui/theme/team_colors.dart';
import 'package:flutter/material.dart';

const _phone = Size(328, 700);

/// The splash lockup (Claude Design, Turn 03), both themes.
///
/// What to look at: the mark is the same two shapes as the launcher icon —
/// chalk diamond, clay plate at the near vertex — sitting unenclosed rather
/// than in the icon's rounded square. The tagline is Grass in light and
/// Grass-lit in dark, which is §23.3's "as line" rule: brand colors keep their
/// light values as fills and take the lifted values as text.
///
/// The progress track does not animate. §18.7 rules out decorative motion, and
/// a bar that sweeps while nothing is measured claims progress it cannot know.
Widget _app({required Brightness brightness}) => MaterialApp(
  theme: buildTheme(
    deriveScheme(
      accentSeed: StubTeamColors.ownTeam.primary!,
      brightness: brightness,
    ),
  ),
  home: const SplashScreen(),
);

void main() {
  goldenTest(
    'splash, light and dark',
    fileName: 'splash',
    builder: () => GoldenTestGroup(
      columns: 2,
      children: [
        GoldenTestScenario(
          name: 'light: raised, not white',
          constraints: BoxConstraints.tight(_phone),
          child: _app(brightness: Brightness.light),
        ),
        GoldenTestScenario(
          name: 'dark: field, no flash',
          constraints: BoxConstraints.tight(_phone),
          child: _app(brightness: Brightness.dark),
        ),
      ],
    ),
  );
}

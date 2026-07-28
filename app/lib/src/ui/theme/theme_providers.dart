import 'package:diamond/src/ui/theme/color_context.dart';
import 'package:diamond/src/ui/theme/derive_scheme.dart';
import 'package:diamond/src/ui/theme/team_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which [ColorContext] is live, held above the `MaterialApp` so a swap
/// re-themes the whole app rather than a subtree.
///
/// Nothing sets this automatically: entering an opponent's space is a
/// navigation decision the screen makes (§23.3's swap/does-not-swap list), and
/// leaving it must restore [ColorContext.ownTeam] — hence
/// [ColorContextController.exit] rather than a second call site guessing the
/// default.
final colorContextProvider =
    NotifierProvider<ColorContextController, ColorContext>(
      ColorContextController.new,
    );

class ColorContextController extends Notifier<ColorContext> {
  @override
  ColorContext build() => ColorContext.ownTeam;

  /// Enter an opponent's space: their book, hitter cards, scoped deck, or a
  /// game against them. Never a list showing more than one opponent.
  void enterOpponent(String teamId) => state = ColorContext.opponent(teamId);

  /// Back to browsing.
  void exit() => state = ColorContext.ownTeam;
}

/// The team record the accent currently comes from, or null when the context
/// names an opponent that has no record. Real records replace
/// [StubTeamColors] here and nowhere else.
final accentTeamProvider = Provider<TeamColors?>((ref) {
  final context = ref.watch(colorContextProvider);
  return switch (context) {
    OwnTeamContext() => StubTeamColors.ownTeam,
    OpponentContext(:final teamId) => StubTeamColors.opponentById(teamId),
  };
});

/// The seed filling the one accent slot (§23.1.2).
///
/// An unset — or unknown — opponent colour falls back to the baseline accent
/// (§23.3). Never auto-assigned: an invented colour is indistinguishable from a
/// chosen one and will be read as fact.
final accentSeedProvider = Provider<Color>((ref) {
  final team = ref.watch(accentTeamProvider);
  return team?.primary ?? StubTeamColors.ownTeam.primary!;
});

/// §23.1.4: dark mode is not optional — night games are real. Both
/// brightnesses resolve from the same seed, so a context switch cannot leave
/// one mode behind.
final lightThemeProvider = Provider<ThemeData>((ref) {
  final seed = ref.watch(accentSeedProvider);
  return buildTheme(
    deriveScheme(accentSeed: seed, brightness: Brightness.light),
  );
});

final darkThemeProvider = Provider<ThemeData>((ref) {
  final seed = ref.watch(accentSeedProvider);
  return buildTheme(
    deriveScheme(accentSeed: seed, brightness: Brightness.dark),
  );
});

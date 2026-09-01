import 'package:diamond/src/game/game_controller.dart';
import 'package:diamond/src/ui/brand/splash_screen.dart';
import 'package:diamond/src/ui/loop/pitch_loop_page.dart';
import 'package:diamond/src/ui/theme/theme_mode_store.dart';
import 'package:diamond/src/ui/theme/theme_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  runApp(const ProviderScope(child: DiamondApp()));
}

class DiamondApp extends ConsumerWidget {
  const DiamondApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Diamond',
      // Both derived from the one live accent context (§23.3), above the
      // MaterialApp so a swap re-themes everything below it.
      theme: ref.watch(lightThemeProvider),
      darkTheme: ref.watch(darkThemeProvider),
      // §23.1.4: the scorer's choice, not the system's — and only ever one
      // of two. Light until the stored choice loads, which is also the
      // default when nothing is stored.
      themeMode: ref.watch(themeModeProvider).valueOrNull ?? ThemeMode.light,
      // DIA-007's pitch loop is the home screen until §19.4's navigation
      // exists. The DIA-005/006 dev harness is gone (DIA-007's cleanup); the
      // settings surface it was waiting on still does not exist: light/dark
      // is a top-bar toggle, not a destination, so the fidelity and
      // silhouette toggles are still waiting on §19.4.
      home: const _Boot(),
    );
  }
}

/// Holds the splash until the game is open.
///
/// The native splash (`flutter_native_splash` in pubspec) covers the frames
/// before Dart runs; this covers the ones after, while Drift opens the file
/// store and the stream folds. Without it the first frame is a pitch loop with
/// an empty count, which reads as a bug rather than as loading.
///
/// `select` rather than a bare watch: `gameControllerProvider` emits on every
/// recorded pitch, and watching it whole here would rebuild the entire tree —
/// including the canvas — once per event. Only the open/not-open transition
/// matters at this level, and it happens once.
class _Boot extends ConsumerWidget {
  const _Boot();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ready = ref.watch(
      gameControllerProvider.select((game) => game.hasValue),
    );
    return ready ? const PitchLoopPage() : const SplashScreen();
  }
}

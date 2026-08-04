import 'package:diamond/src/ui/loop/pitch_loop_page.dart';
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
      // DIA-007's pitch loop is the home screen until §19.4's navigation
      // exists. The DIA-005/006 dev harness is gone (DIA-007's cleanup) —
      // its fidelity/silhouette toggles come back as real settings when a
      // settings surface exists.
      home: const PitchLoopPage(),
    );
  }
}

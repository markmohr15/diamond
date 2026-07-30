import 'package:diamond/src/ui/theme/theme_providers.dart';
import 'package:diamond/src/ui/zone_canvas/zone_canvas_demo_page.dart';
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
      // Placeholder home screen — DIA-007 replaces this with the real pitch
      // loop and §19.4's navigation. The harness now hosts DIA-006's call
      // screen for the call step, keeping its dev toggles; DIA-007's cleanup
      // deletes the whole page.
      home: const ZoneCanvasDemoPage(),
    );
  }
}

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
      // Placeholder home screen — DIA-006/007 replace this with real
      // navigation (§19.4). For now it just hosts the DIA-005 dev harness.
      home: const ZoneCanvasDemoPage(),
    );
  }
}

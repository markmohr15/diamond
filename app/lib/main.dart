import 'package:diamond/src/ui/zone_canvas/zone_canvas_demo_page.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const DiamondApp());
}

class DiamondApp extends StatelessWidget {
  const DiamondApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Diamond',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
      ),
      // Placeholder home screen — DIA-006/007 replace this with real
      // navigation (§19.4). For now it just hosts the DIA-005 dev harness.
      home: const ZoneCanvasDemoPage(),
    );
  }
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// DIA-012's standing rule: **zero hardcoded color literals in UI code.**
/// Everything reads from `Theme.of(context)` so that a context swap (§23.3)
/// reaches every pixel and the brand tier can never be quietly forked at a call
/// site. A literal is invisible in review and permanent in practice — a grep is
/// the only thing that actually holds the line.
///
/// Runs as an ordinary test so `flutter test` (and therefore CI) enforces it
/// with no workflow of its own.
void main() {
  /// Files permitted to contain color literals, with the reason each is
  /// allowed. Adding an entry is a design decision, not a formality: it says
  /// "these colors are not theme tokens," which is a claim to be argued in
  /// review, not a way to get a diff to pass.
  const allowlist = <String, String>{
    'theme/brand_baseline.dart':
        'The brand baseline itself — tier 1 of §23.3 has to be written down '
            'somewhere, and this is that somewhere.',
    'zone_canvas/zone_canvas.dart':
        'Depiction of physical objects (dirt, chalk, ball leather, plate, cast '
            'shadows), which §23.4 governs as per-surface fidelity rather than '
            'palette. Whether any of them should become theme tokens is open; '
            'DIA-012 scoped itself to the accent, atmosphere, and zone fill, '
            'which are already on the theme. Structural ink is the obvious '
            'next candidate.',
  };

  // `Colors.` catches the Material palette; `Color(0x…)` and `Color.fromARGB`
  // catch raw values. Alpha and lerp helpers on an existing color are fine —
  // they derive from a theme value rather than introduce one.
  final literalPattern = RegExp(
    r'(\bColors\.[a-zA-Z]|\bColor\(0x|\bColor\.fromARGB\(|\bColor\.fromRGBO\()',
  );

  test('no color literals in app/lib/src/ui/ outside the allowlist', () {
    final uiDir = Directory(p.join('lib', 'src', 'ui'));
    expect(
      uiDir.existsSync(),
      isTrue,
      reason: 'run from the app/ package root',
    );

    final offenders = <String>[];
    var scanned = 0;

    for (final entity in uiDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;

      final relative = p
          .relative(entity.path, from: uiDir.path)
          .replaceAll(r'\', '/');
      if (allowlist.containsKey(relative)) continue;

      scanned++;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        // Comments describing a color are documentation, not a literal.
        if (line.trimLeft().startsWith('//')) continue;
        if (literalPattern.hasMatch(line)) {
          offenders.add('$relative:${i + 1}: ${line.trim()}');
        }
      }
    }

    expect(scanned, greaterThan(0), reason: 'the scan found nothing to check');
    expect(
      offenders,
      isEmpty,
      reason:
          'Color literals belong on the theme (§23.3). Read the color from '
          'Theme.of(context) — or, if it genuinely is not a theme token, add '
          "the file to this test's allowlist with a stated reason.",
    );
  });

  test('every allowlist entry still exists', () {
    for (final path in allowlist.keys) {
      expect(
        File(p.join('lib', 'src', 'ui', path)).existsSync(),
        isTrue,
        reason: 'stale allowlist entry: $path',
      );
    }
  });
}

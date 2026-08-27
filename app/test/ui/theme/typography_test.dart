import 'dart:io';

import 'package:diamond/src/ui/theme/brand_type.dart';
import 'package:diamond/src/ui/theme/derive_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the bundle, not the network', () {
    // §12.6/§19.1/§21.5: offline-first is the prime directive. A font that
    // resolves over the network is a blank label in a dugout with no signal,
    // and the failure appears only on the day it matters — so the constraint
    // is pinned here rather than trusted to reviewer memory.
    test('every declared font asset exists and is a real TrueType file', () {
      final declared = _declaredFonts();
      expect(declared, isNotEmpty, reason: 'pubspec declares no fonts');

      for (final asset in declared.values.expand((e) => e)) {
        final file = File(asset);
        expect(
          file.existsSync(),
          isTrue,
          reason:
              '$asset is declared in pubspec.yaml but is not in the repo. '
              'Flutter does not fail on a missing font — it silently falls '
              'back to the system face, so this only shows up as a screen '
              'that looks subtly wrong.',
        );
        // 0x00010000 is the TrueType sfnt version. Guards against a file that
        // exists but is an HTML error page a `curl` happily saved.
        final magic = file.readAsBytesSync().take(4).toList();
        expect(magic, [
          0x00,
          0x01,
          0x00,
          0x00,
        ], reason: '$asset is not a TrueType font');
      }
    });

    test('the family names in code match the ones pubspec declares', () {
      // The families are strings on both sides, and a typo in a string does
      // not fail — it falls back. This is the join.
      expect(_declaredFonts().keys, contains(BrandType.sans));
      expect(_declaredFonts().keys, contains(BrandType.mono));
    });

    test('google_fonts is not a dependency', () {
      // Its default behavior is a runtime fetch, which is exactly the thing
      // the bundled files exist to avoid. Bundling and then adding the package
      // back would leave both paths live and the fetch would win at some call
      // site nobody audits.
      // Matched as a dependency *entry*, not as raw text: pubspec.yaml
      // explains in a comment why the package is absent, and a substring
      // search finds its own explanation.
      final entries = File('pubspec.yaml')
          .readAsLinesSync()
          .where((l) => !l.trimLeft().startsWith('#'))
          .where((l) => RegExp(r'^\s+[a-z_]+:').hasMatch(l));
      expect(
        entries.where((l) => l.contains('google_fonts')),
        isEmpty,
        reason: 'google_fonts fetches at runtime by default',
      );
    });
  });

  group('the scale', () {
    test('every slot is sans — mono is opt-in, never a default', () {
      for (final entry in _slots(BrandType.textTheme).entries) {
        expect(
          entry.value.fontFamily,
          BrandType.sans,
          reason: '${entry.key} should be prose; codes opt in via .code',
        );
      }
    });

    test('every slot declares a size and a weight', () {
      for (final entry in _slots(BrandType.textTheme).entries) {
        expect(entry.value.fontSize, isNotNull, reason: entry.key);
        expect(entry.value.fontWeight, isNotNull, reason: entry.key);
      }
    });

    test('only the three bundled weights are ever asked for', () {
      // Flutter resolves an unbundled weight to the nearest bundled one
      // without complaining, so asking for w600 would render as w500 and look
      // like a design choice nobody made.
      // Not a const set: FontWeight has no primitive equality.
      final bundled = <FontWeight>[
        FontWeight.w400,
        FontWeight.w500,
        FontWeight.w700,
      ];
      for (final entry in _slots(BrandType.textTheme).entries) {
        expect(bundled, contains(entry.value.fontWeight), reason: entry.key);
      }
      expect(bundled, contains(BrandType.eyebrow.fontWeight));
    });

    test('no two slots are the same token', () {
      // A duplicate slot is a scale with a redundant step: two names for one
      // thing, which drift apart the first time someone tunes "one of them".
      final seen = <String, String>{};
      for (final entry in _slots(BrandType.textTheme).entries) {
        final s = entry.value;
        final key =
            '${s.fontFamily}/${s.fontSize}/${s.fontWeight}/'
            '${s.height}/${s.letterSpacing}';
        expect(
          seen,
          isNot(contains(key)),
          reason: '${entry.key} is identical to ${seen[key]}',
        );
        seen[key] = entry.key;
      }
    });

    test('display tracks negative, body does not', () {
      // The panels tighten display type and leave everything from
      // headlineMedium down at normal tracking. A positive value anywhere
      // in the sans scale would be an eyebrow in the wrong tier.
      const t = BrandType.textTheme;
      for (final s in [t.displayLarge!, t.displayMedium!, t.displaySmall!]) {
        expect(s.letterSpacing, lessThan(0));
      }
      for (final s in [t.bodyLarge!, t.bodyMedium!, t.bodySmall!]) {
        expect(s.letterSpacing, isNull);
      }
    });

    test('sizes descend within each tier', () {
      const t = BrandType.textTheme;
      for (final tier in [
        [t.displayLarge!, t.displayMedium!, t.displaySmall!],
        [t.headlineLarge!, t.headlineMedium!, t.headlineSmall!],
        [t.titleLarge!, t.titleMedium!, t.titleSmall!],
        [t.bodyLarge!, t.bodyMedium!, t.bodySmall!],
        [t.labelLarge!, t.labelMedium!, t.labelSmall!],
      ]) {
        expect(tier[0].fontSize, greaterThan(tier[1].fontSize!));
        expect(tier[1].fontSize, greaterThan(tier[2].fontSize!));
      }
    });
  });

  group('the mono rule', () {
    test('.code swaps the face and keeps the tier', () {
      // The point of applying mono to a slot rather than replacing the slot:
      // switching a label to a code must not resize the row it lives on.
      final base = BrandType.textTheme.displayLarge!;
      final code = base.code;

      expect(code.fontFamily, BrandType.mono);
      expect(code.fontSize, base.fontSize);
      expect(code.fontWeight, base.fontWeight);
      expect(code.height, base.height);
    });

    test(".code drops the display face's negative tracking", () {
      // A monospaced face carries its sidebearings in the advance width;
      // tightening closes the gaps that make digits countable.
      expect(BrandType.textTheme.displayLarge!.letterSpacing, lessThan(0));
      expect(BrandType.textTheme.displayLarge!.code.letterSpacing, 0);
    });

    test('eyebrow is mono and widely tracked', () {
      expect(BrandType.eyebrow.fontFamily, BrandType.mono);
      expect(BrandType.eyebrow.letterSpacing, greaterThan(0));
    });
  });

  group('on the theme', () {
    test('both brightnesses carry the same scale', () {
      // Type is tier 1 and brightness-independent (§23.3). If these ever
      // diverge it should be a decision, not a merge artifact.
      ThemeData themeFor(Brightness b) => buildTheme(
        deriveScheme(accentSeed: const Color(0xFF2E5E3E), brightness: b),
      );

      final light = themeFor(Brightness.light).textTheme;
      final dark = themeFor(Brightness.dark).textTheme;

      for (final key in _slots(BrandType.textTheme).keys) {
        final l = _slots(light)[key]!;
        final d = _slots(dark)[key]!;
        expect(d.fontSize, l.fontSize, reason: key);
        expect(d.fontWeight, l.fontWeight, reason: key);
        expect(d.fontFamily, l.fontFamily, reason: key);
      }
    });

    test('the theme colors the scale even though the scale does not', () {
      // BrandType sets no color, so Material's defaults have to be supplying
      // one. If this ever comes back null, every string renders in whatever
      // the ambient DefaultTextStyle happens to be.
      final theme = buildTheme(
        deriveScheme(
          accentSeed: const Color(0xFF2E5E3E),
          brightness: Brightness.light,
        ),
      );
      expect(BrandType.textTheme.bodyMedium!.color, isNull);
      expect(theme.textTheme.bodyMedium!.color, isNotNull);
    });
  });
}

/// Every named slot, so a test can iterate the scale instead of listing it and
/// quietly missing the one that was added last.
Map<String, TextStyle> _slots(TextTheme t) => {
  'displayLarge': t.displayLarge!,
  'displayMedium': t.displayMedium!,
  'displaySmall': t.displaySmall!,
  'headlineLarge': t.headlineLarge!,
  'headlineMedium': t.headlineMedium!,
  'headlineSmall': t.headlineSmall!,
  'titleLarge': t.titleLarge!,
  'titleMedium': t.titleMedium!,
  'titleSmall': t.titleSmall!,
  'bodyLarge': t.bodyLarge!,
  'bodyMedium': t.bodyMedium!,
  'bodySmall': t.bodySmall!,
  'labelLarge': t.labelLarge!,
  'labelMedium': t.labelMedium!,
  'labelSmall': t.labelSmall!,
};

/// `family -> [asset paths]`, read straight out of `pubspec.yaml`.
///
/// Hand-scanned rather than parsed with the `yaml` package, which is only a
/// transitive dependency here — the same choice `no_color_literals_test.dart`
/// makes for the same reason.
Map<String, List<String>> _declaredFonts() {
  final lines = File('pubspec.yaml').readAsLinesSync();
  final out = <String, List<String>>{};

  var inFonts = false;
  String? family;
  for (final line in lines) {
    if (line.trimRight() == '  fonts:') {
      inFonts = true;
      continue;
    }
    if (!inFonts) continue;
    // Any non-blank line back at the `flutter:` child indent ends the block.
    if (line.trim().isNotEmpty &&
        !line.startsWith('    ') &&
        !line.trimLeft().startsWith('#')) {
      break;
    }

    final familyMatch = RegExp(r'^\s*- family:\s*(.+)$').firstMatch(line);
    if (familyMatch != null) {
      family = familyMatch.group(1)!.trim();
      out[family] = [];
      continue;
    }
    final assetMatch = RegExp(r'^\s*- asset:\s*(.+)$').firstMatch(line);
    if (assetMatch != null && family != null) {
      out[family]!.add(assetMatch.group(1)!.trim());
    }
  }
  return out;
}

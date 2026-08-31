import 'package:diamond/src/ui/field_canvas/field_dialog.dart';
import 'package:diamond/src/ui/theme/brand_metrics.dart';
import 'package:diamond/src/ui/theme/brand_type.dart';
import 'package:diamond/src/ui/theme/theme_mode_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Keys the widget tests resolve against.
@visibleForTesting
Key themeModeKey(ThemeMode mode) => Key('themeMode-${mode.name}');

const _labels = <ThemeMode, String>{
  ThemeMode.system: 'System',
  ThemeMode.light: 'Light',
  ThemeMode.dark: 'Dark',
};

/// The settings surface `main.dart` has been waiting on — "its fidelity and
/// silhouette toggles come back as real settings when a settings surface
/// exists." This is that surface, holding the one setting that had to exist
/// first (§23.1.4).
///
/// A dialog rather than a screen: there is no navigation yet (§19.4), and a
/// scorer reaching for this mid-game wants it to appear over the loop and go
/// away again, not to leave the game behind.
Future<void> showSettingsSheet(BuildContext context) => showFieldDialog<void>(
  context,
  title: 'Settings',
  alignment: CrossAxisAlignment.start,
  children: (_) => const [SettingsBody()],
);

/// The sheet's contents, separate from the route that shows them.
///
/// Public so a golden can render it directly: a dialog route hangs off the
/// *host's* navigator, which in the golden harness sits above the
/// `ProviderScope`, so driving the real route there fails on a lookup that
/// succeeds in the app. `field_dialog_chips` split the same way for the same
/// reason.
class SettingsBody extends ConsumerWidget {
  const SettingsBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    // While it loads there is nothing selected — a beat, not a spinner.
    final current = ref.watch(themeModeProvider).valueOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('APPEARANCE', style: BrandType.eyebrow),
        const SizedBox(height: BrandMetrics.spaceMd),
        Wrap(
          spacing: BrandMetrics.spaceMd,
          children: [
            for (final entry in _labels.entries)
              ChoiceChip(
                key: themeModeKey(entry.key),
                label: Text(entry.value),
                selected: current == entry.key,
                onSelected: (_) =>
                    ref.read(themeModeProvider.notifier).choose(entry.key),
              ),
          ],
        ),
        const SizedBox(height: BrandMetrics.spaceMd),
        Text(
          'Night games are why this is here: a dugout tablet is not '
          'reliably in system dark.',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

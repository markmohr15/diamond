import 'package:diamond/src/events/database/app_database.dart';
import 'package:diamond/src/game/game_session.dart';
import 'package:diamond/src/ui/loop/count_hud.dart';
import 'package:diamond/src/ui/theme/theme_mode_store.dart';
import 'package:diamond/src/ui/theme/theme_providers.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// §23.1.4's choice: both themes were built and nothing selected between
/// them, so the app followed the system — the wrong authority for a tablet in
/// a dugout at 9pm.
void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWith((ref) => db)],
    );
  });
  tearDown(() async {
    container.dispose();
    await db.close();
  });

  /// A second launch of the app over the same database — the only way to
  /// prove a preference actually persisted rather than being held in memory.
  ProviderContainer relaunch() {
    final next = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWith((ref) => db)],
    );
    addTearDown(next.dispose);
    return next;
  }

  test('nothing stored: light, not the device', () async {
    // Two states, not three (2026-09-01). `system` is gone, so the app never
    // silently defers to the device — the design's base ladder is light and
    // the toggle is one visible tap away.
    expect(await container.read(themeModeProvider.future), ThemeMode.light);
  });

  test('toggle flips, and keeps flipping', () async {
    await container.read(themeModeProvider.future);
    final notifier = container.read(themeModeProvider.notifier);

    await notifier.toggle();
    expect(container.read(themeModeProvider).value, ThemeMode.dark);
    await notifier.toggle();
    expect(container.read(themeModeProvider).value, ThemeMode.light);
    expect(await relaunch().read(themeModeProvider.future), ThemeMode.light);
  });

  test('a choice survives a relaunch', () async {
    await container.read(themeModeProvider.future);
    await container.read(themeModeProvider.notifier).choose(ThemeMode.dark);

    final next = relaunch();
    expect(await next.read(themeModeProvider.future), ThemeMode.dark);
  });

  test('choosing again replaces rather than accumulating rows', () async {
    await container.read(themeModeProvider.future);
    final notifier = container.read(themeModeProvider.notifier);
    await notifier.choose(ThemeMode.dark);
    await notifier.choose(ThemeMode.light);

    final rows = await db.select(db.appSettings).get();
    expect(rows, hasLength(1));
    expect(await relaunch().read(themeModeProvider.future), ThemeMode.light);
  });

  testWidgets('the top-bar button flips the theme and it reaches MaterialApp', (
    tester,
  ) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const _App()),
    );
    await tester.pumpAndSettle();

    ThemeMode modeOnApp() =>
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode!;
    expect(modeOnApp(), ThemeMode.light);

    // One tap, no sheet in between.
    await tester.tap(find.byKey(countHudThemeKey));
    await tester.pumpAndSettle();
    expect(modeOnApp(), ThemeMode.dark);

    await tester.tap(find.byKey(countHudThemeKey));
    await tester.pumpAndSettle();
    expect(modeOnApp(), ThemeMode.light);
  });
}

/// The count HUD under a `MaterialApp` whose `themeMode` the test reads —
/// the smallest tree that proves the wiring end to end.
class _App extends ConsumerWidget {
  const _App();

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp(
    // The real themes: `CountHud` reads `DiamondSemantics`, which only
    // `buildTheme` installs.
    theme: ref.watch(lightThemeProvider),
    darkTheme: ref.watch(darkThemeProvider),
    themeMode: ref.watch(themeModeProvider).valueOrNull ?? ThemeMode.system,
    home: const Scaffold(body: CountHud()),
  );
}

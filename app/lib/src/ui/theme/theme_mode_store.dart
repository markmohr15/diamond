import 'package:diamond/src/events/database/app_database.dart';
import 'package:diamond/src/game/game_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The settings key the choice lives under. One table, many keys eventually —
/// the fidelity and silhouette toggles `main.dart` is waiting on land here.
@visibleForTesting
const themeModeSettingKey = 'themeMode';

/// Device-local persistence for the scorer's light/dark choice.
class ThemeModeStore {
  ThemeModeStore(this._db);

  final AppDatabase _db;

  Future<ThemeMode> load() async {
    final row = await (_db.select(
      _db.appSettings,
    )..where((t) => t.key.equals(themeModeSettingKey))).getSingleOrNull();
    return switch (row?.value) {
      'dark' => ThemeMode.dark,
      // Light on anything else, the unset case included. **Two states, not
      // three** (Mark, 2026-09-01): `system` is gone, so the app never
      // silently defers the choice to the device. The design's base ladder is
      // light — dark is "every screen after dark" — and the toggle sits in
      // the top bar, one visible tap away if the default is wrong.
      _ => ThemeMode.light,
    };
  }

  Future<void> save(ThemeMode mode) => _db
      .into(_db.appSettings)
      .insertOnConflictUpdate(
        AppSettingsCompanion.insert(key: themeModeSettingKey, value: mode.name),
      );
}

final themeModeStoreProvider = Provider<ThemeModeStore>(
  (ref) => ThemeModeStore(ref.watch(appDatabaseProvider)),
);

/// §23.1.4: dark mode is not optional, and neither is *choosing* it. Both
/// themes were built and nothing selected between them, so the app followed
/// the system — the wrong authority for the use. A tablet in a dugout at a
/// 9pm game is not reliably in system dark, and the scorer could not fix it
/// from inside the app.
///
/// **Two states, and the toggle is a top-bar button** (Mark, 2026-09-01).
/// Light/dark does not belong to the pitch screens at all — its eventual home
/// is a settings screen or a menu that may not even be reachable from here —
/// so a whole settings surface built to hold this one control was scaffolding
/// pretending to be a destination. A direct toggle is honest about being
/// temporary and costs one tap instead of three.
final themeModeProvider = AsyncNotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);

class ThemeModeController extends AsyncNotifier<ThemeMode> {
  @override
  Future<ThemeMode> build() => ref.watch(themeModeStoreProvider).load();

  Future<void> choose(ThemeMode mode) async {
    state = AsyncData(mode);
    await ref.read(themeModeStoreProvider).save(mode);
  }

  /// The top-bar button: light becomes dark, dark becomes light. There is no
  /// third state to cycle through.
  Future<void> toggle() => choose(
    state.valueOrNull == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark,
  );
}

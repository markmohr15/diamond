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
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      // Including the null case: nothing stored means nothing chosen.
      _ => ThemeMode.system,
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
/// the system — which is the wrong authority for the use. A tablet in a dugout
/// at a 9pm game is not reliably in system dark, and the scorer could not fix
/// it from inside the app.
///
/// The default stays [ThemeMode.system]: pinning is the fix for the night
/// game, and what the app does out of the box is a separate question.
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
}

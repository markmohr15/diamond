import 'package:diamond/main.dart';
import 'package:diamond/src/call/team_config.dart';
import 'package:diamond/src/events/database/app_database.dart';
import 'package:diamond/src/game/game_session.dart';
import 'package:diamond/src/ui/call/call_screen.dart';
import 'package:diamond/src/ui/loop/count_hud.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('DiamondApp boots to the pitch loop, on the call step', (
    WidgetTester tester,
  ) async {
    // The scope `main()` installs, with the database swapped for an in-memory
    // one — the loop bootstraps the M1 game on first build, and a widget test
    // has no documents directory to put a file store in.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWith((ref) {
            final db = AppDatabase(NativeDatabase.memory());
            ref.onDispose(db.close);
            return db;
          }),
        ],
        child: const DiamondApp(),
      ),
    );
    await tester.pumpAndSettle();

    // The count HUD is up with the seeded game's zero state, and the loop
    // sits on §11.1's first step: the call, whole arsenal on screen.
    expect(find.byKey(countHudKey), findsOneWidget);
    expect(find.text('0-0'), findsOneWidget);
    expect(find.byType(CallScreen), findsOneWidget);
    for (final type in StubTeamCallConfig.arsenal) {
      expect(find.text(type.name), findsOneWidget);
    }
  });
}

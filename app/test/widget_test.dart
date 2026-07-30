import 'package:diamond/main.dart';
import 'package:diamond/src/call/team_config.dart';
import 'package:diamond/src/ui/call/call_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('DiamondApp boots to the harness, on the call step', (
    WidgetTester tester,
  ) async {
    // The scope `main()` installs: DiamondApp reads its theme from the live
    // color context (§23.3), which lives above the MaterialApp.
    await tester.pumpWidget(const ProviderScope(child: DiamondApp()));
    await tester.pumpAndSettle();

    expect(find.text('Pitch entry demo — DIA-005/006'), findsOneWidget);
    expect(find.byType(CallScreen), findsOneWidget);
    // State 1: nothing chosen yet, so every pitch is on screen (§10.3).
    for (final type in StubTeamCallConfig.arsenal) {
      expect(find.text(type.name), findsOneWidget);
    }
  });
}

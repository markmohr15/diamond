import 'package:diamond/src/call/team_config.dart';
import 'package:diamond/src/events/database/app_database.dart';
import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/game/game_controller.dart';
import 'package:diamond/src/game/game_session.dart';
import 'package:diamond/src/ui/call/call_screen.dart';
import 'package:diamond/src/ui/call/pending_call.dart';
import 'package:diamond/src/ui/loop/count_hud.dart';
import 'package:diamond/src/ui/loop/outcome_step.dart';
import 'package:diamond/src/ui/loop/pitch_flow.dart';
import 'package:diamond/src/ui/loop/pitch_loop_page.dart';
import 'package:diamond/src/ui/theme/derive_scheme.dart';
import 'package:diamond/src/ui/theme/diamond_semantics.dart';
import 'package:diamond/src/ui/theme/team_colors.dart';
import 'package:diamond/src/ui/zone_canvas/zone_canvas.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWith((ref) {
          final db = AppDatabase(NativeDatabase.memory());
          ref.onDispose(db.close);
          return db;
        }),
      ],
    );
  });
  tearDown(() => container.dispose());

  Future<void> pumpLoop(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildTheme(
            deriveScheme(
              accentSeed: StubTeamColors.ownTeam.primary!,
              brightness: Brightness.light,
            ),
          ),
          home: const PitchLoopPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The visible stream, most recent last.
  Future<List<GameEvent>> stream() {
    final session = container.read(gameSessionProvider);
    return container.read(eventStoreProvider).readStream(session.gameId);
  }

  Future<PitchThrown> lastPitch() async {
    final events = await stream();
    final event = events.lastWhere((e) => e.type == 'PitchThrown');
    return PitchThrown.fromJson(event.payload);
  }

  /// Taps the (only) zone canvas at [coord] — a call-step zone tap.
  Future<void> tapCanvasAt(WidgetTester tester, ZoneCoord coord) async {
    final area = find.byKey(zoneCanvasDrawingAreaKey);
    final topLeft = tester.getTopLeft(area);
    await tester.tapAt(
      topLeft + localFromZoneCoord(coord, tester.getSize(area)),
    );
    await tester.pumpAndSettle();
  }

  /// Long-press-and-release at [coord] — the actual-step commit gesture.
  Future<void> placeActualAt(WidgetTester tester, ZoneCoord coord) async {
    final area = find.byKey(zoneCanvasDrawingAreaKey);
    final topLeft = tester.getTopLeft(area);
    final gesture = await tester.startGesture(
      topLeft + localFromZoneCoord(coord, tester.getSize(area)),
    );
    await tester.pump(zoneCanvasArmDuration + const Duration(milliseconds: 50));
    await gesture.up();
    await tester.pumpAndSettle();
  }

  Future<void> tapText(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  group('the full loop, §11.1 in order', () {
    testWidgets('call → actual → outcome → commit, and back to the call '
        'screen with the count advanced', (tester) async {
      await pumpLoop(tester);

      // CALL: two taps, then the pitch happens.
      await tapText(tester, 'Fastball');
      await tapCanvasAt(tester, ZoneCoord(x: 0, y: 0.5)); // c2r2, dead center
      await tester.tap(find.byKey(callScreenPitchThrownKey));
      await tester.pumpAndSettle();

      // ACTUAL: the call surface is gone; this canvas is location entry.
      expect(find.byType(CallScreen), findsNothing);
      expect(find.text('Skip location'), findsOneWidget);
      await placeActualAt(tester, ZoneCoord(x: 0.4, y: 0.3));

      // OUTCOME: in-zone location suggests a called strike (§11.1) — but the
      // full override row is present, because the ump's call is the truth.
      expect(find.byKey(outcomeConfirmKey), findsOneWidget);
      expect(find.text('In play'), findsOneWidget);
      await tester.tap(find.byKey(outcomeConfirmKey));
      await tester.pumpAndSettle();

      // Back on CALL with the whole arsenal, count advanced, one event.
      expect(find.byType(CallScreen), findsOneWidget);
      expect(find.text('Rise'), findsOneWidget);
      expect(find.text('0-1'), findsOneWidget);

      final pitch = await lastPitch();
      expect(pitch.outcome, Outcome.CALLED_STRIKE);
      expect(pitch.intendedType, 'ff');
      expect(pitch.intendedZoneId, 'c2r2');
      expect(pitch.intendedLocation!.x, closeTo(0, 1e-9));
      expect(pitch.intendedLocation!.y, closeTo(0.5, 1e-9));
      expect(pitch.actualLocation!.x, closeTo(0.4, 0.05));
      expect(pitch.actualLocation!.y, closeTo(0.3, 0.05));
      expect(pitch.bounceLocation, isNull);
      expect(pitch.batterId, 'opp-1');
      expect(pitch.pitcherId, 'own-p1');
    });

    testWidgets('the checkmark appears only once a call is complete — a '
        'half-made call has nothing to confirm (§10.3 v0.40)', (tester) async {
      await pumpLoop(tester);
      expect(find.byKey(callScreenPitchThrownKey), findsNothing);

      await tapText(tester, 'Fastball');
      expect(find.byKey(callScreenPitchThrownKey), findsNothing);

      await tapCanvasAt(tester, ZoneCoord(x: 0, y: 0.5));
      expect(find.byKey(callScreenPitchThrownKey), findsOneWidget);
      // Still on the call step: the checkmark confirms, it doesn't auto-fire.
      expect(find.byType(CallScreen), findsOneWidget);
    });

    testWidgets('cancel on the actual step goes back to the call screen with '
        'the pending call still up (§10.3)', (tester) async {
      await pumpLoop(tester);

      await tapText(tester, 'Fastball');
      await tapCanvasAt(tester, ZoneCoord(x: 0, y: 0.5));
      final code = tester
          .widget<Text>(find.byKey(callScreenCodeKey))
          .data;
      await tester.tap(find.byKey(callScreenPitchThrownKey));
      await tester.pumpAndSettle();

      await tapText(tester, 'Cancel');

      expect(find.byType(CallScreen), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(callScreenCodeKey)).data,
        code,
        reason: 'the pending call persists until the pitch result is entered',
      );
      expect(await stream(), hasLength(2), reason: 'bootstrap only — '
          'nothing committed');
    });
  });

  group('skipping (§11.2, per-pitch ladder)', () {
    testWidgets('skip call → skip location → outcome with no suggestion: '
        'the pitch records with no intent and no location', (tester) async {
      await pumpLoop(tester);

      await tapText(tester, 'Skip call');
      expect(find.text('Skip location'), findsOneWidget);
      await tapText(tester, 'Skip location');

      // Nothing to suggest from — the row alone.
      expect(find.byKey(outcomeConfirmKey), findsNothing);
      await tapText(tester, 'Ball');

      final pitch = await lastPitch();
      expect(pitch.outcome, Outcome.BALL);
      expect(pitch.intendedType, isNull);
      expect(pitch.actualLocation, isNull);
      expect(find.text('1-0'), findsOneWidget);
    });
  });

  group('strikeout (§11.3 automatic state)', () {
    Future<void> skipToOutcome(WidgetTester tester) async {
      await tapText(tester, 'Skip call');
      await tapText(tester, 'Skip location');
    }

    testWidgets('strike three records the out itself: RunnerOut appended, '
        'outs up, next batter due', (tester) async {
      await pumpLoop(tester);

      for (final outcome in ['Called strike', 'Swinging strike', 'Foul tip']) {
        await skipToOutcome(tester);
        await tapText(tester, outcome);
      }

      final events = await stream();
      final last = events.last;
      expect(last.type, 'RunnerOut');
      final out = RunnerOut.fromJson(last.payload);
      expect(out.how, How.STRIKEOUT);
      expect(out.runnerId, 'opp-1');

      expect(find.text('1 out'), findsOneWidget);
      expect(find.text('0-0'), findsOneWidget); // next batter's count
      final gs = container.read(gameControllerProvider).requireValue;
      expect(gs.batterDue('opp'), 'opp-2');
    });

    testWidgets('an uncaught third strike with first base open does NOT '
        'assume the out — D3K is armed instead (§11.3)', (tester) async {
      await pumpLoop(tester);

      await skipToOutcome(tester);
      await tapText(tester, 'Called strike');
      await skipToOutcome(tester);
      await tapText(tester, 'Swinging strike');
      await skipToOutcome(tester);
      await tapText(tester, 'Swinging (in dirt)');

      final events = await stream();
      expect(events.last.type, 'PitchThrown',
          reason: 'no RunnerOut: the batter may run on a D3K');
      expect(find.text('0 outs'), findsOneWidget);
    });
  });

  group('unknown and the uncertain count (§12.5)', () {
    testWidgets('an unknown outcome turns the HUD amber', (tester) async {
      await pumpLoop(tester);

      await tapText(tester, 'Skip call');
      await tapText(tester, 'Skip location');
      await tapText(tester, 'Unknown');

      final hud = tester.widget<Container>(find.byKey(countHudKey));
      final semantics = DiamondSemantics.of(
        tester.element(find.byKey(countHudKey)),
      );
      expect(hud.color, semantics.uncertainty);
      // The count itself did not move — unknown never guesses (§12.5).
      expect(find.text('0-0'), findsOneWidget);
    });
  });

  group('undo from the HUD', () {
    testWidgets('one tap voids the last pitch and the count walks back', (
      tester,
    ) async {
      await pumpLoop(tester);

      await tapText(tester, 'Skip call');
      await tapText(tester, 'Skip location');
      await tapText(tester, 'Ball');
      expect(find.text('1-0'), findsOneWidget);

      await tester.tap(find.byKey(countHudUndoKey));
      await tester.pumpAndSettle();
      expect(find.text('0-0'), findsOneWidget);
    });
  });

  group('without wristbands (§10.2): a call but no code', () {
    setUp(() {
      container.dispose();
      container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWith((ref) {
            final db = AppDatabase(NativeDatabase.memory());
            ref.onDispose(db.close);
            return db;
          }),
          teamCallConfigProvider.overrideWithValue(
            StubTeamCallConfig.noWristbandConfig(),
          ),
        ],
      );
    });

    testWidgets('the checkmark stands alone in the code slot and still '
        'advances the loop with full intent', (tester) async {
      await pumpLoop(tester);

      await tapText(tester, 'Fastball');
      await tapCanvasAt(tester, ZoneCoord(x: 0, y: 0.5)); // coarse: c2r2
      expect(find.byKey(callScreenCodeKey), findsNothing);
      expect(find.byKey(callScreenPitchThrownKey), findsOneWidget);

      await tester.tap(find.byKey(callScreenPitchThrownKey));
      await tester.pumpAndSettle();
      await tapText(tester, 'Skip location');
      await tapText(tester, 'Ball');

      final pitch = await lastPitch();
      expect(pitch.intendedType, 'ff');
      expect(pitch.intendedZoneId, 'c2r2');
      expect(pitch.intendedLocation!.x, closeTo(0, 1e-9));
      expect(pitch.intendedLocation!.y, closeTo(0.5, 1e-9));
    });
  });

  group('suggestOutcome', () {
    test('in the zone — edges included — suggests a called strike', () {
      expect(
        suggestOutcome(actual: ZoneCoord(x: 0, y: 0.5)),
        Outcome.CALLED_STRIKE,
      );
      expect(
        suggestOutcome(actual: ZoneCoord(x: 1, y: 0)),
        Outcome.CALLED_STRIKE,
      );
    });

    test('off the plate suggests a ball', () {
      expect(suggestOutcome(actual: ZoneCoord(x: 1.4, y: 0.5)), Outcome.BALL);
      expect(suggestOutcome(actual: ZoneCoord(x: 0, y: -0.2)), Outcome.BALL);
    });

    test('a bounce is never a strike by location', () {
      expect(
        suggestOutcome(bounce: BounceCoord(x: 0, depth: 1.5)),
        Outcome.BALL,
      );
    });

    test('nothing captured, nothing suggested', () {
      expect(suggestOutcome(), isNull);
    });
  });
}

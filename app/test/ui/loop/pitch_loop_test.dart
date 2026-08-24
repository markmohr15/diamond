import 'package:diamond/src/call/team_config.dart';
import 'package:diamond/src/events/database/app_database.dart';
import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/game/game_controller.dart';
import 'package:diamond/src/game/game_session.dart';
import 'package:diamond/src/rules/game_state.dart';
import 'package:diamond/src/rules/official_scoring.dart';
import 'package:diamond/src/ui/call/call_screen.dart';
import 'package:diamond/src/ui/call/pending_call.dart';
import 'package:diamond/src/ui/field_canvas/field_entry_surface.dart';
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
      final code = tester.widget<Text>(find.byKey(callScreenCodeKey)).data;
      await tester.tap(find.byKey(callScreenPitchThrownKey));
      await tester.pumpAndSettle();

      await tapText(tester, 'Cancel');

      expect(find.byType(CallScreen), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(callScreenCodeKey)).data,
        code,
        reason: 'the pending call persists until the pitch result is entered',
      );
      expect(
        await stream(),
        hasLength(2),
        reason:
            'bootstrap only — '
            'nothing committed',
      );
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

    testWidgets('the strikeout and its pitch are one undo unit (§11.3) — '
        'which is what a real D3K is reversed with until the resolution '
        'flow lands', (
      tester,
    ) async {
      await pumpLoop(tester);
      await skipToOutcome(tester);
      await tapText(tester, 'Called strike');
      await skipToOutcome(tester);
      await tapText(tester, 'Swinging strike');
      await skipToOutcome(tester);
      await tapText(tester, 'Swinging strike');

      final events = await stream();
      final out = RunnerOut.fromJson(events.last.payload);
      expect(out.how, How.STRIKEOUT);
      expect(find.text('1 out'), findsOneWidget);

      // The escape hatch until DIA-008: one action-scoped undo.
      await tester.tap(find.byKey(countHudUndoKey));
      await tester.pumpAndSettle();
      expect(find.text('0 outs'), findsOneWidget);
      expect(find.text('0-2'), findsOneWidget);
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

  group('walk auto-applies (§11.3 v0.41)', () {
    testWidgets('ball four places the batter with no confirmation and '
        'returns straight to the call screen', (tester) async {
      await pumpLoop(tester);
      for (var i = 0; i < 4; i++) {
        await tapText(tester, 'Skip call');
        await tapText(tester, 'Skip location');
        await tapText(tester, 'Ball');
      }

      expect(find.byType(CallScreen), findsOneWidget);
      final events = await stream();
      final advance = RunnerAdvance.fromJson(events.last.payload);
      expect(advance.reason, RunnerAdvanceReason.WALK);
      expect((advance.runnerId, advance.from, advance.to), ('opp-1', 0, 1));
      final gs = container.read(gameControllerProvider).requireValue;
      expect(gs.bases.first, 'opp-1');
      expect(gs.batterDue('opp'), 'opp-2');
    });

    testWidgets('one undo tap reverses the whole walk — ball four AND its '
        'forced advance, one action-scoped unit (§6)', (tester) async {
      await pumpLoop(tester);
      for (var i = 0; i < 4; i++) {
        await tapText(tester, 'Skip call');
        await tapText(tester, 'Skip location');
        await tapText(tester, 'Ball');
      }
      expect(
        container.read(gameControllerProvider).requireValue.bases.first,
        'opp-1',
      );

      await tester.tap(find.byKey(countHudUndoKey));
      await tester.pumpAndSettle();

      final gs = container.read(gameControllerProvider).requireValue;
      expect(gs.bases.first, isNull);
      expect((gs.balls, gs.strikes), (3, 0));
      expect(find.text('3-0'), findsOneWidget);
    });
  });

  group('bailout (§11.2 v0.41)', () {
    Future<void> twoFingerSwipeDown(WidgetTester tester) async {
      final center =
          tester.getCenter(find.byKey(countHudKey)) + const Offset(0, 200);
      final one = await tester.startGesture(
        center - const Offset(60, 0),
        pointer: 7,
      );
      final two = await tester.startGesture(
        center + const Offset(60, 0),
        pointer: 8,
      );
      await tester.pump(const Duration(milliseconds: 16));
      await one.moveBy(const Offset(0, 90));
      await two.moveBy(const Offset(0, 90));
      await tester.pump();
      await one.up();
      await two.up();
      await tester.pumpAndSettle();
    }

    testWidgets('two-finger swipe drops to the giant row from the call '
        'step', (tester) async {
      await pumpLoop(tester);
      await twoFingerSwipeDown(tester);

      for (final label in ['BALL', 'STRIKE', 'FOUL', 'IN PLAY']) {
        expect(find.text(label), findsOneWidget);
      }
    });

    testWidgets('STRIKE records strike_unspecified — the count advanced, '
        'the kind honestly unknown (§4.1)', (tester) async {
      await pumpLoop(tester);
      await twoFingerSwipeDown(tester);
      await tapText(tester, 'STRIKE');

      expect((await lastPitch()).outcome, Outcome.STRIKE_UNSPECIFIED);
      expect(find.text('0-1'), findsOneWidget);
      expect(
        find.byType(CallScreen),
        findsOneWidget,
        reason:
            'bailout is '
            'per-pitch: the next pitch starts back at the top of the ladder',
      );
    });

    testWidgets('at two strikes, STRIKE is strike three — the field showed '
        'the at-bat ended — and the K consequence fires', (tester) async {
      await pumpLoop(tester);
      for (var i = 0; i < 2; i++) {
        await tapText(tester, 'Skip call');
        await tapText(tester, 'Skip location');
        await tapText(tester, 'Called strike');
      }

      await twoFingerSwipeDown(tester);
      await tapText(tester, 'STRIKE');

      final events = await stream();
      expect(events.last.type, 'RunnerOut');
      expect(find.text('1 out'), findsOneWidget);
      expect(find.text('0-0'), findsOneWidget);
    });

    testWidgets('at two strikes, FOUL stays a no-op — she is still in the '
        'box', (tester) async {
      await pumpLoop(tester);
      for (var i = 0; i < 2; i++) {
        await tapText(tester, 'Skip call');
        await tapText(tester, 'Skip location');
        await tapText(tester, 'Called strike');
      }

      await twoFingerSwipeDown(tester);
      await tapText(tester, 'FOUL');

      expect(find.text('0-2'), findsOneWidget);
      expect(find.text('0 outs'), findsOneWidget);
    });

    testWidgets('a call gathered before the chaos still rides the bailout '
        'commit', (tester) async {
      await pumpLoop(tester);
      await tapText(tester, 'Fastball');
      await tapCanvasAt(tester, ZoneCoord(x: 0, y: 0.5));

      await twoFingerSwipeDown(tester);
      await tapText(tester, 'BALL');

      final pitch = await lastPitch();
      expect(pitch.outcome, Outcome.BALL);
      expect(pitch.intendedType, 'ff');
      expect(pitch.intendedZoneId, 'c2r2');
    });
  });

  group("catcher's interference (§4.1 v0.43)", () {
    testWidgets('one tap on the outcome dialog: dead ball, PA over, batter '
        'awarded first, ⚖ emitted — and never the field surface', (
      tester,
    ) async {
      await pumpLoop(tester);
      await tapText(tester, 'Skip call');
      await tapText(tester, 'Skip location');
      await tapText(tester, "Catcher's interference");

      // Straight back to the call screen: no play canvas for a dead ball.
      expect(find.byType(CallScreen), findsOneWidget);
      expect(find.text('0-0'), findsOneWidget);

      final events = await stream();
      expect(events.map((e) => e.type).toList().sublist(events.length - 3), [
        'PitchThrown',
        'RuleCall',
        'RunnerAdvance',
      ]);
      expect(events.last.payload['reason'], 'catcher_interference');
      expect(events.last.payload['to'], 1);

      final gs = container.read(gameControllerProvider).requireValue;
      expect(gs.bases.first, 'opp-1');
      expect(gs.batterDue('opp'), 'opp-2');

      // One undo reverses the whole award: pitch, ⚖, and advance.
      await container.read(gameControllerProvider.notifier).undoLast();
      final after = container.read(gameControllerProvider).requireValue;
      expect(after.bases.first, isNull);
      expect(after.batterDue('opp'), 'opp-1');
    });
  });

  group('the outcome sheet', () {
    testWidgets('the suggestion leads and In play always closes it — same '
        'weight, its own row, every time', (tester) async {
      await pumpLoop(tester);
      await tapText(tester, 'Skip call');

      // In the zone: the suggestion is the strike.
      await placeActualAt(tester, ZoneCoord(x: 0.2, y: 0.5));
      expect(
        tester
            .widget<Text>(
              find.descendant(
                of: find.byKey(outcomeConfirmKey),
                matching: find.byType(Text),
              ),
            )
            .data,
        'Called strike',
      );
      // In play carries the suggestion's weight and sits below everything.
      final inPlay = find.byKey(outcomeInPlayKey);
      expect(inPlay, findsOneWidget);
      expect(find.text('In play'), findsOneWidget);
      expect(
        tester.getCenter(inPlay).dy,
        greaterThan(tester.getCenter(find.byKey(outcomeConfirmKey)).dy),
      );
      expect(
        tester.getSize(inPlay).height,
        tester.getSize(find.byKey(outcomeConfirmKey)).height,
      );

      // Out of the zone: the suggestion flips to the ball, In play stays.
      await tester.tapAt(const Offset(20, 20)); // dismiss
      await tester.pumpAndSettle();
      await placeActualAt(tester, ZoneCoord(x: 1.7, y: 0.5));
      expect(
        tester
            .widget<Text>(
              find.descendant(
                of: find.byKey(outcomeConfirmKey),
                matching: find.byType(Text),
              ),
            )
            .data,
        'Ball',
      );
      expect(find.byKey(outcomeInPlayKey), findsOneWidget);

      await tester.tap(find.byKey(outcomeInPlayKey));
      await tester.pumpAndSettle();
      expect((await lastPitch()).outcome, Outcome.IN_PLAY);
    });

    testWidgets('with no location there is no suggestion, and In play is '
        'still the last row', (tester) async {
      await pumpLoop(tester);
      await tapText(tester, 'Skip call');
      await tapText(tester, 'Skip location');

      expect(find.byKey(outcomeConfirmKey), findsNothing);
      expect(find.byKey(outcomeInPlayKey), findsOneWidget);
      expect(
        tester.getCenter(find.byKey(outcomeInPlayKey)).dy,
        greaterThan(tester.getCenter(find.text('Ball')).dy),
      );
    });

    testWidgets('dismissing it returns to the location step with nothing '
        'committed — the choice still takes a tap', (tester) async {
      await pumpLoop(tester);
      await tapText(tester, 'Skip call');
      await placeActualAt(tester, ZoneCoord(x: 0.2, y: 0.6));
      expect(find.byKey(outcomeConfirmKey), findsOneWidget);

      // Tap the scrim above the sheet.
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      expect(find.byKey(outcomeConfirmKey), findsNothing);
      expect(find.text('Skip location'), findsOneWidget);
      expect(
        await stream(),
        hasLength(2),
        reason: 'bootstrap only — nothing committed',
      );

      // Re-confirming from the canvas reopens the sheet and commits.
      await placeActualAt(tester, ZoneCoord(x: 0.2, y: 0.6));
      await tapText(tester, 'Ball');
      expect(find.text('1-0'), findsOneWidget);
    });
  });

  group('record last pitch (§11.1 v0.39)', () {
    // An in-play pitch opens the field surface (§15.1, DIA-008a); the offer
    // belongs to the loop's *return*, so these tests discard the play to get
    // back — the offer must survive the whole field-entry detour.
    Future<void> inPlayUnlocated(WidgetTester tester) async {
      await tapText(tester, 'Skip call');
      await tapText(tester, 'Skip location');
      await tapText(tester, 'In play');
      // Wave off the trajectory modal that opens with the surface
      // (§15.1 v0.43), then discard.
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(fieldDiscardKey));
      await tester.pumpAndSettle();
    }

    testWidgets('no offer when the in-play pitch was located — there is '
        'nothing to fill in', (tester) async {
      await pumpLoop(tester);
      await tapText(tester, 'Skip call');
      await placeActualAt(tester, ZoneCoord(x: 0.2, y: 0.6));
      await tapText(tester, 'In play');
      // Wave off the trajectory modal that opens with the surface
      // (§15.1 v0.43), then discard.
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(fieldDiscardKey));
      await tester.pumpAndSettle();

      expect(find.byKey(recordLastPitchKey), findsNothing);
    });

    testWidgets('X declines for good: the pitch stays honestly unlocated', (
      tester,
    ) async {
      await pumpLoop(tester);
      await inPlayUnlocated(tester);
      expect(find.byKey(recordLastPitchKey), findsOneWidget);

      await tester.tap(find.byKey(dismissLastPitchKey));
      await tester.pumpAndSettle();
      expect(find.byKey(recordLastPitchKey), findsNothing);

      final pitch = await lastPitch();
      expect(pitch.actualLocation, isNull);
    });

    testWidgets('the offer dies when the loop moves on — dismissal by '
        'proceeding, no tap spent on it', (tester) async {
      await pumpLoop(tester);
      await inPlayUnlocated(tester);
      expect(find.byKey(recordLastPitchKey), findsOneWidget);

      await tapText(tester, 'Skip call'); // next pitch is underway
      expect(find.byKey(recordLastPitchKey), findsNothing);
    });

    testWidgets('starting the next call also removes it — the first type '
        'tap is already the choice to move on', (tester) async {
      await pumpLoop(tester);
      await inPlayUnlocated(tester);
      expect(find.byKey(recordLastPitchKey), findsOneWidget);

      await tapText(tester, 'Fastball');
      expect(find.byKey(recordLastPitchKey), findsNothing);
    });

    testWidgets('cancel backs out of location entry with the offer still '
        'standing', (tester) async {
      await pumpLoop(tester);
      await inPlayUnlocated(tester);
      await tester.tap(find.byKey(recordLastPitchKey));
      await tester.pumpAndSettle();

      await tapText(tester, 'Cancel');
      expect(find.byKey(recordLastPitchKey), findsOneWidget);
      final pitch = await lastPitch();
      expect(pitch.actualLocation, isNull, reason: 'nothing committed');
    });
  });

  group('forcedAdvances (§11.3)', () {
    const reason = RunnerAdvanceReason.WALK;

    test('bases empty: only the batter moves', () {
      final advances = forcedAdvances(BaseState.empty, 'b1', reason);
      expect(advances, hasLength(1));
      expect((advances.single.runnerId, advances.single.to), ('b1', 1));
    });

    test('runner on first is forced; runner on third alone is not', () {
      final advances = forcedAdvances(
        const BaseState(first: 'r1', third: 'r3'),
        'b1',
        reason,
      );
      expect(advances.map((a) => a.runnerId).toList(), ['r1', 'b1']);
      expect(advances.first.to, 2);
    });

    test('bases loaded: everyone forced, lead runner first so no placement '
        'overwrites an occupant', () {
      final advances = forcedAdvances(
        const BaseState(first: 'r1', second: 'r2', third: 'r3'),
        'b1',
        reason,
      );
      expect(advances.map((a) => a.runnerId).toList(), [
        'r3',
        'r2',
        'r1',
        'b1',
      ]);
      expect(advances.first.to, 4); // the forced-in run
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

  group('the uncaught third strike (§11.3 v0.46)', () {
    Future<void> strikeThree(WidgetTester tester) async {
      for (final call in ['Called strike', 'Called strike', 'Called strike']) {
        await tapText(tester, 'Skip call');
        await tapText(tester, 'Skip location');
        await tapText(tester, call);
      }
    }

    testWidgets('offered on every third strike she may run on — not only a '
        'ball in the dirt', (tester) async {
      await pumpLoop(tester);
      await strikeThree(tester);
      expect(find.byKey(d3kOutThrowKey), findsOneWidget);
    });

    testWidgets('hidden when the rules prevent her running: first occupied, '
        'fewer than two out', (tester) async {
      await pumpLoop(tester);
      // Walk a runner to first.
      for (var i = 0; i < 4; i++) {
        await tapText(tester, 'Skip call');
        await tapText(tester, 'Skip location');
        await tapText(tester, 'Ball');
      }
      await strikeThree(tester);
      expect(find.byKey(d3kOutThrowKey), findsNothing);
      expect(find.text('1 out'), findsOneWidget);
    });

    testWidgets('out at first: the strikeout is voided and rewritten as 2-3', (
      tester,
    ) async {
      await pumpLoop(tester);
      await strikeThree(tester);
      await tester.tap(find.byKey(d3kOutThrowKey));
      await tester.pumpAndSettle();

      final events = await stream();
      // One out still, but now it says who made it.
      expect(container.read(gameControllerProvider).value!.outs, 1);
      final out = RunnerOut.fromJson(
        events.lastWhere((e) => e.type == 'RunnerOut').payload,
      );
      expect(out.how, How.STRIKEOUT_D3_K_THROW);
      final scoring = foldOfficialScoring(events);
      expect(scoring.putoutsByPosition, {3: 1});
      expect(scoring.assistsByPosition, {2: 1});
      // The pitcher keeps the strikeout either way.
      expect(scoring.strikeoutsByPitcher.values.single, 1);
    });

    testWidgets('safe on a passed ball: no out, the §13.2 pair, no error', (
      tester,
    ) async {
      await pumpLoop(tester);
      await strikeThree(tester);
      await tester.tap(find.byKey(d3kSafePbKey));
      await tester.pumpAndSettle();

      final state = container.read(gameControllerProvider).value!;
      expect(state.outs, 0, reason: 'the recorded strikeout was voided');
      expect(state.bases.first, isNotNull);

      final scoring = foldOfficialScoring(await stream());
      expect(scoring.passedBalls, 1);
      expect(scoring.errors, isEmpty);
      expect(scoring.strikeoutsByPitcher.values.single, 1);
    });

    testWidgets('safe on a wild pitch: the advance alone', (tester) async {
      await pumpLoop(tester);
      await strikeThree(tester);
      await tester.tap(find.byKey(d3kSafeWpKey));
      await tester.pumpAndSettle();

      final events = await stream();
      expect(events.where((e) => e.type == 'FielderTouch'), isEmpty);
      final scoring = foldOfficialScoring(events);
      expect(scoring.wildPitchesByPitcher.values.single, 1);
      expect(container.read(gameControllerProvider).value!.outs, 0);
    });

    testWidgets('ignoring it leaves the strikeout standing', (tester) async {
      await pumpLoop(tester);
      await strikeThree(tester);
      await tester.tap(find.byKey(d3kDismissKey));
      await tester.pumpAndSettle();

      expect(find.byKey(d3kOutThrowKey), findsNothing);
      expect(container.read(gameControllerProvider).value!.outs, 1);
      final out = RunnerOut.fromJson((await stream()).last.payload);
      expect(out.how, How.STRIKEOUT);
    });
  });
}

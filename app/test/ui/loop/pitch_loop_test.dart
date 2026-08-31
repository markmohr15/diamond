import 'package:diamond/src/call/team_config.dart';
import 'package:diamond/src/events/database/app_database.dart';
import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/game/game_controller.dart';
import 'package:diamond/src/game/game_session.dart';
import 'package:diamond/src/play/play_draft_controller.dart';
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

  Future<void> tapKey(WidgetTester tester, Key key) async {
    await tester.tap(find.byKey(key));
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

      // OUTCOME: five primaries at fixed positions, whatever the location
      // was (§11.1 v0.51). Nothing here consults it.
      expect(find.byKey(outcomeKey(Outcome.CALLED_STRIKE)), findsOneWidget);
      expect(find.text('In play'), findsOneWidget);
      await tester.tap(find.byKey(outcomeKey(Outcome.CALLED_STRIKE)));
      await tester.pumpAndSettle();

      // Back on CALL with the whole arsenal, count advanced, one event.
      expect(find.byType(CallScreen), findsOneWidget);
      expect(find.text('Rise'), findsOneWidget);
      expect(find.text('0-1', findRichText: true), findsOneWidget);

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
    testWidgets('skip call → skip location → outcome: the pitch records with '
        'no intent and no location', (tester) async {
      await pumpLoop(tester);

      await tapText(tester, 'Skip call');
      expect(find.text('Skip location'), findsOneWidget);
      await tapText(tester, 'Skip location');

      // The same five primaries as always: with nothing captured, the sheet
      // is identical, which is the point of ranking by frequency.
      expect(find.byKey(outcomeKey(Outcome.BALL)), findsOneWidget);
      await tapText(tester, 'Ball');

      final pitch = await lastPitch();
      expect(pitch.outcome, Outcome.BALL);
      expect(pitch.intendedType, isNull);
      expect(pitch.actualLocation, isNull);
      expect(find.text('1-0', findRichText: true), findsOneWidget);
    });
  });

  group('the batter-action modifier (§4.1)', () {
    testWidgets('a bunt rides along with the outcome, on one event', (
      tester,
    ) async {
      // Posture and outcome are two facts about one pitch, so they are one
      // tap-then-tap on one surface and one `PitchThrown` — never a modifier
      // committed separately, which could disagree about which pitch it
      // described.
      await pumpLoop(tester);
      await tapText(tester, 'Skip call');
      await tapText(tester, 'Skip location');
      await tapKey(tester, batterActionKey(BatterAction.BUNT));
      await tapText(tester, 'Foul');

      final pitch = await lastPitch();
      expect(pitch.batterAction, BatterAction.BUNT);
      expect(pitch.outcome, Outcome.FOUL);
    });

    testWidgets('absent unless she is asked to be, and toggles off', (
      tester,
    ) async {
      await pumpLoop(tester);
      await tapText(tester, 'Skip call');
      await tapText(tester, 'Skip location');
      // On, then off: a mis-tap is corrected before committing rather than by
      // undoing the pitch.
      await tapKey(tester, batterActionKey(BatterAction.SLAP));
      await tapKey(tester, batterActionKey(BatterAction.SLAP));
      await tapText(tester, 'Ball');

      expect((await lastPitch()).batterAction, isNull);
    });

    testWidgets('it does not carry to the next pitch', (tester) async {
      // Posture is a per-pitch observation. Sticking would record a bunt she
      // never showed.
      await pumpLoop(tester);
      await tapText(tester, 'Skip call');
      await tapText(tester, 'Skip location');
      await tapKey(tester, batterActionKey(BatterAction.SLASH));
      await tapText(tester, 'Ball');

      await tapText(tester, 'Skip call');
      await tapText(tester, 'Skip location');
      await tapText(tester, 'Ball');
      expect((await lastPitch()).batterAction, isNull);
    });
  });

  group('the getaway consequence (§13.2, §11.3)', () {
    Future<void> runnerOnSecond(WidgetTester tester) async {
      await container
          .read(gameControllerProvider.notifier)
          .append(
            type: 'RunnerAdvance',
            payload: RunnerAdvance(
              runnerId: 'r2',
              from: 0,
              to: 2,
              reason: RunnerAdvanceReason.BATTED_BALL,
            ).toJson(),
          );
      await tester.pumpAndSettle();
    }

    testWidgets('nothing is offered with the bases empty', (tester) async {
      // Rule 9.13 charges a getaway on its *consequence*. Empty bases, no
      // consequence, no question — and no chip to mis-tap either.
      await pumpLoop(tester);
      await tapText(tester, 'Skip call');
      await tapText(tester, 'Skip location');
      expect(find.byKey(getawayKey(Cause.WILD_PITCH)), findsNothing);
    });

    testWidgets('all runners up one, in a single tap', (tester) async {
      await pumpLoop(tester);
      await runnerOnSecond(tester);
      await tapText(tester, 'Skip call');
      await tapText(tester, 'Skip location');
      await tapKey(tester, getawayKey(Cause.WILD_PITCH));
      await tapText(tester, 'Ball');
      await tapKey(tester, getawayAdvanceAllKey);

      final advance = (await stream())
          .where((e) => e.type == 'RunnerAdvance')
          .map((e) => RunnerAdvance.fromJson(e.payload))
          .last;
      expect(advance.runnerId, 'r2');
      expect((advance.from, advance.to), (2, 3));
      expect(advance.reason, RunnerAdvanceReason.WILD_PITCH);
      expect(container.read(gameControllerProvider).value!.bases.third, 'r2');
    });

    testWidgets("a passed ball writes §13.2's pair, linked", (tester) async {
      // The catcher's misplay and the advance it enabled — the same shape the
      // D3K resolution writes, reused rather than reinvented.
      await pumpLoop(tester);
      await runnerOnSecond(tester);
      await tapText(tester, 'Skip call');
      await tapText(tester, 'Skip location');
      await tapKey(tester, getawayKey(Cause.PASSED_BALL));
      await tapText(tester, 'Ball');
      await tapKey(tester, getawayAdvanceAllKey);

      final events = await stream();
      final touch = events
          .where((e) => e.type == 'FielderTouch')
          .map((e) => FielderTouch.fromJson(e.payload))
          .single;
      expect(touch.position, 2);
      expect(touch.touchType, TouchType.MISSED_CATCH);

      final advance = events.lastWhere((e) => e.type == 'RunnerAdvance');
      expect(
        advance.payload['enabledByTouchId'],
        events.firstWhere((e) => e.type == 'FielderTouch').id,
      );
      final scoring = foldOfficialScoring(events);
      expect(scoring.passedBalls, 1);
      expect(scoring.errors, isEmpty, reason: 'a PB is never an error');
    });

    testWidgets('going to the field seeds the ball loose, not to the catcher', (
      tester,
    ) async {
      // A wild pitch's physics is the *absence* of a touch (§13.2), so seeding
      // her would assert something that did not happen.
      await pumpLoop(tester);
      await runnerOnSecond(tester);
      await tapText(tester, 'Skip call');
      await tapText(tester, 'Skip location');
      await tapKey(tester, getawayKey(Cause.WILD_PITCH));
      await tapText(tester, 'Ball');
      await tapKey(tester, getawayToFieldKey);

      expect(
        container.read(playDraftProvider).value!.holderPosition,
        isNull,
        reason: 'nobody has it — that is what got away means',
      );
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
      // next batter's count
      expect(find.text('0-0', findRichText: true), findsOneWidget);
      final gs = container.read(gameControllerProvider).requireValue;
      expect(gs.batterDue('opp'), 'opp-2');
    });

    testWidgets('the strikeout and its pitch are one undo unit (§11.3) — '
        'which is what a real D3K is reversed with until the resolution '
        'flow lands', (tester) async {
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
      expect(find.text('0-2', findRichText: true), findsOneWidget);
    });
  });

  group('unknown and the uncertain count (§12.5)', () {
    testWidgets('an unknown outcome tints the HUD and says so', (tester) async {
      await pumpLoop(tester);

      await tapText(tester, 'Skip call');
      await tapText(tester, 'Skip location');
      await tapText(tester, 'Unknown');

      final hud = tester.widget<Container>(find.byKey(countHudKey));
      final element = tester.element(find.byKey(countHudKey));
      final semantics = DiamondSemantics.of(element);
      final scheme = Theme.of(element).colorScheme;

      // A wash, not a fill (§23.2): the field moved off its resting color but
      // did not become the saturated reservation, which at this size would be
      // a wall of chroma the eye stops reading after two innings.
      expect(hud.color, isNot(scheme.surfaceContainerHigh));
      expect(hud.color, isNot(semantics.uncertainty));

      // §23.1.7: the state is never signalled by color alone.
      expect(find.byKey(countHudUnsureKey), findsOneWidget);

      // The count itself did not move — unknown never guesses (§12.5).
      expect(find.text('0-0', findRichText: true), findsOneWidget);
    });
  });

  group('undo hands back what the scorer typed (§11.3, DIA-019b)', () {
    /// A full pitch: a real call, a placed location, an outcome.
    Future<void> calledPitch(WidgetTester tester, String outcome) async {
      await tapText(tester, 'Fastball');
      await tapCanvasAt(tester, ZoneCoord(x: 0, y: 0.5)); // c2r2
      await tapKey(tester, callScreenPitchThrownKey);
      await placeActualAt(tester, ZoneCoord(x: -0.2, y: 0.1));
      await tapText(tester, outcome);
    }

    testWidgets('the call and the location survive it — only the wrong '
        'answer has to be given again', (tester) async {
      await pumpLoop(tester);
      await calledPitch(tester, 'Ball');
      final wrong = await lastPitch();

      await tapKey(tester, countHudUndoKey);
      // The location step, with everything still on the canvas — one
      // long-press from the sheet again.
      await placeActualAt(tester, ZoneCoord(x: -0.2, y: 0.1));
      await tapText(tester, 'Called strike');

      final fixed = await lastPitch();
      expect(fixed.outcome, Outcome.CALLED_STRIKE);
      expect(fixed.intendedType, wrong.intendedType);
      expect(fixed.intendedZoneId, wrong.intendedZoneId);
      expect(fixed.intendedLocation?.x, wrong.intendedLocation?.x);
    });

    testWidgets('a second undo still works: the count HUD is reachable, so '
        'depth is not the price of keeping the entry', (tester) async {
      await pumpLoop(tester);
      await calledPitch(tester, 'Ball');
      await calledPitch(tester, 'Ball');
      expect(find.text('2-0', findRichText: true), findsOneWidget);

      await tapKey(tester, countHudUndoKey);
      await tapKey(tester, countHudUndoKey);
      expect(find.text('0-0', findRichText: true), findsOneWidget);
    });

    testWidgets('everything automatic stays voided: a walk goes back with '
        'its forced advance, not without it', (tester) async {
      await pumpLoop(tester);
      for (var i = 0; i < 4; i++) {
        await tapText(tester, 'Skip call');
        await tapText(tester, 'Skip location');
        await tapText(tester, 'Ball');
      }
      var gs = container.read(gameControllerProvider).requireValue;
      expect(gs.bases.first, isNotNull, reason: 'the walk placed her');

      await tapKey(tester, countHudUndoKey);
      gs = container.read(gameControllerProvider).requireValue;
      expect(gs.bases.first, isNull, reason: 'one undo, one unit');
      expect((gs.balls, gs.strikes), (3, 0));
    });

    testWidgets('a pitch that skipped the call comes back with no call — '
        'a zone without a type is not a call (§10.3)', (tester) async {
      await pumpLoop(tester);
      await tapText(tester, 'Skip call');
      await placeActualAt(tester, ZoneCoord(x: 0.1, y: 0.2));
      await tapText(tester, 'Ball');

      await tapKey(tester, countHudUndoKey);
      await placeActualAt(tester, ZoneCoord(x: 0.1, y: 0.2));
      await tapText(tester, 'Called strike');

      final pitch = await lastPitch();
      expect(pitch.intendedType, isNull);
      expect(pitch.intendedZoneId, isNull);
      expect(pitch.actualLocation, isNotNull);
    });

    testWidgets('undoing a §6 correction reopens nothing: the pitch it '
        'corrected is still standing', (tester) async {
      await pumpLoop(tester);
      // In play with no location, then take the standing offer — that
      // backfill is a correction, not a new pitch.
      await tapText(tester, 'Skip call');
      await tapText(tester, 'Skip location');
      await tapText(tester, 'In play');
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(fieldDiscardKey));
      await tester.pumpAndSettle();
      await tapKey(tester, recordLastPitchKey);
      await placeActualAt(tester, ZoneCoord(x: 0.4, y: 0.2));
      expect((await lastPitch()).actualLocation, isNotNull);

      await tapKey(tester, countHudUndoKey);

      final pitch = await lastPitch();
      expect(pitch.actualLocation, isNull, reason: 'the backfill came off');
      expect(pitch.outcome, Outcome.IN_PLAY, reason: 'the pitch stands');
      // Nothing to re-answer, so the loop stayed where it was.
      expect(find.text('Called strike'), findsNothing);
    });
  });

  group('undo stops at the plate appearance (§11.3 v0.54)', () {
    /// One taken pitch, no call, no location.
    Future<void> pitch(WidgetTester tester, String outcome) async {
      await tapText(tester, 'Skip call');
      await tapText(tester, 'Skip location');
      await tapText(tester, outcome);
    }

    /// Three strikes: the plate appearance ends and the next batter is due.
    Future<void> strikeOut(WidgetTester tester) async {
      for (var i = 0; i < 3; i++) {
        await pitch(tester, 'Called strike');
      }
    }

    bool undoEnabled(WidgetTester tester) =>
        tester.widget<IconButton>(find.byKey(countHudUndoKey)).onPressed !=
        null;

    testWidgets('the finished plate appearance is still undoable until the '
        'scorer moves on — the strikeout she just mistapped', (tester) async {
      await pumpLoop(tester);
      await strikeOut(tester);

      expect(undoEnabled(tester), isTrue);
      await tapKey(tester, countHudUndoKey);
      final gs = container.read(gameControllerProvider).requireValue;
      expect((gs.balls, gs.strikes), (0, 2), reason: 'strike three came off');
    });

    testWidgets('calling the next pitch seals it: the first type tap is '
        'moving on, and undo stops offering the last batter', (tester) async {
      await pumpLoop(tester);
      await strikeOut(tester);

      // The signal the record-last-pitch offer already uses.
      await tapText(tester, 'Fastball');
      await tester.pumpAndSettle();

      expect(undoEnabled(tester), isFalse);
      final gs = container.read(gameControllerProvider).requireValue;
      expect(gs.outs, 1, reason: 'the strikeout stands');
    });

    testWidgets('undo cannot walk out of the current plate appearance into '
        'the one before it, however many taps', (tester) async {
      await pumpLoop(tester);
      await strikeOut(tester); // batter 1 down
      await pitch(tester, 'Called strike'); // batter 2, one strike

      // Peel batter 2's plate appearance empty, then keep tapping.
      await tapKey(tester, countHudUndoKey);
      for (var i = 0; i < 3; i++) {
        if (undoEnabled(tester)) await tapKey(tester, countHudUndoKey);
      }

      final gs = container.read(gameControllerProvider).requireValue;
      expect(
        gs.outs,
        1,
        reason: "batter 1's strikeout is sealed behind the boundary",
      );
      expect(undoEnabled(tester), isFalse);
    });

    testWidgets('the seal does not lift when a plate appearance is emptied '
        '— the wall is frozen, not recomputed', (tester) async {
      await pumpLoop(tester);
      await strikeOut(tester);
      await pitch(tester, 'Ball'); // batter 2's only pitch

      await tapKey(tester, countHudUndoKey); // batter 2 now has nothing
      expect(
        undoEnabled(tester),
        isFalse,
        reason: 'recomputing the boundary here would offer batter 1',
      );
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
      expect(find.text('1-0', findRichText: true), findsOneWidget);

      await tester.tap(find.byKey(countHudUndoKey));
      await tester.pumpAndSettle();
      expect(find.text('0-0', findRichText: true), findsOneWidget);
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
      expect(find.text('3-0', findRichText: true), findsOneWidget);
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
      expect(find.text('0-1', findRichText: true), findsOneWidget);
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
      expect(find.text('0-0', findRichText: true), findsOneWidget);
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

      expect(find.text('0-2', findRichText: true), findsOneWidget);
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
      expect(find.text('0-0', findRichText: true), findsOneWidget);

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
    testWidgets('the five primaries are in the same places whatever the '
        'location was', (tester) async {
      await pumpLoop(tester);
      await tapText(tester, 'Skip call');

      // In the zone. The sheet used to promote "Called strike" to a confirm
      // button here — its most confident case and its worst one, since a
      // pitch *in* the zone is more often swung at than taken.
      await placeActualAt(tester, ZoneCoord(x: 0.2, y: 0.5));
      final inZone = [
        for (final outcome in [
          Outcome.BALL,
          Outcome.CALLED_STRIKE,
          Outcome.SWINGING_STRIKE,
          Outcome.FOUL,
        ])
          tester.getCenter(find.byKey(outcomeKey(outcome))).dy,
      ];
      // In play is the fifth primary and sits below the other four (5A).
      final inPlay = tester.getCenter(find.byKey(outcomeInPlayKey)).dy;
      expect(inPlay, greaterThan(inZone.last));
      expect(
        tester.getSize(find.byKey(outcomeInPlayKey)).height,
        tester.getSize(find.byKey(outcomeKey(Outcome.BALL))).height,
        reason: 'equal prominence — no primary outranks another',
      );

      // Out of the zone: byte-for-byte the same layout.
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      await placeActualAt(tester, ZoneCoord(x: 1.7, y: 0.5));
      final outOfZone = [
        for (final outcome in [
          Outcome.BALL,
          Outcome.CALLED_STRIKE,
          Outcome.SWINGING_STRIKE,
          Outcome.FOUL,
        ])
          tester.getCenter(find.byKey(outcomeKey(outcome))).dy,
      ];
      expect(outOfZone, inZone, reason: 'location does not reorder the sheet');

      await tester.tap(find.byKey(outcomeInPlayKey));
      await tester.pumpAndSettle();
      expect((await lastPitch()).outcome, Outcome.IN_PLAY);
    });

    testWidgets('dismissing it returns to the location step with nothing '
        'committed — the choice still takes a tap', (tester) async {
      await pumpLoop(tester);
      await tapText(tester, 'Skip call');
      await placeActualAt(tester, ZoneCoord(x: 0.2, y: 0.6));
      expect(find.byKey(outcomeInPlayKey), findsOneWidget);

      // Tap the scrim above the sheet.
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      expect(find.byKey(outcomeInPlayKey), findsNothing);
      expect(find.text('Skip location'), findsOneWidget);
      expect(
        await stream(),
        hasLength(2),
        reason: 'bootstrap only — nothing committed',
      );

      // Re-confirming from the canvas reopens the sheet and commits.
      await placeActualAt(tester, ZoneCoord(x: 0.2, y: 0.6));
      await tapText(tester, 'Ball');
      expect(find.text('1-0', findRichText: true), findsOneWidget);
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

  group('record last pitch after a D3K (§11.1 v0.53)', () {
    /// Two called strikes, then a third pitch taken to the outcome sheet with
    /// **no location entered** and declared an uncaught third strike. The
    /// pitch commits here; what follows is only how the D3K ended.
    Future<void> d3kUnlocated(WidgetTester tester) async {
      for (var i = 0; i < 2; i++) {
        await tapText(tester, 'Skip call');
        await tapText(tester, 'Skip location');
        await tapText(tester, 'Called strike');
      }
      await tapText(tester, 'Skip call');
      await tapText(tester, 'Skip location');
      await tapKey(tester, outcomeD3kKey);
      await tapKey(tester, d3kSwingingKey);
    }

    /// Capturing a bounce is **two** gestures, not one: a release in the dirt
    /// band hinges the canvas to the top-down plane, and a second release
    /// there places the depth. Both are needed, which is why this asserts the
    /// hinge in between — reaching the ground plane at all is what proves
    /// `onCommitBounce` is wired on this step.
    Future<void> placeBounceAt(WidgetTester tester, double fx) async {
      final area = find.byKey(zoneCanvasDrawingAreaKey);
      final topLeft = tester.getTopLeft(area);
      final size = tester.getSize(area);

      Future<void> longPressAt(double fy) async {
        final gesture = await tester.startGesture(
          topLeft + Offset(size.width * fx, size.height * fy),
        );
        await tester.pump(
          zoneCanvasArmDuration + const Duration(milliseconds: 50),
        );
        await gesture.up();
        await tester.pumpAndSettle();
      }

      await longPressAt(0.97);
      expect(find.text('IN THE DIRT'), findsOneWidget);
      await longPressAt(0.1);
    }

    // The four endings each reset the flow, and each has to carry the offer
    // through. They are separate resets in `pitch_flow`, so one test per
    // ending rather than one test and a loop over keys.
    for (final (name, key) in [
      ('out on the throw', d3kOutThrowKey),
      ('out on the tag', d3kOutTagKey),
      ('safe, wild pitch', d3kSafeWpKey),
      ('safe, passed ball', d3kSafePbKey),
    ]) {
      testWidgets('the offer stands after $name', (tester) async {
        await pumpLoop(tester);
        await d3kUnlocated(tester);
        await tapKey(tester, key);

        expect(find.byKey(recordLastPitchKey), findsOneWidget);
      });
    }

    testWidgets('and it survives the detour to the field — the longest way '
        'back to the loop', (tester) async {
      await pumpLoop(tester);
      await d3kUnlocated(tester);
      await tapKey(tester, d3kFieldKey);
      // The between-pitches surface, so its own ✕ — `fieldDiscardKey` is the
      // play surface's, and a D3K to the field opens the idle chrome.
      await tapKey(tester, fieldIdleCloseKey);

      expect(find.byKey(recordLastPitchKey), findsOneWidget);
    });

    testWidgets('no offer when the D3K pitch was located — the guard against '
        'arming this for every pitch', (tester) async {
      await pumpLoop(tester);
      for (var i = 0; i < 2; i++) {
        await tapText(tester, 'Skip call');
        await tapText(tester, 'Skip location');
        await tapText(tester, 'Called strike');
      }
      await tapText(tester, 'Skip call');
      await placeActualAt(tester, ZoneCoord(x: 0.2, y: -0.3));
      await tapKey(tester, outcomeD3kKey);
      await tapKey(tester, d3kSwingingKey);
      await tapKey(tester, d3kSafeWpKey);

      expect(find.byKey(recordLastPitchKey), findsNothing);
    });

    testWidgets('taking it corrects the committed pitch (§6) rather than '
        'writing a second one', (tester) async {
      await pumpLoop(tester);
      await d3kUnlocated(tester);
      await tapKey(tester, d3kSafeWpKey);
      await tapKey(tester, recordLastPitchKey);
      await placeActualAt(tester, ZoneCoord(x: 0.2, y: 0.4));

      final pitch = await lastPitch();
      expect(pitch.actualLocation, isNotNull);
      expect(pitch.bounceLocation, isNull);

      final visible = await stream();
      expect(
        visible.where((e) => e.type == 'PitchThrown'),
        hasLength(3),
        reason: 'a correction replaces in place — three pitches, not four',
      );
    });

    testWidgets('the bounce hinge is available here: a third strike in the '
        'dirt is the case that motivates the offer', (tester) async {
      await pumpLoop(tester);
      await d3kUnlocated(tester);
      await tapKey(tester, d3kSafeWpKey);
      await tapKey(tester, recordLastPitchKey);
      await placeBounceAt(tester, 0.55);

      final pitch = await lastPitch();
      expect(pitch.bounceLocation, isNotNull);
      expect(
        pitch.actualLocation,
        isNull,
        reason: '§4.1: the two are mutually exclusive',
      );
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

  group('the dropped third strike (§11.3 v0.46)', () {
    /// Two called strikes, then open the outcome sheet on the third pitch.
    Future<void> toThirdStrikeSheet(WidgetTester tester) async {
      for (var i = 0; i < 2; i++) {
        await tapText(tester, 'Skip call');
        await tapText(tester, 'Skip location');
        await tapText(tester, 'Called strike');
      }
      await tapText(tester, 'Skip call');
      await tapText(tester, 'Skip location');
    }

    testWidgets('it lives on the outcome sheet, beside In play — an outcome '
        'that opens a surface, not a note on a strikeout', (tester) async {
      await pumpLoop(tester);
      await toThirdStrikeSheet(tester);
      expect(find.byKey(outcomeD3kKey), findsOneWidget);
    });

    testWidgets('absent at one strike, and absent when the rules prevent her '
        'running', (tester) async {
      await pumpLoop(tester);
      await tapText(tester, 'Skip call');
      await tapText(tester, 'Skip location');
      expect(find.byKey(outcomeD3kKey), findsNothing, reason: '0 strikes');
      await tapText(tester, 'Called strike');

      // Put a runner on first: now she may not run with fewer than two out.
      for (var i = 0; i < 4; i++) {
        await tapText(tester, 'Skip call');
        await tapText(tester, 'Skip location');
        await tapText(tester, 'Ball');
      }
      await toThirdStrikeSheet(tester);
      expect(find.byKey(outcomeD3kKey), findsNothing);
    });

    testWidgets('out at first: no out is ever written and then voided — it '
        'is recorded once, as 2-3', (tester) async {
      await pumpLoop(tester);
      await toThirdStrikeSheet(tester);
      await tapKey(tester, outcomeD3kKey);
      await tapKey(tester, d3kSwingingKey);
      await tapKey(tester, d3kOutThrowKey);

      final events = await stream();
      expect(
        events.where((e) => e.type == 'VoidEvent'),
        isEmpty,
        reason: 'declaring it up front leaves nothing to undo',
      );
      expect(container.read(gameControllerProvider).value!.outs, 1);
      final out = RunnerOut.fromJson(
        events.lastWhere((e) => e.type == 'RunnerOut').payload,
      );
      expect(out.how, How.STRIKEOUT_D3_K_THROW);
      final scoring = foldOfficialScoring(events);
      expect(scoring.putoutsByPosition, {3: 1});
      expect(scoring.assistsByPosition, {2: 1});
      expect(scoring.strikeoutsByPitcher.values.single, 1);
    });

    testWidgets('safe on a passed ball: the §13.2 pair, no out, no error', (
      tester,
    ) async {
      await pumpLoop(tester);
      await toThirdStrikeSheet(tester);
      await tapKey(tester, outcomeD3kKey);
      await tapKey(tester, d3kCalledKey);
      await tapKey(tester, d3kSafePbKey);

      final state = container.read(gameControllerProvider).value!;
      expect(state.outs, 0);
      expect(state.bases.first, isNotNull);
      final scoring = foldOfficialScoring(await stream());
      expect(scoring.passedBalls, 1);
      expect(scoring.errors, isEmpty);
      expect(scoring.strikeoutsByPitcher.values.single, 1);
    });

    testWidgets('the strike kind is kept: a called third strike stays called', (
      tester,
    ) async {
      await pumpLoop(tester);
      await toThirdStrikeSheet(tester);
      await tapKey(tester, outcomeD3kKey);
      await tapKey(tester, d3kCalledKey);
      await tapKey(tester, d3kSafeWpKey);

      final pitch = PitchThrown.fromJson(
        (await stream()).lastWhere((e) => e.type == 'PitchThrown').payload,
      );
      expect(pitch.outcome, Outcome.CALLED_STRIKE);
    });

    testWidgets('backing out of the strike-kind question records nothing', (
      tester,
    ) async {
      await pumpLoop(tester);
      final before = (await stream()).length;
      await toThirdStrikeSheet(tester);
      await tapKey(tester, outcomeD3kKey);
      // Dismiss the dialog by tapping the barrier.
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect((await stream()).length, before + 2, reason: 'the two strikes');
    });
  });
}

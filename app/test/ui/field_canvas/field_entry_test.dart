import 'package:diamond/src/events/database/app_database.dart';
import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/field/field_profile.dart';
import 'package:diamond/src/game/game_controller.dart';
import 'package:diamond/src/game/game_session.dart';
import 'package:diamond/src/play/play_journal_store.dart';
import 'package:diamond/src/rules/official_scoring.dart';
import 'package:diamond/src/ui/field_canvas/field_dialog.dart';
import 'package:diamond/src/ui/field_canvas/field_entry_surface.dart';
import 'package:diamond/src/ui/field_canvas/field_geometry.dart';
import 'package:diamond/src/ui/field_canvas/play_chain_strip.dart';
import 'package:diamond/src/ui/field_canvas/trajectory_row.dart';
import 'package:diamond/src/ui/loop/pitch_loop_page.dart';
import 'package:diamond/src/ui/theme/derive_scheme.dart';
import 'package:diamond/src/ui/theme/team_colors.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// DIA-008a/b acceptance under §15.1 v0.43's grammar: the trajectory modal
/// first; the ball's path drawn (two taps, streak) or implied by the live
/// fielder drag with its what-happened popup; the batter runs on contact;
/// SAFE/OUT resolution at the approached base; the chain strip's chips; the
/// §15.4.2 prompt; atomic ✓ (§15.5); the journal restore; and the committed
/// play as one undo unit.
void main() {
  // One database across containers, so the restore tests can relaunch "the
  // app" (a fresh container) against surviving storage.
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

  /// A second launch of the app over the same database.
  ProviderContainer relaunch() {
    final next = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWith((ref) => db)],
    );
    addTearDown(next.dispose);
    return next;
  }

  Future<void> pumpLoop(WidgetTester tester, {ProviderContainer? into}) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: into ?? container,
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

  Future<List<GameEvent>> stream({ProviderContainer? from}) {
    final c = from ?? container;
    final session = c.read(gameSessionProvider);
    return c.read(eventStoreProvider).readStream(session.gameId);
  }

  /// Fastest path to the field surface: skip call, skip location, "In play".
  /// Arrives with the trajectory modal open (§15.1 v0.43).
  Future<void> reachFieldSurface(WidgetTester tester) async {
    await tester.tap(find.text('Skip call'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip location'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('In play'));
    await tester.pumpAndSettle();
    expect(find.byKey(fieldCanvasKey), findsOneWidget);
  }

  /// The rendered canvas's geometry, for aiming taps at world coordinates.
  FieldGeometry canvasGeometry(WidgetTester tester) => FieldGeometry(
    profile: FieldProfile.fastpitch12U,
    size: tester.getSize(find.byKey(fieldCanvasKey)),
  );

  Offset canvasTopLeft(WidgetTester tester) =>
      tester.getTopLeft(find.byKey(fieldCanvasKey));

  Offset worldPx(WidgetTester tester, FieldCoord world) =>
      canvasTopLeft(tester) + canvasGeometry(tester).toPx(world);

  Future<void> tapKey(WidgetTester tester, Key key) async {
    await tester.tap(find.byKey(key));
    await tester.pumpAndSettle();
  }

  Future<void> tapWorld(WidgetTester tester, FieldCoord world) async {
    await tester.tapAt(worldPx(tester, world));
    await tester.pumpAndSettle();
  }

  Future<void> drag(WidgetTester tester, Offset from, Offset to) async {
    final gesture = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveTo(to);
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.up();
    await tester.pumpAndSettle();
  }

  FieldCoord standardSpot(int position) =>
      standardFielderSpots(FieldProfile.fastpitch12U)[position]!;

  /// Drags [position] from her standard spot to where she made the play.
  Future<void> dragFielder(
    WidgetTester tester,
    int position,
    FieldCoord to,
  ) async {
    await drag(
      tester,
      worldPx(tester, standardSpot(position)),
      worldPx(tester, to),
    );
  }

  /// A throw: from the holder's current spot to the receiver's spot.
  Future<void> dragBall(
    WidgetTester tester,
    FieldCoord from,
    FieldCoord to,
  ) async {
    await drag(tester, worldPx(tester, from), worldPx(tester, to));
  }

  /// Drags the token at [fromBase] and releases it on [target] at [toBase]:
  /// the SAFE pill, the OUT pill, or the base itself (also safe).
  /// [originFrom] names the base the play found her on when she is still
  /// in motion (the walk-up), since the token renders partway up the line.
  Future<void> dragToken(
    WidgetTester tester,
    int fromBase,
    int toBase, {
    String target = 'safe',
    int? originFrom,
  }) async {
    final geometry = canvasGeometry(tester);
    final release = switch (target) {
      'out' => geometry.outAffordanceCenter(toBase),
      'safe' => geometry.safeAffordanceCenter(toBase),
      _ => toBase == 4 ? geometry.plate : geometry.baseCenter(toBase),
    };
    await drag(
      tester,
      canvasTopLeft(tester) +
          geometry.runnerTokenCenter(
            base: fromBase,
            origin: originFrom,
            inMotion: originFrom != null,
          ),
      canvasTopLeft(tester) + release,
    );
  }

  /// Taps the pending force play's SAFE or OUT pill at [base].
  Future<void> tapPill(
    WidgetTester tester,
    int base, {
    bool out = false,
  }) async {
    final geometry = canvasGeometry(tester);
    final center = out
        ? geometry.outAffordanceCenter(base)
        : geometry.safeAffordanceCenter(base);
    await tester.tapAt(canvasTopLeft(tester) + center);
    await tester.pumpAndSettle();
  }

  /// Runs a fixture's gesture script asserting the DIA-008 tap budget: the
  /// list length IS the field-gesture count the ticket documents.
  Future<void> runGestures(
    int budget,
    List<Future<void> Function()> gestures,
  ) async {
    expect(gestures, hasLength(budget), reason: 'ticket tap budget');
    for (final gesture in gestures) {
      await gesture();
    }
  }

  group('reaching the field surface (§11.1: in_play → FIELD)', () {
    testWidgets('the trajectory modal opens with the surface; canvas '
        'touches bring it back until answered (§15.1 v0.43)', (tester) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      expect(find.text('How did it come off the bat?'), findsOneWidget);

      // Wave it away; the canvas just re-asks.
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(find.text('How did it come off the bat?'), findsNothing);
      expect(
        tester.widget<FilledButton>(find.byKey(fieldCommitKey)).onPressed,
        isNull,
      );

      await tapWorld(tester, FieldCoord(x: -45, y: 120));
      expect(find.text('How did it come off the bat?'), findsOneWidget);

      await tapKey(tester, trajectoryKey(Trajectory.LINE));
      expect(find.text('How did it come off the bat?'), findsNothing);
      await tapWorld(tester, FieldCoord(x: -45, y: 120));
      expect(find.text('128 ft'), findsOneWidget);
    });
  });

  group('the drawn path (§15.1 v0.43: two taps, the streak)', () {
    testWidgets('first tap = first bounce, second = where it ended up; '
        'later taps adjust the end', (tester) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.GROUND));

      await tapWorld(tester, FieldCoord(x: -60, y: 140));
      expect(find.text('152 ft'), findsOneWidget); // √(60²+140²)

      await tapWorld(tester, FieldCoord(x: -70, y: 160));
      final label = tester.widget<Text>(find.byKey(fieldDistanceKey)).data!;
      expect(label, '152 ft → 175 ft');

      await tapWorld(tester, FieldCoord(x: -75, y: 165));
      await tapKey(tester, fieldCommitKey);

      final events = await stream();
      final ball = BallInPlay.fromJson(
        events.lastWhere((e) => e.type == 'BallInPlay').payload,
      );
      expect(ball.landing.x, closeTo(-60, 2));
      expect(ball.landing.y, closeTo(140, 2));
      expect(ball.retrieved!.x, closeTo(-75, 2));
      expect(ball.retrieved!.y, closeTo(165, 2));
      expect(ball.trajectory, Trajectory.GROUND);
    });

    testWidgets('a landing on the fence spline suggests off-the-wall '
        '(§15.1)', (tester) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.FLY));

      expect(find.byKey(offWallChipKey), findsNothing);
      await tapWorld(tester, FieldCoord(x: 0, y: 208));
      expect(find.byKey(offWallChipKey), findsOneWidget);

      await tapKey(tester, offWallChipKey);
      await tapKey(tester, fieldCommitKey);

      final events = await stream();
      final ball = BallInPlay.fromJson(
        events.lastWhere((e) => e.type == 'BallInPlay').payload,
      );
      expect(ball.offWall, isTrue);
    });
  });

  group(
    'the fielder drag (§15.1 v0.43: play implied, popup disambiguates)',
    () {
      testWidgets('drag 8 to the ball, Caught: the walk-up voids and the fly '
          'out records itself — four gestures, done', (tester) async {
        await pumpLoop(tester);
        await reachFieldSurface(tester);

        await runGestures(4, [
          () => tapKey(tester, trajectoryKey(Trajectory.FLY)),
          () => dragFielder(tester, 8, FieldCoord(x: 30, y: 160)),
          () => tapKey(tester, fielderPlayKey('caught')),
          () => tapKey(tester, fieldCommitKey),
        ]);

        final events = await stream();
        expect(events.map((e) => e.type), isNot(contains('RunnerAdvance')));
        final ball = BallInPlay.fromJson(
          events.lastWhere((e) => e.type == 'BallInPlay').payload,
        );
        expect(ball.landing.x, closeTo(30, 2));
        expect(ball.landingIsCaught, isTrue);

        final touchEvent = events.lastWhere((e) => e.type == 'FielderTouch');
        final touch = FielderTouch.fromJson(touchEvent.payload);
        expect(touch.touchType, TouchType.CAUGHT);
        expect(touch.position, 8);
        expect(touch.location!.x, closeTo(30, 2));

        final out = events.lastWhere((e) => e.type == 'RunnerOut');
        expect(out.payload['how'], 'fly_out');
        expect(out.payload['putoutTouchId'], touchEvent.id);
        expect(container.read(gameControllerProvider).value!.outs, 1);
      });

      testWidgets('ground ball popup offers ground choices; "Missed it" '
          'records no touch and the batter reaches (§13)', (tester) async {
        await pumpLoop(tester);
        await reachFieldSurface(tester);
        await tapKey(tester, trajectoryKey(Trajectory.GROUND));

        await dragFielder(tester, 4, FieldCoord(x: 30, y: 95));
        expect(find.byKey(fielderPlayKey('caught')), findsNothing);
        expect(find.byKey(fielderPlayKey('fielded')), findsOneWidget);
        await tapKey(tester, fielderPlayKey('missed'));
        await tapKey(tester, fieldCommitKey);

        final events = await stream();
        expect(events.map((e) => e.type), isNot(contains('FielderTouch')));
        final ball = BallInPlay.fromJson(
          events.lastWhere((e) => e.type == 'BallInPlay').payload,
        );
        expect(ball.landing.x, closeTo(30, 2));
        final advance = RunnerAdvance.fromJson(events.last.payload);
        expect(advance.runnerId, 'opp-1');
        expect(advance.to, 1);
      });
    },
  );

  group('throws (§15.1 v0.43: tap while the ball is held)', () {
    testWidgets('with the ball secured, tapping another fielder throws to '
        'her — received_throw at her spot, ball route drawn', (tester) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.GROUND));
      await dragFielder(tester, 6, FieldCoord(x: -50, y: 95));
      await tapKey(tester, fielderPlayKey('fielded'));

      await tapWorld(tester, standardSpot(3)); // the throw, one tap
      // No popup: a throw is not a new play on the ball. The force play's
      // SAFE/OUT pair is up instead — she beat it.
      expect(find.byKey(fielderPlayKey('fielded')), findsNothing);
      await tapPill(tester, 1);
      await tapKey(tester, fieldCommitKey);

      final events = await stream();
      final touches = events.where((e) => e.type == 'FielderTouch').toList();
      expect(touches, hasLength(2));
      expect(touches.last.payload['touchType'], 'received_throw');
      expect(touches.last.payload['position'], 3);
      final location = touches.last.payload['location'] as Map<String, dynamic>;
      expect(location['x'] as double, closeTo(standardSpot(3).x, 2));
    });

    testWidgets('Deflected on a grounder: it hit her and caromed away — a '
        'touch, no error, and the ball is loose (§13.2)', (tester) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.GROUND));

      await dragFielder(tester, 5, FieldCoord(x: -55, y: 85));
      expect(find.text('Deflected'), findsOneWidget);
      await tapKey(tester, fielderPlayKey('deflected'));

      // Loose, so the next fielder is playing the ball, not receiving it.
      await tapWorld(tester, standardSpot(6));
      expect(find.byKey(fielderPlayKey('fielded')), findsOneWidget);
      await tapKey(tester, fielderPlayKey('fielded'));
      await tapKey(tester, fieldCommitKey);

      final events = await stream();
      final touches = events.where((e) => e.type == 'FielderTouch').toList();
      expect(touches, hasLength(2));
      expect(touches.first.payload['touchType'], 'deflected');
      expect(touches.first.payload['position'], 5);
      expect(
        touches.first.payload['ordinaryEffort'],
        isNull,
        reason: 'never an error candidate — no judgment to default',
      );
      // Her reach stands as a hit: a deflection is not a misplay, so it
      // never claims the batter's provisional reach (§13.2).
      final advance = RunnerAdvance.fromJson(
        events.lastWhere((e) => e.type == 'RunnerAdvance').payload,
      );
      expect(advance.reason, RunnerAdvanceReason.BATTED_BALL);
      expect(advance.to, 1);
    });

    testWidgets('Deflected is not offered in the air', (tester) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.FLY));
      await dragFielder(tester, 8, FieldCoord(x: 20, y: 170));
      expect(find.text('Deflected'), findsNothing);
      expect(find.text('Caught'), findsOneWidget);
    });

    testWidgets('the simple 6-3: field it, throw to first, OUT — five '
        'gestures, no runner dragging at all', (tester) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);

      await runGestures(5, [
        () => tapKey(tester, trajectoryKey(Trajectory.GROUND)),
        () => dragFielder(tester, 6, FieldCoord(x: -40, y: 90)),
        () => tapKey(tester, fielderPlayKey('fielded')),
        () => tapWorld(tester, standardSpot(3)), // the throw
        () => tapPill(tester, 1, out: true), // the force play, resolved
      ]);
      await tapKey(tester, fieldCommitKey);

      final events = await stream();
      final tail = events.sublist(events.length - 4);
      expect(tail.map((e) => e.type), [
        'BallInPlay',
        'FielderTouch',
        'FielderTouch',
        'RunnerOut',
      ]);
      expect(tail[1].payload['touchType'], 'fielded');
      expect(tail[2].payload['touchType'], 'received_throw');
      expect(tail[3].payload['how'], 'force');
      expect(tail[3].payload['putoutTouchId'], tail[2].id);
      expect(container.read(gameControllerProvider).value!.outs, 1);
      expect(container.read(gameControllerProvider).value!.bases.first, isNull);
    });

    testWidgets('a loose ball is not throwable: after a drop, tapping '
        'another fielder is a play on the ball', (tester) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.FLY));
      await dragFielder(tester, 8, FieldCoord(x: 10, y: 150));
      await tapKey(tester, fielderPlayKey('dropped'));

      // The ball is on the ground: LF coming over is a pickup, not a
      // reception — the popup asks, and it no longer offers to catch a ball
      // that is already down.
      await tapWorld(tester, standardSpot(7));
      expect(find.text('Caught'), findsNothing);
      expect(find.byKey(fielderPlayKey('fielded')), findsOneWidget);
      await tapKey(tester, fielderPlayKey('fielded'));
      await tapKey(tester, fieldCommitKey);

      final events = await stream();
      final touches = events.where((e) => e.type == 'FielderTouch').toList();
      expect(touches, hasLength(2));
      expect(touches.last.payload['touchType'], 'fielded');
      expect(touches.last.payload['position'], 7);
    });
  });

  group('beyond the fence (§16.3)', () {
    testWidgets('a fair landing past the fence asks "Home run?" — Yes '
        'scores everyone aboard', (tester) async {
      await pumpLoop(tester);
      // A runner on first, so the home run is a two-run shot.
      await container
          .read(gameControllerProvider.notifier)
          .append(
            type: 'RunnerAdvance',
            payload: RunnerAdvance(
              runnerId: 'r1',
              from: 0,
              to: 1,
              reason: RunnerAdvanceReason.BATTED_BALL,
            ).toJson(),
          );
      await tester.pumpAndSettle();
      await reachFieldSurface(tester);

      await runGestures(4, [
        () => tapKey(tester, trajectoryKey(Trajectory.FLY)),
        () => tapWorld(tester, FieldCoord(x: 0, y: 220)), // past the 210 CF
        () => tapKey(tester, beyondFenceKey('yes')),
        () => tapKey(tester, fieldCommitKey),
      ]);

      final events = await stream();
      final advances = events
          .where((e) => e.type == 'RunnerAdvance')
          .map((e) => RunnerAdvance.fromJson(e.payload))
          .toList();
      // The setup advance, then the two scoring legs — lead runner first.
      expect(advances.sublist(1).map((a) => (a.runnerId, a.from, a.to)), [
        ('r1', 1, 4),
        ('opp-1', 0, 4),
      ]);
      expect(
        advances
            .sublist(1)
            .every((a) => a.reason == RunnerAdvanceReason.BATTED_BALL),
        isTrue,
      );

      final state = container.read(gameControllerProvider).value!;
      expect(state.runsByTeam['opp'], 2);
      expect(state.bases.first, isNull);
      expect(state.bases.second, isNull);
      expect(state.bases.third, isNull);
      expect(state.outs, 0);
    });

    testWidgets('a landing inside the fence never asks', (tester) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.FLY));
      await tapWorld(tester, FieldCoord(x: 0, y: 180));
      expect(find.text('Home run?'), findsNothing);
    });

    testWidgets('No proceeds as a normal play — the landing stands and the '
        'walk-up is untouched', (tester) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.FLY));
      await tapWorld(tester, FieldCoord(x: 0, y: 220));
      await tapKey(tester, beyondFenceKey('no'));
      await tapKey(tester, fieldCommitKey);

      final committed = await stream();
      final ball = BallInPlay.fromJson(
        committed.lastWhere((e) => e.type == 'BallInPlay').payload,
      );
      expect(ball.landing.y, closeTo(220, 2));
      final walkUp = RunnerAdvance.fromJson(committed.last.payload);
      expect(walkUp.to, 1, reason: 'the ordinary walk-up, nothing awarded');
      expect(
        container.read(gameControllerProvider).value!.runsByTeam['opp'] ?? 0,
        0,
      );
    });

    testWidgets('landed in the park, ended up over the fence: asks '
        '"Ground rule double?" — Yes awards two bases apiece', (tester) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.LINE));
      await tapWorld(tester, FieldCoord(x: 0, y: 170)); // lands in the park
      expect(find.text('Home run?'), findsNothing);

      await tapWorld(tester, FieldCoord(x: 0, y: 220)); // bounces over
      expect(find.text('Ground rule double?'), findsOneWidget);
      await tapKey(tester, beyondFenceKey('yes'));
      await tapKey(tester, fieldCommitKey);

      final events = await stream();
      final advance = RunnerAdvance.fromJson(events.last.payload);
      expect(advance.runnerId, 'opp-1');
      expect(advance.to, 2);
      expect(advance.reason, RunnerAdvanceReason.GROUND_RULE);
      expect(
        container.read(gameControllerProvider).value!.bases.second,
        'opp-1',
      );
    });
  });

  group('the ball decides what can happen next (§15.1 v0.43)', () {
    testWidgets('once it has been touched it is a ball on the ground: no '
        'catching it, whatever it was off the bat', (tester) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.FLY));
      await dragFielder(tester, 8, FieldCoord(x: 20, y: 170));
      expect(find.text('Caught'), findsOneWidget);
      await tapKey(tester, fielderPlayKey('dropped'));

      await tapWorld(tester, standardSpot(9));
      expect(find.text('Caught'), findsNothing);
      expect(find.text('Fielded'), findsOneWidget);
      expect(find.text('Deflected'), findsOneWidget);
    });

    testWidgets('a liner caroms: deflected off the pitcher, still in the '
        'air, caught by the shortstop for the out', (tester) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.LINE));

      await dragFielder(tester, 1, FieldCoord(x: 2, y: 44));
      expect(find.text('Deflected'), findsOneWidget);
      await tapKey(tester, fielderPlayKey('deflected'));

      // Off the glove and still up: the shortstop can catch it.
      await tapWorld(tester, standardSpot(6));
      expect(find.text('Caught'), findsOneWidget);
      await tapKey(tester, fielderPlayKey('caught'));
      await tapKey(tester, fieldCommitKey);

      final events = await stream();
      final touches = events.where((e) => e.type == 'FielderTouch').toList();
      expect(touches.map((e) => e.payload['touchType']), [
        'deflected',
        'caught',
      ]);
      // The catch retires her wherever it happened — but the ball was not
      // caught where it came down, so the wire field stays honest.
      final ball = BallInPlay.fromJson(
        events.lastWhere((e) => e.type == 'BallInPlay').payload,
      );
      expect(ball.landingIsCaught, isFalse);
      final out = events.lastWhere((e) => e.type == 'RunnerOut');
      expect(out.payload['how'], 'fly_out');
      expect(out.payload['putoutTouchId'], touches.last.id);
      expect(events.map((e) => e.type), isNot(contains('RunnerAdvance')));
    });

    testWidgets('a fly ball is never deflected — one fielder touching it '
        'and another catching it is two fielders on one ball', (tester) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.POPUP));
      await dragFielder(tester, 5, FieldCoord(x: -30, y: 50));
      expect(find.text('Caught'), findsOneWidget);
      expect(find.text('Deflected'), findsNothing);
    });

    testWidgets('dropping a runner on the base she already occupies is not '
        'a move — no from==to leg, and she settles', (tester) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.GROUND));
      await tapWorld(tester, FieldCoord(x: -50, y: 95));

      // She is walking up to first; drag her onto first.
      await dragToken(tester, 1, 1, originFrom: 0);
      expect(find.text('Safe at 1B — how?'), findsNothing);
      await tapKey(tester, fieldCommitKey);

      final events = await stream();
      final advances = events
          .where((e) => e.type == 'RunnerAdvance')
          .map((e) => RunnerAdvance.fromJson(e.payload))
          .toList();
      expect(advances, hasLength(1), reason: 'the walk-up, and only that');
      expect(advances.single.from, 0);
      expect(advances.single.to, 1);
      expect(
        container.read(gameControllerProvider).value!.bases.first,
        'opp-1',
      );
    });
  });

  group('the batter runs on contact (§15.1 v0.43)', () {
    testWidgets('a clean single is trajectory + tap + ✓ — the walk-up '
        'commits by itself and the loop returns', (tester) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);

      await runGestures(3, [
        () => tapKey(tester, trajectoryKey(Trajectory.LINE)),
        () => tapWorld(tester, FieldCoord(x: 110, y: 150)), // inside the yard
        () => tapKey(tester, fieldCommitKey),
      ]);

      expect(find.byKey(fieldCanvasKey), findsNothing);
      expect(find.text('Skip call'), findsOneWidget);

      final events = await stream();
      final types = events.map((e) => e.type).toList();
      expect(types.sublist(types.length - 3), [
        'PitchThrown',
        'BallInPlay',
        'RunnerAdvance',
      ]);
      final advance = RunnerAdvance.fromJson(events.last.payload);
      expect(advance.runnerId, 'opp-1');
      expect(advance.from, 0);
      expect(advance.to, 1);
      expect(advance.reason, RunnerAdvanceReason.BATTED_BALL);

      final state = container.read(gameControllerProvider).value!;
      expect(state.bases.first, 'opp-1');

      // The journal is spent (§15.5); the standing offer survives the play
      // (§11.1 v0.39).
      final session = container.read(gameSessionProvider);
      expect(
        await container.read(playJournalStoreProvider).load(session.gameId),
        isNull,
      );
      expect(find.byKey(recordLastPitchKey), findsOneWidget);
    });

    testWidgets('with first occupied the walk-up cascades — the whole chain '
        'moves with zero drags', (tester) async {
      await pumpLoop(tester);

      // Walk opp-1 aboard: four skipped-entry balls (§11.3 auto-applies the
      // forced advance).
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.text('Skip call'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Skip location'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Ball'));
        await tester.pumpAndSettle();
      }

      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.GROUND));
      await tapWorld(tester, FieldCoord(x: 60, y: 110));
      await tapKey(tester, fieldCommitKey);

      final state = container.read(gameControllerProvider).value!;
      expect(state.bases.first, 'opp-2');
      expect(state.bases.second, 'opp-1');

      final events = await stream();
      final advances = events
          .where((e) => e.type == 'RunnerAdvance')
          .map((e) => RunnerAdvance.fromJson(e.payload))
          .toList();
      expect(advances, hasLength(3)); // the walk, then the play's two
      expect(advances.sublist(1).map((a) => (a.runnerId, a.from, a.to)), [
        ('opp-2', 0, 1),
        ('opp-1', 1, 2),
      ]);
    });

    testWidgets('one undo voids the committed play as a unit, leaving the '
        'pitch (§11.3 action scope)', (tester) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.LINE));
      await tapWorld(tester, FieldCoord(x: 110, y: 150));
      await tapKey(tester, fieldCommitKey);

      await container.read(gameControllerProvider.notifier).undoLast();
      final types = (await stream()).map((e) => e.type).toList();
      expect(types, isNot(contains('BallInPlay')));
      expect(types, isNot(contains('RunnerAdvance')));
      expect(types, contains('PitchThrown'));
    });
  });

  group('fixtures through the UI (DIA-008 accept)', () {
    testWidgets('play 01 — dropped liner, out anyway: 8 field gestures', (
      tester,
    ) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      final spot = FieldCoord(x: -45, y: 120);

      await runGestures(8, [
        () => tapKey(tester, trajectoryKey(Trajectory.LINE)),
        () => dragFielder(tester, 6, spot), // she goes to the ball
        () => tapKey(tester, fielderPlayKey('dropped')),
        () => tapWorld(tester, spot), // the pickup, where she stands
        () => tapKey(tester, fielderPlayKey('fielded')),
        () => tapWorld(tester, standardSpot(3)), // tap 1B = the throw
        // The throw arrived at first with the batter heading there: the
        // SAFE/OUT pair is up at the bag — OUT resolves the force play.
        () => tapPill(tester, 1, out: true),
        () => tapKey(tester, fieldCommitKey),
      ]);

      final events = await stream();
      final tail = events.sublist(events.length - 5);
      expect(tail.map((e) => e.type), [
        'BallInPlay',
        'FielderTouch',
        'FielderTouch',
        'FielderTouch',
        'RunnerOut',
      ]);
      expect(tail[0].payload['landingIsCaught'], isFalse);
      final landing = tail[0].payload['landing'] as Map<String, dynamic>;
      expect(landing['x'] as double, closeTo(-45, 2));
      expect(tail[1].payload['touchType'], 'dropped');
      expect(tail[1].payload['position'], 6);
      expect(tail[1].payload['ordinaryEffort'], isTrue);
      expect(tail[1].payload['ballInPlayEventId'], tail[0].id);
      expect(tail[2].payload['touchType'], 'fielded');
      expect(tail[3].payload['touchType'], 'received_throw');
      expect(tail[3].payload['position'], 3);
      expect(tail[4].payload['how'], 'force');
      expect(tail[4].payload['putoutTouchId'], tail[3].id);
      expect(container.read(gameControllerProvider).value!.outs, 1);
    });

    testWidgets('play 02 — boot then throw-away, batter to third: 10 field '
        'gestures', (tester) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      final spot = FieldCoord(x: -50, y: 95);

      await runGestures(10, [
        () => tapKey(tester, trajectoryKey(Trajectory.GROUND)),
        () => dragFielder(tester, 6, spot),
        () => tapKey(tester, fielderPlayKey('booted')), // claims the reach
        () => tapWorld(tester, spot), // the recovery
        () => tapKey(tester, fielderPlayKey('fielded')), // entry key 2
        () => tapKey(tester, chainNodeKey(2)),
        () => tapKey(tester, chainChipKey('wild_throw')),
        () => dragToken(tester, 1, 3, originFrom: 0),
        () => tapKey(tester, safeChipKey('error')), // links the wild throw
        () => tapKey(tester, fieldCommitKey),
      ]);

      final events = await stream();
      final tail = events.sublist(events.length - 5);
      expect(tail.map((e) => e.type), [
        'BallInPlay',
        'FielderTouch',
        'RunnerAdvance',
        'FielderTouch',
        'RunnerAdvance',
      ]);
      expect(tail[1].payload['touchType'], 'booted');
      expect(tail[1].payload['ordinaryEffort'], isTrue);
      expect(tail[2].payload['reason'], 'error');
      expect(tail[2].payload['enabledByTouchId'], tail[1].id);
      expect(tail[2].payload['from'], 0);
      expect(tail[2].payload['to'], 1);
      expect(tail[3].payload['touchType'], 'wild_throw');
      expect(tail[4].payload['reason'], 'wild_throw');
      expect(tail[4].payload['enabledByTouchId'], tail[3].id);
      expect(tail[4].payload['from'], 1);
      expect(tail[4].payload['to'], 3);
      expect(
        container.read(gameControllerProvider).value!.bases.third,
        'opp-1',
      );
    });

    testWidgets('play 03 — single, R3 scores, batter out stretching 9-6: '
        '9 field gestures', (tester) async {
      await pumpLoop(tester);
      // Setup: a runner on third (the play found her there).
      await container
          .read(gameControllerProvider.notifier)
          .append(
            type: 'RunnerAdvance',
            payload: RunnerAdvance(
              runnerId: 'r3',
              from: 0,
              to: 3,
              reason: RunnerAdvanceReason.BATTED_BALL,
            ).toJson(),
          );
      await tester.pumpAndSettle();
      await reachFieldSurface(tester);
      final spot = FieldCoord(x: 110, y: 180);

      await runGestures(9, [
        () => tapKey(tester, trajectoryKey(Trajectory.LINE)),
        () => dragFielder(tester, 9, spot),
        () => tapKey(tester, fielderPlayKey('picked_up')),
        () => dragToken(tester, 3, 4, target: 'base'), // R3 home
        () => tapKey(tester, safeChipKey('hit')),
        () => dragBall(tester, spot, standardSpot(6)), // the 9-6 throw
        () => dragToken(tester, 1, 2, target: 'out', originFrom: 0),
        () => tapKey(tester, outChipKey('tag')),
        () => tapKey(tester, fieldCommitKey),
      ]);

      final events = await stream();
      final tail = events.sublist(events.length - 8);
      expect(tail.map((e) => e.type), [
        'PitchThrown',
        'BallInPlay',
        'RunnerAdvance', // the batter's walk-up, clean → batted_ball
        'FielderTouch', // 9 fielded, located at the play
        'RunnerAdvance', // r3 scores
        'FielderTouch', // 6 received_throw
        'FielderTouch', // 6 tag_applied (auto)
        'RunnerOut', // tag at second
      ]);
      expect(tail[2].payload['runnerId'], 'opp-1');
      expect(tail[2].payload['to'], 1);
      expect(tail[2].payload['reason'], 'batted_ball');
      expect(tail[3].payload['touchType'], 'fielded');
      expect(tail[3].payload['position'], 9);
      final location = tail[3].payload['location'] as Map<String, dynamic>;
      expect(location['x'] as double, closeTo(110, 2));
      expect(tail[4].payload['runnerId'], 'r3');
      expect(tail[4].payload['to'], 4);
      expect(tail[5].payload['touchType'], 'received_throw');
      expect(tail[6].payload['touchType'], 'tag_applied');
      expect(tail[6].payload['position'], 6);
      expect(tail[7].payload['how'], 'tag');
      expect(tail[7].payload['atBase'], 2);
      expect(tail[7].payload['putoutTouchId'], tail[6].id);

      final state = container.read(gameControllerProvider).value!;
      expect(state.outs, 1);
      expect(state.runsByTeam['opp'], 1);
      expect(state.bases.first, isNull);
    });
  });

  group('the OUT menu offers only possible outs (§4.3)', () {
    /// Puts [runnerId] on [base] before the play, as the fold sees it.
    Future<void> placeRunner(String runnerId, int base) async {
      await container
          .read(gameControllerProvider.notifier)
          .append(
            type: 'RunnerAdvance',
            payload: RunnerAdvance(
              runnerId: runnerId,
              from: 0,
              to: base,
              reason: RunnerAdvanceReason.BATTED_BALL,
            ).toJson(),
          );
    }

    testWidgets('runner from second with first empty is forced nowhere: '
        'thrown out at home, she was tagged', (tester) async {
      await pumpLoop(tester);
      await placeRunner('r2', 2); // the leadoff double
      await tester.pumpAndSettle();
      await reachFieldSurface(tester); // the single behind her

      await tapKey(tester, trajectoryKey(Trajectory.LINE));
      await tapWorld(tester, FieldCoord(x: 60, y: 150));
      await dragToken(tester, 2, 4, target: 'out');

      expect(find.text('Force'), findsNothing);
      expect(find.text('Tag'), findsOneWidget);
      await tapKey(tester, outChipKey('tag'));
      await tapKey(tester, fieldCommitKey);

      final out = (await stream()).lastWhere((e) => e.type == 'RunnerOut');
      expect(out.payload['how'], 'tag');
      expect(out.payload['atBase'], 4);
    });

    testWidgets('bases loaded, the runner from third IS forced at home', (
      tester,
    ) async {
      await pumpLoop(tester);
      await placeRunner('r1', 1);
      await placeRunner('r2', 2);
      await placeRunner('r3', 3);
      await tester.pumpAndSettle();
      await reachFieldSurface(tester);

      await tapKey(tester, trajectoryKey(Trajectory.GROUND));
      await tapWorld(tester, FieldCoord(x: 0, y: 60));
      await dragToken(tester, 4, 4, target: 'out', originFrom: 3);

      expect(find.text('Force'), findsOneWidget);
      await tapKey(tester, outChipKey('force'));
      await tapKey(tester, fieldCommitKey);

      final out = (await stream()).lastWhere((e) => e.type == 'RunnerOut');
      expect(out.payload['how'], 'force');
      expect(out.payload['runnerId'], 'r3');
    });

    testWidgets('a catch removes every force — the runner owes a retouch, '
        'not an advance', (tester) async {
      await pumpLoop(tester);
      await placeRunner('r1', 1);
      await tester.pumpAndSettle();
      await reachFieldSurface(tester);

      await tapKey(tester, trajectoryKey(Trajectory.FLY));
      await dragFielder(tester, 8, FieldCoord(x: 20, y: 170));
      await tapKey(tester, fielderPlayKey('caught'));

      await dragToken(tester, 1, 1, target: 'out');
      expect(find.text('Force'), findsNothing);
      expect(find.text("Didn't tag up"), findsOneWidget);
    });

    testWidgets('fly out belongs to the batter; the appeal does not', (
      tester,
    ) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.FLY));
      await dragFielder(tester, 8, FieldCoord(x: 20, y: 170));
      await tapKey(tester, fielderPlayKey('dropped')); // she can still run

      await dragToken(tester, 1, 2, target: 'out', originFrom: 0);
      expect(find.text('Fly out'), findsNothing, reason: 'nothing was caught');
      expect(find.text('Force'), findsNothing, reason: 'second is not next');
      expect(find.text('Tag'), findsOneWidget);
    });
  });

  group('the catch and its appeal (§15.1 v0.43)', () {
    testWidgets('a caught fly returns runners to their bases; the OUT '
        'dialog then offers the tag-up appeal', (tester) async {
      await pumpLoop(tester);
      // A runner on second, so there is somebody to double off.
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
      await reachFieldSurface(tester);

      await tapKey(tester, trajectoryKey(Trajectory.FLY));
      await dragFielder(tester, 8, FieldCoord(x: 20, y: 170));
      await tapKey(tester, fielderPlayKey('caught'));

      // She never tagged: the throw goes to second, then she's doubled off.
      await tapWorld(tester, standardSpot(6));
      await dragToken(tester, 2, 2, target: 'out');
      expect(find.text("Didn't tag up"), findsOneWidget);
      await tapKey(tester, outChipKey('appeal'));
      await tapKey(tester, fieldCommitKey);

      final events = await stream();
      final outs = events.where((e) => e.type == 'RunnerOut').toList();
      expect(outs, hasLength(2));
      expect(outs.first.payload['how'], 'fly_out');
      expect(outs.last.payload['runnerId'], 'r2');
      expect(outs.last.payload['how'], 'appeal');
      expect(outs.last.payload['atBase'], 2);
      // The putout goes to whoever held the ball at the bag.
      final received = events.lastWhere(
        (e) =>
            e.type == 'FielderTouch' &&
            e.payload['touchType'] == 'received_throw',
      );
      expect(outs.last.payload['putoutTouchId'], received.id);
      expect(container.read(gameControllerProvider).value!.outs, 2);
    });

    testWidgets('with two away the catch is the third out: no OUT pill, no '
        'appeal, no fourth out (§4.4)', (tester) async {
      await pumpLoop(tester);
      final game = container.read(gameControllerProvider.notifier);
      for (final id in ['x1', 'x2']) {
        await game.append(
          type: 'RunnerOut',
          payload: RunnerOut(runnerId: id, atBase: 1, how: How.FORCE).toJson(),
        );
      }
      await game.append(
        type: 'RunnerAdvance',
        payload: RunnerAdvance(
          runnerId: 'r2',
          from: 0,
          to: 2,
          reason: RunnerAdvanceReason.BATTED_BALL,
        ).toJson(),
      );
      await tester.pumpAndSettle();
      expect(container.read(gameControllerProvider).value!.outs, 2);

      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.FLY));
      await dragFielder(tester, 8, FieldCoord(x: 20, y: 170));
      await tapKey(tester, fielderPlayKey('caught')); // the third out

      // The half is over: dragging the runner onto OUT does nothing.
      await dragToken(tester, 2, 2, target: 'out');
      expect(find.text("Didn't tag up"), findsNothing);
      expect(find.text('Tag'), findsNothing);
      await tapKey(tester, fieldCommitKey);

      final state = container.read(gameControllerProvider).value!;
      expect(state.outs, 3, reason: 'never a fourth');
      expect(state.halfEnded, isTrue);
      final outs = (await stream()).where((e) => e.type == 'RunnerOut');
      expect(outs, hasLength(3));
    });

    testWidgets('with one away the appeal still stands — doubled off for '
        'the third out', (tester) async {
      await pumpLoop(tester);
      final game = container.read(gameControllerProvider.notifier);
      await game.append(
        type: 'RunnerOut',
        payload: RunnerOut(runnerId: 'x1', atBase: 1, how: How.FORCE).toJson(),
      );
      await game.append(
        type: 'RunnerAdvance',
        payload: RunnerAdvance(
          runnerId: 'r2',
          from: 0,
          to: 2,
          reason: RunnerAdvanceReason.BATTED_BALL,
        ).toJson(),
      );
      await tester.pumpAndSettle();

      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.FLY));
      await dragFielder(tester, 8, FieldCoord(x: 20, y: 170));
      await tapKey(tester, fielderPlayKey('caught')); // the second out

      await dragToken(tester, 2, 2, target: 'out');
      expect(find.text("Didn't tag up"), findsOneWidget);
      await tapKey(tester, outChipKey('appeal'));
      await tapKey(tester, fieldCommitKey);

      final state = container.read(gameControllerProvider).value!;
      expect(state.outs, 3);
      expect(state.halfEnded, isTrue);
    });

    testWidgets('with no catch, the appeal is not offered', (tester) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.GROUND));
      await tapWorld(tester, FieldCoord(x: -50, y: 95));
      await dragToken(tester, 1, 2, target: 'out', originFrom: 0);
      expect(find.text("Didn't tag up"), findsNothing);
      expect(find.text('Tag'), findsOneWidget);
    });
  });

  group('the SAFE menu after a catch (§15.1 v0.43)', () {
    Future<void> flyBallWithRunnerOnThird(WidgetTester tester) async {
      await container
          .read(gameControllerProvider.notifier)
          .append(
            type: 'RunnerAdvance',
            payload: RunnerAdvance(
              runnerId: 'r3',
              from: 0,
              to: 3,
              reason: RunnerAdvanceReason.BATTED_BALL,
            ).toJson(),
          );
      await tester.pumpAndSettle();
      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.FLY));
      await dragFielder(tester, 8, FieldCoord(x: 10, y: 200));
      await tapKey(tester, fielderPlayKey('caught'));
    }

    testWidgets('a runner tagging home on a caught fly with no throw is not '
        'asked at all — one possible answer is not a question', (tester) async {
      await pumpLoop(tester);
      await flyBallWithRunnerOnThird(tester);

      await dragToken(tester, 3, 4, target: 'base');
      // No popup: nothing else could have moved her.
      expect(find.text('On the hit'), findsNothing);
      expect(find.text("Fielder's choice"), findsNothing);
      expect(find.text('Obstruction'), findsNothing);
      await tapKey(tester, fieldCommitKey);

      final events = await stream();
      final advance = RunnerAdvance.fromJson(
        events.lastWhere((e) => e.type == 'RunnerAdvance').payload,
      );
      expect(advance.runnerId, 'r3');
      expect(advance.from, 3);
      expect(advance.to, 4);
      expect(advance.reason, RunnerAdvanceReason.BATTED_BALL);
      // Which is exactly the shape §13.6 reads as a sacrifice fly.
      expect(
        container.read(gameControllerProvider).value!.runsByTeam['opp'],
        1,
      );
    });

    testWidgets('with a throw it asks, and says tagged up rather than "on '
        'the hit" — nothing was hit anywhere', (tester) async {
      await pumpLoop(tester);
      await flyBallWithRunnerOnThird(tester);
      await tapWorld(tester, standardSpot(2)); // the throw home

      await dragToken(tester, 3, 4, target: 'base');
      expect(find.text('Tagged up'), findsOneWidget);
      expect(find.text('On the hit'), findsNothing);
      expect(find.text('On the throw'), findsOneWidget);
      expect(find.text("Fielder's choice"), findsNothing);
      await tapKey(tester, safeChipKey('hit'));
      await tapKey(tester, fieldCommitKey);

      final events = await stream();
      final advance = RunnerAdvance.fromJson(
        events.lastWhere((e) => e.type == 'RunnerAdvance').payload,
      );
      expect(advance.reason, RunnerAdvanceReason.BATTED_BALL);
    });

    testWidgets('"On the throw" needs a throw, not merely a touch', (
      tester,
    ) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.GROUND));
      await dragFielder(tester, 6, FieldCoord(x: -40, y: 90));
      await tapKey(tester, fielderPlayKey('fielded'));

      await dragToken(tester, 1, 2, originFrom: 0);
      expect(find.text('On the throw'), findsNothing);
      // The batter's own answer names the hit she got.
      expect(find.text('Double'), findsOneWidget);
    });
  });

  group('the SAFE menu offers only answers with a cause (§13.2)', () {
    testWidgets('"On an error" is absent until a misplay exists to link', (
      tester,
    ) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.GROUND));
      await tapWorld(tester, FieldCoord(x: -50, y: 95));
      await tapWorld(tester, standardSpot(6));
      await tapKey(tester, fielderPlayKey('fielded')); // clean

      await dragToken(tester, 1, 2, originFrom: 0);
      expect(find.text('On an error'), findsNothing);
      await tapKey(tester, safeChipKey('hit'));
      await tapKey(tester, fieldCommitKey);

      final events = await stream();
      final advance = RunnerAdvance.fromJson(events.last.payload);
      expect(advance.reason, RunnerAdvanceReason.BATTED_BALL);
    });

    testWidgets('with a misplay on the chain it is offered, and links to it', (
      tester,
    ) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.GROUND));
      await dragFielder(tester, 6, FieldCoord(x: -50, y: 95));
      await tapKey(tester, fielderPlayKey('booted'));

      await dragToken(tester, 1, 2, originFrom: 0);
      expect(find.text('On an error'), findsOneWidget);
      await tapKey(tester, safeChipKey('error'));
      await tapKey(tester, fieldCommitKey);

      final events = await stream();
      final touch = events.firstWhere((e) => e.type == 'FielderTouch');
      final advance = events.lastWhere((e) => e.type == 'RunnerAdvance');
      expect(advance.payload['enabledByTouchId'], touch.id);
      expect(advance.payload['reason'], 'error');
    });
  });

  group('the sacrifice judgment (§13.6 v0.43)', () {
    testWidgets('a bunt that moves a runner offers the judgment; a bunt that '
        'moves nobody does not', (tester) async {
      await pumpLoop(tester);
      await container
          .read(gameControllerProvider.notifier)
          .append(
            type: 'RunnerAdvance',
            payload: RunnerAdvance(
              runnerId: 'r1',
              from: 0,
              to: 1,
              reason: RunnerAdvanceReason.BATTED_BALL,
            ).toJson(),
          );
      await tester.pumpAndSettle();
      await reachFieldSurface(tester);

      await tapKey(tester, trajectoryKey(Trajectory.BUNT));
      await tapWorld(tester, FieldCoord(x: -18, y: 24));
      // The walk-up pushed R1 to second, so the question is live.
      expect(find.byKey(sacrificeChipKey), findsOneWidget);
      await tapKey(tester, sacrificeChipKey);

      // She is thrown out at first; the runner she moved stands at second.
      await tapWorld(tester, standardSpot(5));
      await tapKey(tester, fielderPlayKey('fielded'));
      await tapWorld(tester, standardSpot(3));
      await tapPill(tester, 1, out: true);
      await tapKey(tester, fieldCommitKey);

      final events = await stream();
      final ball = BallInPlay.fromJson(
        events.lastWhere((e) => e.type == 'BallInPlay').payload,
      );
      expect(ball.sacrifice, isTrue);
      expect(ball.trajectory, Trajectory.BUNT);
    });

    testWidgets('no runner moved, no question — a bunt for a hit is just a '
        'bunt', (tester) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.BUNT));
      await tapWorld(tester, FieldCoord(x: -18, y: 24));
      expect(find.byKey(sacrificeChipKey), findsNothing);
    });

    testWidgets('a fly ball never asks — the sac fly derives', (tester) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.FLY));
      await tapWorld(tester, FieldCoord(x: 0, y: 180));
      expect(find.byKey(sacrificeChipKey), findsNothing);
    });
  });

  group('the locked path and the reset (§15.1 v0.43)', () {
    testWidgets('once anything hangs off the path, open-field taps stop '
        'changing it; ↺ starts the play over', (tester) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.GROUND));
      await tapWorld(tester, FieldCoord(x: -60, y: 140));
      expect(find.text('152 ft'), findsOneWidget);

      // A fielder plays it: the path is now load-bearing.
      await tapWorld(tester, standardSpot(6));
      await tapKey(tester, fielderPlayKey('fielded'));

      // Open-field taps no longer touch the streak.
      await tapWorld(tester, FieldCoord(x: -85, y: 190));
      expect(find.text('152 ft'), findsOneWidget);

      // The reset wipes the play — trajectory question and all — and the
      // path draws fresh.
      await tapKey(tester, fieldResetKey);
      expect(find.text('How did it come off the bat?'), findsOneWidget);
      await tapKey(tester, trajectoryKey(Trajectory.FLY));
      await tapWorld(tester, FieldCoord(x: 30, y: 160));
      expect(find.text('163 ft'), findsOneWidget); // √(30²+160²)

      await tapKey(tester, fieldCommitKey);
      final events = await stream();
      final ball = BallInPlay.fromJson(
        events.lastWhere((e) => e.type == 'BallInPlay').payload,
      );
      expect(ball.trajectory, Trajectory.FLY);
      expect(ball.landing.x, closeTo(30, 2));
      expect(events.map((e) => e.type), isNot(contains('FielderTouch')));
    });

    testWidgets('re-dragging a fielder who already played the ball adjusts '
        'her play — one touch, moved, never two', (tester) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.FLY));
      await dragFielder(tester, 8, FieldCoord(x: 30, y: 160));
      await tapKey(tester, fielderPlayKey('caught'));

      // Second thought: she actually caught it deeper toward the gap. The
      // re-drag moves her and the play — no popup, no second touch.
      await drag(
        tester,
        worldPx(tester, FieldCoord(x: 30, y: 160)),
        worldPx(tester, FieldCoord(x: 55, y: 175)),
      );
      expect(find.byKey(fielderPlayKey('caught')), findsNothing);
      await tapKey(tester, fieldCommitKey);

      final events = await stream();
      final touches = events.where((e) => e.type == 'FielderTouch').toList();
      expect(touches, hasLength(1));
      final location =
          touches.single.payload['location'] as Map<String, dynamic>;
      expect(location['x'] as double, closeTo(55, 2));
      final ball = BallInPlay.fromJson(
        events.lastWhere((e) => e.type == 'BallInPlay').payload,
      );
      expect(ball.landing.x, closeTo(55, 2), reason: 'assumed landing moves');
    });
  });

  group('chips and prompts (§15.3–15.4)', () {
    testWidgets('a throw to first never guesses at a drop: the runner is '
        'presumed, not ruled, and nothing is asked', (tester) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.GROUND));
      await tapWorld(tester, FieldCoord(x: -50, y: 95));
      await tapWorld(tester, standardSpot(6));
      await tapKey(tester, fielderPlayKey('fielded'));
      await tapWorld(tester, standardSpot(3)); // the throw

      // The pills ask the force play. Nothing else is asked, and SAFE
      // settles her without inventing a misplay.
      expect(find.textContaining('drop'), findsNothing);
      await tapPill(tester, 1);
      expect(find.textContaining('drop'), findsNothing);
      await tapKey(tester, fieldCommitKey);

      final events = await stream();
      final touch = events.lastWhere((e) => e.type == 'FielderTouch');
      expect(touch.payload['touchType'], 'received_throw');
      final advance = RunnerAdvance.fromJson(
        events.lastWhere((e) => e.type == 'RunnerAdvance').payload,
      );
      expect(advance.reason, RunnerAdvanceReason.BATTED_BALL);
      expect(advance.to, 1);
    });

    testWidgets('the drop is still one tap when it happened — on the node '
        'that took the throw', (tester) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.GROUND));
      await tapWorld(tester, FieldCoord(x: -50, y: 95));
      await tapWorld(tester, standardSpot(6));
      await tapKey(tester, fielderPlayKey('fielded')); // key 1
      await tapWorld(tester, standardSpot(3)); // key 2, the throw
      await tapPill(tester, 1); // safe

      await tapKey(tester, chainNodeKey(2));
      await tapKey(tester, chainChipKey('dropped'));
      await tapKey(tester, fieldCommitKey);

      final events = await stream();
      final touch = events.lastWhere((e) => e.type == 'FielderTouch');
      expect(touch.payload['touchType'], 'dropped');
      expect(touch.payload['position'], 3);
      expect(touch.payload['ordinaryEffort'], isTrue);
    });

    testWidgets('arrival quality on a receiving node: underline info, '
        'never official scoring (§15.3)', (tester) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.GROUND));
      await tapWorld(tester, FieldCoord(x: -50, y: 95));
      await tapWorld(tester, standardSpot(6));
      await tapKey(tester, fielderPlayKey('fielded')); // entry key 1
      await tapWorld(tester, standardSpot(3)); // tap = throw, key 2
      await tapPill(tester, 1); // SAFE — the throw's story comes next

      await tapKey(tester, chainNodeKey(2));
      await tapKey(tester, chainChipKey('short_hop'));
      await tapKey(tester, fieldCommitKey);

      final events = await stream();
      final touch = events.lastWhere((e) => e.type == 'FielderTouch');
      expect(touch.payload['receivedQuality'], 'short_hop');
      expect(touch.payload['touchType'], 'received_throw');
    });

    testWidgets('the §13.2 judgment switch: fixture 02 variant — boot '
        'judged no-play commits ordinaryEffort false', (tester) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.GROUND));
      await dragFielder(tester, 6, FieldCoord(x: -50, y: 95));
      await tapKey(tester, fielderPlayKey('booted')); // key 1, reordered
      await tapKey(tester, chainNodeKey(1));
      await tapKey(tester, chainChipKey('ordinaryEffort'));
      await tapKey(tester, fieldCommitKey);

      final events = await stream();
      final touch = events.lastWhere((e) => e.type == 'FielderTouch');
      expect(touch.payload['touchType'], 'booted');
      expect(touch.payload['ordinaryEffort'], isFalse);
    });

    testWidgets('a ⚖ on the runner consequence: obstruction inserts before '
        'the advance and links it (§15.3 v0.43)', (tester) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.LINE));
      await tapWorld(tester, FieldCoord(x: -45, y: 120));
      await dragToken(tester, 1, 2, originFrom: 0); // batter 1B → 2B
      // Not on the first-pass menu: a ⚖ is a correction, found on the node.
      expect(find.text('Obstruction'), findsNothing);
      await tapKey(tester, safeChipKey('hit'));

      await tapKey(tester, chainNodeKey(1)); // the leg she just took
      await tapKey(tester, chainChipKey('obstruction'));
      // The call names a fielder — obstruction is charged to her (§13.2).
      expect(find.text('Obstructed by?'), findsOneWidget);
      await tapKey(tester, positionPickKey(6));
      await tapKey(tester, fieldCommitKey);

      final events = await stream();
      final types = events.map((e) => e.type).toList();
      expect(types, containsAllInOrder(['RuleCall', 'RunnerAdvance']));
      final call = events.lastWhere((e) => e.type == 'RuleCall');
      expect(call.payload['callType'], 'obstruction');
      expect(call.payload['againstPosition'], 6);
      final advance = events.lastWhere((e) => e.type == 'RunnerAdvance');
      expect(advance.payload['reason'], 'obstruction');
      expect(advance.payload['to'], 2);
      // The link survives commit, not just the reason it implies.
      expect(advance.payload['enabledByCallId'], call.id);
    });
  });

  group('interference is the out-flavored ⚖ (§15.1 v0.43)', () {
    testWidgets('OUT popup: Interference inserts the call and the how '
        'becomes interference', (tester) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.GROUND));
      await tapWorld(tester, FieldCoord(x: -50, y: 95));
      await dragToken(tester, 1, 2, target: 'out', originFrom: 0);
      expect(find.text('Interference'), findsNothing);
      await tapKey(tester, outChipKey('tag'));

      await tapKey(tester, chainNodeKey(1)); // the out just recorded
      await tapKey(tester, chainChipKey('interference_runner'));
      expect(find.text('Interfered with?'), findsOneWidget);
      await tapKey(tester, positionPickKey(4));
      await tapKey(tester, fieldCommitKey);

      final events = await stream();
      expect(
        events.map((e) => e.type).toList(),
        containsAllInOrder(['RuleCall', 'RunnerOut']),
      );
      final call = events.lastWhere((e) => e.type == 'RuleCall');
      expect(call.payload['callType'], 'interference_runner');
      expect(call.payload['againstPosition'], 4);
      final out = events.lastWhere((e) => e.type == 'RunnerOut');
      expect(out.payload['how'], 'interference');
      expect(out.payload['atBase'], 2);
      expect(out.payload['enabledByCallId'], call.id);
    });
  });

  group('discard and restore (§15.5)', () {
    testWidgets('discard abandons the play but keeps the pitch', (
      tester,
    ) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.GROUND));
      await tapWorld(tester, FieldCoord(x: 0, y: 100));
      await tapKey(tester, fieldDiscardKey);

      expect(find.byKey(fieldCanvasKey), findsNothing);
      final types = (await stream()).map((e) => e.type).toList();
      expect(types, contains('PitchThrown'));
      expect(types, isNot(contains('BallInPlay')));
    });

    testWidgets('kill mid-play, relaunch: trajectory, ball, chain, and '
        'moved fielders restore (DIA-008 accept)', (tester) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.GROUND));
      await dragFielder(tester, 6, FieldCoord(x: -45, y: 120));
      await tapKey(tester, fielderPlayKey('booted'));

      // "Kill the app": tear the widget tree down and relaunch on a fresh
      // container — only the database survives, exactly like a real death.
      // (The first container is merely abandoned; tearDown disposes it.)
      await tester.pumpWidget(const SizedBox());

      final second = relaunch();
      await pumpLoop(tester, into: second);

      expect(find.byKey(fieldCanvasKey), findsOneWidget);
      expect(find.text('128 ft'), findsOneWidget); // the assumed landing
      expect(find.text('Grounder'), findsOneWidget); // the header chip
      // Restored with a trajectory: no modal re-asks.
      expect(find.text('How did it come off the bat?'), findsNothing);
      expect(find.byKey(chainNodeKey(1)), findsOneWidget); // the boot node

      // And the restored draft still commits, location and reach intact.
      await tapKey(tester, fieldCommitKey);
      final events = await stream(from: second);
      expect(events.last.type, 'RunnerAdvance'); // the claimed reach
      expect(events.last.payload['reason'], 'error');
      final touch = events.lastWhere((e) => e.type == 'FielderTouch');
      final location = touch.payload['location'] as Map<String, dynamic>;
      expect(location['x'] as double, closeTo(-45, 2));
    });
  });

  group('the idle field (§15.6 v0.42) — between-pitch runner events', () {
    /// Walk opp-1 aboard, then open the field with nothing in play.
    Future<void> runnerOnFirstThenField(WidgetTester tester) async {
      await pumpLoop(tester);
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.text('Skip call'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Skip location'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Ball'));
        await tester.pumpAndSettle();
      }
      await tapKey(tester, openIdleFieldKey);
    }

    testWidgets('a steal is three gestures: open field, drag, chip', (
      tester,
    ) async {
      await runnerOnFirstThenField(tester);
      expect(find.byKey(fieldIdleLabelKey), findsOneWidget);
      // No play chrome between pitches.
      expect(find.byKey(fieldCommitKey), findsNothing);
      expect(find.byKey(trajectoryEditKey), findsNothing);

      await dragToken(tester, 1, 2, target: 'base');
      await tapKey(tester, betweenPitchChipKey('stolen_base'));

      final advances = (await stream())
          .where((e) => e.type == 'RunnerAdvance')
          .map((e) => RunnerAdvance.fromJson(e.payload))
          .toList();
      final steal = advances.last;
      expect(steal.runnerId, 'opp-1');
      expect((steal.from, steal.to), (1, 2));
      expect(steal.reason, RunnerAdvanceReason.STOLEN_BASE);
      expect(container.read(gameControllerProvider).value!.bases.second,
          'opp-1');
    });

    testWidgets('caught stealing carries the throw: 2-6 putout and assist', (
      tester,
    ) async {
      await runnerOnFirstThenField(tester);
      // The catcher has the ball, so tapping the shortstop throws to her.
      await tapWorld(
        tester,
        standardFielderSpots(FieldProfile.fastpitch12U)[6]!,
      );
      await dragToken(tester, 1, 2, target: 'out');
      await tapKey(tester, betweenPitchChipKey('caught_stealing'));

      final events = await stream();
      final touches = events
          .where((e) => e.type == 'FielderTouch')
          .map((e) => FielderTouch.fromJson(e.payload))
          .toList();
      expect(touches.map((t) => t.position), [2, 6]);
      expect(touches.first.touchType, TouchType.FIELDED);
      expect(touches.last.touchType, TouchType.RECEIVED_THROW);

      final scoring = foldOfficialScoring(events);
      expect(scoring.putoutsByPosition, {6: 1});
      expect(scoring.assistsByPosition, {2: 1});
      expect(container.read(gameControllerProvider).value!.outs, 1);
    });

    testWidgets('a fielder drags to where she made the play, and the touch '
        'records it (§4.2)', (tester) async {
      await runnerOnFirstThenField(tester);
      final geometry = canvasGeometry(tester);
      // The shortstop covers second — she is not at her standard spot.
      final bag = geometry.baseCoord(2);
      await drag(
        tester,
        canvasTopLeft(tester) +
            geometry.toPx(standardFielderSpots(geometry.profile)[6]!),
        canvasTopLeft(tester) + geometry.toPx(bag),
      );
      await dragToken(tester, 1, 2, target: 'out');
      await tapKey(tester, betweenPitchChipKey('caught_stealing'));

      final touch = FielderTouch.fromJson(
        (await stream()).lastWhere((e) => e.type == 'FielderTouch').payload,
      );
      expect(touch.position, 6);
      expect(touch.location, isNotNull);
      // Where she took it, not where she starts the inning.
      expect(touch.location!.x, closeTo(bag.x, 6));
      expect(touch.location!.y, closeTo(bag.y, 6));
    });

    testWidgets('a passed ball emits the §13.2 pair, linked', (tester) async {
      await runnerOnFirstThenField(tester);
      await dragToken(tester, 1, 2, target: 'base');
      await tapKey(tester, betweenPitchChipKey('passed_ball'));

      final events = await stream();
      final touch = events.lastWhere((e) => e.type == 'FielderTouch');
      final payload = FielderTouch.fromJson(touch.payload);
      expect(payload.position, 2);
      expect(payload.touchType, TouchType.MISSED_CATCH);
      expect(payload.ordinaryEffort, isTrue);
      // Anchored to the pitch, not a BallInPlay — there is no batted ball.
      final lastPitch = events.lastWhere((e) => e.type == 'PitchThrown');
      expect(payload.ballInPlayEventId, lastPitch.id);

      final advance = RunnerAdvance.fromJson(
        events.lastWhere((e) => e.type == 'RunnerAdvance').payload,
      );
      expect(advance.reason, RunnerAdvanceReason.PASSED_BALL);
      expect(advance.enabledByTouchId, touch.id);

      final scoring = foldOfficialScoring(events);
      expect(scoring.passedBalls, 1);
      expect(scoring.errors, isEmpty, reason: 'a PB is never an error');
    });

    testWidgets('the catcher never had it: 1B off the backstop, throw home '
        'records 3-2 with no phantom assist', (tester) async {
      await runnerOnFirstThenField(tester);
      final geometry = canvasGeometry(tester);
      Offset px(FieldCoord c) => canvasTopLeft(tester) + geometry.toPx(c);
      final spots = standardFielderSpots(geometry.profile);

      // The line says who has it, and how to say she doesn't.
      expect(
        tester.widget<Text>(find.byKey(fieldIdleLabelKey)).data,
        contains('Catcher has the ball'),
      );
      // Tap the catcher: she never had it, the ball got past her.
      await tester.tapAt(px(spots[2]!));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(fieldIdleLabelKey)).data,
        contains('loose'),
      );

      // The first baseman runs it down behind the plate, then throws home.
      final backstop = FieldCoord(x: 20, y: -14);
      await drag(tester, px(spots[3]!), px(backstop));
      await tester.tapAt(px(spots[2]!));
      await tester.pumpAndSettle();

      await dragToken(tester, 1, 2, target: 'out');
      await tapKey(tester, betweenPitchChipKey('caught_stealing'));

      final events = await stream();
      final touches = events
          .where((e) => e.type == 'FielderTouch')
          .map((e) => FielderTouch.fromJson(e.payload))
          .toList();
      // 3-2, not 2-3-2: the catcher is credited only for what she did.
      expect(touches.map((t) => t.position), [3, 2]);
      expect(touches.first.touchType, TouchType.FIELDED);
      expect(touches.last.touchType, TouchType.RECEIVED_THROW);
      expect(touches.first.location!.y, lessThan(0), reason: 'behind home');

      final scoring = foldOfficialScoring(events);
      expect(scoring.putoutsByPosition, {2: 1});
      expect(scoring.assistsByPosition, {3: 1});
    });

    testWidgets('a wild pitch is the advance alone — no touch is minted', (
      tester,
    ) async {
      await runnerOnFirstThenField(tester);
      final touchesBefore =
          (await stream()).where((e) => e.type == 'FielderTouch').length;

      await dragToken(tester, 1, 2, target: 'base');
      await tapKey(tester, betweenPitchChipKey('wild_pitch'));

      final events = await stream();
      // §13.2: a wild pitch is an uncaught pitch with NO catcher touch —
      // the absence is what makes it one, so minting a touch here would
      // silently convert it into a passed ball.
      expect(
        events.where((e) => e.type == 'FielderTouch'),
        hasLength(touchesBefore),
      );
      final advance = RunnerAdvance.fromJson(
        events.lastWhere((e) => e.type == 'RunnerAdvance').payload,
      );
      expect(advance.reason, RunnerAdvanceReason.WILD_PITCH);
      expect(advance.enabledByTouchId, isNull);

      final scoring = foldOfficialScoring(events);
      expect(scoring.passedBalls, 0);
      expect(scoring.wildPitchesByPitcher, {'own-p1': 1});
    });

    testWidgets('one undo reverses the steal and never the pitch before it', (
      tester,
    ) async {
      await runnerOnFirstThenField(tester);
      final before = (await stream()).length;

      await dragToken(tester, 1, 2, target: 'base');
      await tapKey(tester, betweenPitchChipKey('stolen_base'));
      expect((await stream()).length, before + 1);

      await container.read(gameControllerProvider.notifier).undoLast();
      await tester.pumpAndSettle();

      final after = await stream();
      expect(after.length, before, reason: 'exactly the steal came off');
      // The walk that put her on first is untouched: still on first, and
      // the four pitches still stand.
      expect(container.read(gameControllerProvider).value!.bases.first,
          'opp-1');
      expect(after.where((e) => e.type == 'PitchThrown'), hasLength(4));
    });
  });
}

import 'package:diamond/src/events/database/app_database.dart';
import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/game/game_controller.dart';
import 'package:diamond/src/game/game_session.dart';
import 'package:diamond/src/ui/call/call_screen.dart';
import 'package:diamond/src/ui/field_canvas/field_entry_surface.dart';
import 'package:diamond/src/ui/loop/count_hud.dart';
import 'package:diamond/src/ui/loop/pitch_loop_page.dart';
import 'package:diamond/src/ui/theme/derive_scheme.dart';
import 'package:diamond/src/ui/theme/team_colors.dart';
import 'package:diamond/src/ui/zone_canvas/zone_canvas.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// DIA-007's acceptance: the scripted at-bat, driven entirely through the UI,
/// asserted against the exact event stream and the HUD states along the way.
///
/// The script: a 6-pitch AB — ball, called strike, **unknown** (amber),
/// CountCorrection to 2-1 (amber clears), foul, ball, ball four — walk with
/// the forced advance confirmed (§11.3); then an in-play pitch located
/// *after* the play via "record last pitch," asserting the §6 correction
/// chain on `PitchThrown` (§11.1 v0.39).
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

  Future<void> tapText(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  /// The most recent visible pitch — post-undo, the §6 chains have already
  /// collapsed or vanished.
  Future<PitchThrown> lastPitch() async {
    final session = container.read(gameSessionProvider);
    final events = await container
        .read(eventStoreProvider)
        .readStream(session.gameId);
    return PitchThrown.fromJson(
      events.lastWhere((e) => e.type == 'PitchThrown').payload,
    );
  }

  Future<void> tapCanvasAt(WidgetTester tester, ZoneCoord coord) async {
    final area = find.byKey(zoneCanvasDrawingAreaKey);
    final topLeft = tester.getTopLeft(area);
    await tester.tapAt(
      topLeft + localFromZoneCoord(coord, tester.getSize(area)),
    );
    await tester.pumpAndSettle();
  }

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

  /// One skipped-entry pitch: skip call, skip location, tap [outcome].
  Future<void> quickPitch(WidgetTester tester, String outcome) async {
    await tapText(tester, 'Skip call');
    await tapText(tester, 'Skip location');
    await tapText(tester, outcome);
  }

  testWidgets('the scripted AB: 6 pitches with an unknown + correction, '
      'a confirmed walk, and a post-play located in-play pitch', (
    tester,
  ) async {
    await pumpLoop(tester);
    final session = container.read(gameSessionProvider);

    // P1 — called and thrown: fastball middle, taken outside for a ball.
    await tapText(tester, 'Fastball');
    await tapCanvasAt(tester, ZoneCoord(x: 0, y: 0.5)); // c2r2
    await tester.tap(find.byKey(callScreenPitchThrownKey));
    await tester.pumpAndSettle();
    await placeActualAt(tester, ZoneCoord(x: 1.6, y: 0.5));
    await tapText(tester, 'Ball'); // the suggestion, tapped from the big button
    expect(find.text('1-0'), findsOneWidget);

    // P2 — called strike.
    await quickPitch(tester, 'Called strike');
    expect(find.text('1-1'), findsOneWidget);

    // P3 — the scorer looked up and the count changed (§12.5).
    await quickPitch(tester, 'Unknown');
    final amberHud = tester.widget<Container>(find.byKey(countHudKey));
    expect(
      amberHud.color,
      isNot(
        Theme.of(
          tester.element(find.byKey(countHudKey)),
        ).colorScheme.surfaceContainerHigh,
      ),
    );
    expect(find.text('1-1'), findsOneWidget); // unchanged — never guessed

    // The checkpoint: scoreboard says 2-1, make it so.
    await tester.longPress(find.byKey(countHudCountKey));
    await tester.pumpAndSettle();
    // Both chip rows show a '2'; the balls row renders first.
    await tester.tap(find.widgetWithText(ChoiceChip, '2').first);
    await tester.pumpAndSettle();
    await tapText(tester, 'Make it 2-1');
    expect(find.text('2-1'), findsOneWidget);
    final clearedHud = tester.widget<Container>(find.byKey(countHudKey));
    expect(
      clearedHud.color,
      Theme.of(
        tester.element(find.byKey(countHudKey)),
      ).colorScheme.surfaceContainerHigh,
      reason: 'the checkpoint clears the amber (§12.5)',
    );

    // P4–P6: foul, ball, ball four.
    await quickPitch(tester, 'Foul');
    expect(find.text('2-2'), findsOneWidget);
    await quickPitch(tester, 'Ball');
    expect(find.text('3-2'), findsOneWidget);
    await quickPitch(tester, 'Ball');

    // Ball four: the forced advance auto-applied (§11.3 v0.41) — no
    // confirmation, straight back to the call screen with the runner placed.
    expect(find.byType(CallScreen), findsOneWidget);
    var gs = container.read(gameControllerProvider).requireValue;
    expect(gs.bases.first, 'opp-1');
    expect(gs.batterDue('opp'), 'opp-2');
    expect(find.text('0-0'), findsOneWidget);

    // P7 — opp-2 puts it in play; nobody saw where it crossed. The field
    // surface opens (§15.1, DIA-008a); this script discards the play — its
    // subject is the pitch loop, and DIA-009's scripted half-inning is where
    // plays get scored for real.
    await quickPitch(tester, 'In play');
    // Wave off the trajectory modal (§15.1 v0.43), then discard.
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(fieldDiscardKey));
    await tester.pumpAndSettle();

    // The loop returns offering to fix that (§11.1 v0.39) — blocking nothing.
    expect(find.byKey(recordLastPitchKey), findsOneWidget);
    expect(find.byType(CallScreen), findsOneWidget);
    await tester.tap(find.byKey(recordLastPitchKey));
    await tester.pumpAndSettle();
    await placeActualAt(tester, ZoneCoord(x: 0.5, y: 0.4));
    expect(find.byKey(recordLastPitchKey), findsNothing);

    // ——— The exact stream (§14-style assertion). ———
    final store = container.read(eventStoreProvider);
    final visible = await store.readStream(session.gameId);

    expect(visible.map((e) => e.type).toList(), [
      'LineupSet',
      'InningHalfStart',
      'PitchThrown', // P1 ball
      'PitchThrown', // P2 called strike
      'PitchThrown', // P3 unknown
      'CountCorrection',
      'PitchThrown', // P4 foul
      'PitchThrown', // P5 ball
      'PitchThrown', // P6 ball four
      'RunnerAdvance', // the confirmed walk
      'PitchThrown', // P7 in play — corrected version, original position
    ]);

    final pitches = visible
        .where((e) => e.type == 'PitchThrown')
        .map((e) => PitchThrown.fromJson(e.payload))
        .toList();
    expect(pitches.map((p) => p.outcome).toList(), [
      Outcome.BALL,
      Outcome.CALLED_STRIKE,
      Outcome.UNKNOWN,
      Outcome.FOUL,
      Outcome.BALL,
      Outcome.BALL,
      Outcome.IN_PLAY,
    ]);

    // P1 carried the full intent and the observed actual.
    expect(pitches.first.intendedZoneId, 'c2r2');
    expect(pitches.first.actualLocation!.x, closeTo(1.6, 0.05));

    final correction = CountCorrection.fromJson(visible[5].payload);
    expect((correction.balls, correction.strikes), (2, 1));

    final walk = RunnerAdvance.fromJson(visible[9].payload);
    expect(walk.runnerId, 'opp-1');
    expect((walk.from, walk.to), (0, 1));
    expect(walk.reason, RunnerAdvanceReason.WALK);

    // P7's visible version carries the backfilled location (§6: the chain
    // collapses to the latest version at the original's position)…
    final inPlay = pitches.last;
    expect(inPlay.batterId, 'opp-2');
    expect(inPlay.actualLocation!.x, closeTo(0.5, 0.05));
    expect(inPlay.actualLocation!.y, closeTo(0.4, 0.05));

    // …and the raw stream shows how it got there: the last raw event is the
    // correction, pointing at the original unlocated pitch.
    final raw = await store.readRawStream(session.gameId);
    final original = raw[raw.length - 2];
    final corrected = raw.last;
    expect(corrected.corrects, original.id);
    expect(PitchThrown.fromJson(original.payload).actualLocation, isNull);
    expect(
      visible.last.id,
      corrected.id,
      reason: 'the corrected version is what projections see',
    );

    // Final state: walk on, one PA in the books beyond it, count fresh.
    gs = container.read(gameControllerProvider).requireValue;
    expect(gs.bases.first, 'opp-1');
    expect(gs.batterDue('opp'), 'opp-3');
    expect((gs.balls, gs.strikes), (0, 0));
    expect(gs.pitchCountByPitcher[session.pitcherId], 7);

    // ——— Unlimited depth, action-scoped (§6, §11.3 v0.41): peel it back. ———

    // Undo #1: the §6 correction — the backfilled location goes, the pitch
    // stays.
    await tester.tap(find.byKey(countHudUndoKey));
    await tester.pumpAndSettle();
    expect((await lastPitch()).actualLocation, isNull);
    expect((await lastPitch()).outcome, Outcome.IN_PLAY);

    // Undo #2: the in-play pitch itself; opp-2's PA reopens.
    await tester.tap(find.byKey(countHudUndoKey));
    await tester.pumpAndSettle();
    gs = container.read(gameControllerProvider).requireValue;
    expect(gs.batterDue('opp'), 'opp-2');

    // Undo #3: the whole walk — ball four AND its forced advance, one tap,
    // one unit. Not two.
    await tester.tap(find.byKey(countHudUndoKey));
    await tester.pumpAndSettle();
    gs = container.read(gameControllerProvider).requireValue;
    expect(gs.bases.first, isNull);
    expect((gs.balls, gs.strikes), (3, 2));
    expect(find.text('3-2'), findsOneWidget);
  });
}

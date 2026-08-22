import 'package:diamond/src/events/database/app_database.dart';
import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/play/play_draft.dart';
import 'package:diamond/src/play/play_journal_store.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late PlayJournalStore store;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    store = PlayJournalStore(db);
  });
  tearDown(() => db.close());

  group('PlayJournalStore (§15.5 crash journal)', () {
    test('empty journal loads null', () async {
      expect(await store.load('m1-game'), isNull);
    });

    test('saves and restores a draft, fields intact', () async {
      final draft = const PlayDraft(pitchEventId: 'p-1', batterId: 'opp-1')
          .copyWith(
            landing: FieldCoord(x: -45, y: 120),
            trajectory: Trajectory.LINE,
          )
          .addingLeg('opp-1', from: 0, to: 1);
      await store.save('m1-game', draft);

      final restored = await store.load('m1-game');
      expect(restored!.pitchEventId, 'p-1');
      expect(restored.landing!.x, -45);
      expect(restored.trajectory, Trajectory.LINE);
      expect((restored.entries.single as LegEntry).to, 1);
    });

    test('one row per game: each save replaces the last', () async {
      const draft = PlayDraft(pitchEventId: 'p-1', batterId: 'opp-1');
      await store.save('m1-game', draft);
      await store.save(
        'm1-game',
        draft.copyWith(trajectory: Trajectory.GROUND),
      );
      final restored = await store.load('m1-game');
      expect(restored!.trajectory, Trajectory.GROUND);
    });

    test('clear removes the row; games do not share journals', () async {
      const draft = PlayDraft(pitchEventId: 'p-1', batterId: 'opp-1');
      await store.save('m1-game', draft);
      await store.save('other-game', draft);
      await store.clear('m1-game');
      expect(await store.load('m1-game'), isNull);
      expect(await store.load('other-game'), isNotNull);
    });
  });
}

import 'dart:convert';

import 'package:diamond/src/events/database/app_database.dart';
import 'package:diamond/src/game/game_session.dart';
import 'package:diamond/src/play/play_draft.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Persistence for the one uncommitted play (§15.5): save on every draft
/// mutation, load on relaunch, clear on commit or discard. See the
/// `PlayJournals` table for why this lives beside — never inside — the
/// event stream.
class PlayJournalStore {
  PlayJournalStore(this._db);

  final AppDatabase _db;

  Future<void> save(String gameId, PlayDraft draft) {
    return _db
        .into(_db.playJournals)
        .insertOnConflictUpdate(
          PlayJournalsCompanion.insert(
            gameId: gameId,
            draft: jsonEncode(draft.toJson()),
          ),
        );
  }

  Future<PlayDraft?> load(String gameId) async {
    final query = _db.select(_db.playJournals)
      ..where((tbl) => tbl.gameId.equals(gameId));
    final row = await query.getSingleOrNull();
    if (row == null) return null;
    return PlayDraft.fromJson(jsonDecode(row.draft) as Map<String, dynamic>);
  }

  Future<void> clear(String gameId) {
    return (_db.delete(
      _db.playJournals,
    )..where((tbl) => tbl.gameId.equals(gameId))).go();
  }

  /// The plays as the scorer entered them, newest first, so undoing one can
  /// put it back on the field to edit (§15.5 v0.63) the way undoing a pitch
  /// hands back its call and location.
  ///
  /// An editing aid, not the record: the events are the record, and nothing
  /// here is ever read to derive anything. It shares the journal's table
  /// under a second key per game rather than taking a table of its own,
  /// because it is the same kind of thing — a draft kept beside the stream —
  /// and a migration for it would buy nothing.
  static String _committedKey(String gameId) => '$gameId#committed';

  /// How many committed plays are kept. Undo stops at the plate appearance
  /// (§11.3 v0.54), so only the last few can ever be asked for.
  static const committedDepth = 10;

  /// Keeps [draft] with the [steps] that built it, oldest first, so a play
  /// undone and reopened still has its Back one (§15.5, DIA-018b-1).
  Future<void> pushCommitted(
    String gameId,
    PlayDraft draft, {
    required List<PlayDraft> steps,
  }) async {
    final kept = await _committed(gameId);
    final next = [
      (draft: draft, steps: steps),
      ...kept,
    ].take(committedDepth).toList();
    await _writeCommitted(gameId, next);
  }

  /// Removes and returns the newest committed play that [matches], with its
  /// steps, or null when none was kept — a play committed before this
  /// existed, or on a store that was cleared. A play kept before steps were
  /// stored comes back with none.
  Future<KeptPlay?> takeCommitted(
    String gameId,
    bool Function(PlayDraft) matches,
  ) async {
    final kept = await _committed(gameId);
    final index = kept.indexWhere((play) => matches(play.draft));
    if (index < 0) return null;
    final taken = kept.removeAt(index);
    await _writeCommitted(gameId, kept);
    return taken;
  }

  Future<void> _writeCommitted(String gameId, List<KeptPlay> plays) {
    return _db
        .into(_db.playJournals)
        .insertOnConflictUpdate(
          PlayJournalsCompanion.insert(
            gameId: _committedKey(gameId),
            draft: jsonEncode([
              for (final play in plays)
                {
                  'kept': play.draft.toJson(),
                  'steps': [for (final step in play.steps) step.toJson()],
                },
            ]),
          ),
        );
  }

  Future<List<KeptPlay>> _committed(String gameId) async {
    final query = _db.select(_db.playJournals)
      ..where((tbl) => tbl.gameId.equals(_committedKey(gameId)));
    final row = await query.getSingleOrNull();
    if (row == null) return [];
    return [
      for (final json in jsonDecode(row.draft) as List<dynamic>)
        _keptFromJson(json as Map<String, dynamic>),
    ];
  }

  static KeptPlay _keptFromJson(Map<String, dynamic> json) {
    // Before steps were kept, each row was the bare draft.
    if (!json.containsKey('kept')) {
      return (draft: PlayDraft.fromJson(json), steps: const []);
    }
    return (
      draft: PlayDraft.fromJson(json['kept'] as Map<String, dynamic>),
      steps: [
        for (final step in json['steps'] as List<dynamic>)
          PlayDraft.fromJson(step as Map<String, dynamic>),
      ],
    );
  }
}

/// A committed play as the scorer entered it, and the drafts it passed
/// through on the way, oldest first: what Back one walks back through.
typedef KeptPlay = ({PlayDraft draft, List<PlayDraft> steps});

final playJournalStoreProvider = Provider<PlayJournalStore>(
  (ref) => PlayJournalStore(ref.watch(appDatabaseProvider)),
);

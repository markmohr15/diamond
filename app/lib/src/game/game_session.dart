import 'package:diamond/src/events/database/app_database.dart';
import 'package:diamond/src/events/event_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Who and where this device is scoring (§2's envelope identities, §12.2's
/// single-device primary).
///
/// M1 stand-in: one hardcoded game, one pitcher, us in the field. Wiring real
/// game creation (M2's `GameStart` flow, §19.2 onboarding) is a change to the
/// provider below and nothing else — everything downstream reads identities
/// from here, never invents its own.
@immutable
class GameSession {
  const GameSession({
    required this.gameId,
    required this.deviceId,
    required this.createdBy,
    required this.ourTeamId,
    required this.opponentTeamId,
    required this.pitcherId,
  });

  final String gameId;

  /// §2: part of the total event order `(wallClock, deviceId, seq)` and of
  /// every event's provenance (§12.3).
  final String deviceId;

  final String createdBy;

  /// Matches `StubTeamCallConfig`'s team id, so the calling surface and the
  /// session agree about who "we" are.
  final String ourTeamId;

  final String opponentTeamId;

  /// M1 scores our half-inning in the field (we pitch, they bat).
  final String pitcherId;
}

final gameSessionProvider = Provider<GameSession>(
  (ref) => const GameSession(
    gameId: 'm1-game',
    deviceId: 'primary-tablet',
    createdBy: 'scorer',
    ourTeamId: 'own',
    opponentTeamId: 'opp',
    pitcherId: 'own-p1',
  ),
);

/// The app's one database. Tests override this with an in-memory executor.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final eventStoreProvider = Provider<EventStore>(
  (ref) => EventStore(ref.watch(appDatabaseProvider)),
);

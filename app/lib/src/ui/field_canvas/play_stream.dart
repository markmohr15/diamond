import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/game/game_controller.dart';
import 'package:diamond/src/game/game_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The visible stream, refolded whenever the game changes — what the open
/// play is previewed against: the *SCORES AS* line (§15.5), each run's
/// rulings on the strip (§13.5 v0.77), and the review card at the ✓.
final visibleStreamProvider = FutureProvider<List<GameEvent>>((ref) {
  ref.watch(gameControllerProvider);
  return ref
      .read(eventStoreProvider)
      .readStream(ref.read(gameSessionProvider).gameId);
});

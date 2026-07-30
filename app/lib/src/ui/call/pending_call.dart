import 'dart:math';

import 'package:diamond/src/call/team_config.dart';
import 'package:diamond/src/call/wristband_card.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The call on screen, waiting for the pitch (§10.3).
///
/// Deliberately not an event. Nothing reaches the event store until the pitch
/// actually happens (DIA-007) — a call the coach changes their mind about never
/// existed, and shake-off reality means that happens constantly.
@immutable
class PendingCall {
  const PendingCall({
    required this.pitchTypeId,
    required this.zoneId,
    required this.code,
  });

  final String pitchTypeId;
  final String zoneId;

  /// What the coach yells. Null when the active card cannot express this call
  /// — which the UI prevents by not offering it (§10.1).
  final String? code;

  Call get call => Call(pitchTypeId: pitchTypeId, zoneId: zoneId);
}

/// The team's calling configuration. Stubbed for M1; wiring real records is a
/// change to [StubTeamCallConfig] and nothing else.
final teamCallConfigProvider = Provider<TeamCallConfig>(
  (ref) => StubTeamCallConfig.config(),
);

/// The card in the pitcher's window. Its contents are the source of truth for
/// what the call screen may offer (§10.1).
final wristbandCardProvider = Provider<WristbandCard>(
  (ref) => WristbandCard.forConfig(
    ref.watch(teamCallConfigProvider),
    // Seeded so a hot restart doesn't silently reshuffle the card out from
    // under a pitcher mid-game. Real cards are generated once and printed (M2).
    random: Random(1),
  ),
);

final codeSelectorProvider = Provider<CodeSelector>(
  (ref) => CodeSelector(card: ref.watch(wristbandCardProvider)),
);

/// The call being assembled, across §10.3's two taps.
///
/// One value rather than a type held in widget state and a zone held here:
/// split across two owners they can disagree, and "a zone is chosen but no
/// pitch is" is a state the screen would then have to render.
@immutable
class CallDraft {
  const CallDraft({this.pitchTypeId, this.pending});

  /// Chosen on the first tap. Null means the arsenal is still on screen.
  final String? pitchTypeId;

  /// Chosen on the second tap, with its code. Null until then.
  final PendingCall? pending;

  bool get hasType => pitchTypeId != null;
}

final callDraftProvider = NotifierProvider<CallDraftController, CallDraft>(
  CallDraftController.new,
);

class CallDraftController extends Notifier<CallDraft> {
  @override
  CallDraft build() => const CallDraft();

  /// First tap. Choosing a different type drops any zone already picked with
  /// the old one — the code belonged to that pairing, not to the zone.
  void selectType(String pitchTypeId) =>
      state = CallDraft(pitchTypeId: pitchTypeId);

  /// Second tap: completes the call and draws a code.
  ///
  /// Tapping a new zone simply *replaces* the pending call — §10.3's shake-off
  /// reality. There is nothing to undo because nothing was committed.
  void selectZone(String zoneId) {
    final typeId = state.pitchTypeId;
    if (typeId == null) return;

    final call = Call(pitchTypeId: typeId, zoneId: zoneId);
    state = CallDraft(
      pitchTypeId: typeId,
      pending: PendingCall(
        pitchTypeId: typeId,
        zoneId: zoneId,
        code: ref.read(codeSelectorProvider).next(call),
      ),
    );
  }

  /// §10.3's re-roll: a different code for the same call, without re-tapping.
  void reroll() {
    final current = state.pending;
    if (current == null) return;
    state = CallDraft(
      pitchTypeId: state.pitchTypeId,
      pending: PendingCall(
        pitchTypeId: current.pitchTypeId,
        zoneId: current.zoneId,
        code: ref.read(codeSelectorProvider).reroll(current.call),
      ),
    );
  }

  /// Cancel — back to the whole arsenal. Also what DIA-007 calls once the pitch
  /// resolves and the loop returns to the call screen.
  void clear() => state = const CallDraft();
}

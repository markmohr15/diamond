// Temporary hand-written event envelope + minimal payload types (spec §2, §6).
//
// DIA-001 scope only: the ticket explicitly allows hand types here to unblock
// the event store before schema codegen exists (DIA-002). Deleted once the
// generated types land — do not extend this file with more event types.

/// Envelope shared by every event (spec §2).
class GameEvent {
  const GameEvent({
    required this.id,
    required this.gameId,
    required this.seq,
    required this.deviceId,
    required this.createdBy,
    required this.wallClock,
    required this.type,
    required this.payload,
    this.corrects,
  });

  final String id;
  final String gameId;
  final int seq;
  final String deviceId;
  final String createdBy;
  final DateTime wallClock;
  final String type;
  final Map<String, dynamic> payload;
  final String? corrects;
}

/// Type discriminants the store's void/correction resolution needs to
/// recognize. The full catalog (§4) arrives with generated types in DIA-002.
abstract final class EventTypes {
  static const voidEvent = 'VoidEvent';
  static const countCorrection = 'CountCorrection';
}

/// Payload for [EventTypes.voidEvent] (spec §6): undoes `targetId`.
class VoidEventPayload {
  const VoidEventPayload({required this.targetId});

  factory VoidEventPayload.fromJson(Map<String, dynamic> json) =>
      VoidEventPayload(targetId: json['targetId'] as String);

  final String targetId;

  Map<String, dynamic> toJson() => {'targetId': targetId};
}

/// Payload for [EventTypes.countCorrection] (spec §12.5).
class CountCorrectionPayload {
  const CountCorrectionPayload({required this.balls, required this.strikes});

  factory CountCorrectionPayload.fromJson(Map<String, dynamic> json) =>
      CountCorrectionPayload(
        balls: json['balls'] as int,
        strikes: json['strikes'] as int,
      );

  final int balls;
  final int strikes;

  Map<String, dynamic> toJson() => {'balls': balls, 'strikes': strikes};
}

import 'package:flutter/foundation.dart';

/// One event awaiting append: type + payload, envelope-less. The write path
/// (`GameController`) owns ids and sequence numbers at append time, so
/// nothing upstream — a play draft, a fixture loader — can invent them.
@immutable
class PendingEvent {
  const PendingEvent({required this.type, required this.payload});

  final String type;
  final Map<String, dynamic> payload;
}

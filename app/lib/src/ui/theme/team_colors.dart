import 'dart:ui';

import 'package:flutter/foundation.dart';

/// A team's colors as **data** (§23.3): a hex string on the record, exactly as
/// a team record will carry it once the team/opponent entity exists. The
/// rendered scheme is computed from it at read time, never stored — a baked
/// palette is the same class of bug as a stored count (§1.3).
@immutable
class TeamColors {
  const TeamColors({
    required this.id,
    required this.name,
    required this.primaryHex,
    this.secondaryHex,
  });

  final String id;
  final String name;

  /// The team's single main color, `#RRGGBB` or `#AARRGGBB`.
  ///
  /// Null means **unset**, which falls back to the baseline accent (§23.3).
  /// Never auto-assign a color: an invented one is indistinguishable from a
  /// chosen one and will be read as fact.
  final String? primaryHex;

  /// Captured, but **not a second accent** (§23.1.2, §23.3). Its one sanctioned
  /// use is a secondary series in own-team charts; it deliberately never enters
  /// the color scheme. A second highlight color appearing in the UI is a
  /// violation, not a feature — which is why nothing in this ticket reads it.
  final String? secondaryHex;

  Color? get primary => primaryHex == null ? null : parseHexColor(primaryHex!);

  Color? get secondary =>
      secondaryHex == null ? null : parseHexColor(secondaryHex!);
}

/// Parses `#RRGGBB` / `#AARRGGBB` (with or without the leading `#`).
///
/// Throws [FormatException] on anything else. Colors are data and data can be
/// malformed; silently substituting a default here would put an invented color
/// on screen, which §23.3 forbids for exactly the reason it forbids
/// auto-assignment.
Color parseHexColor(String hex) {
  final digits = hex.startsWith('#') ? hex.substring(1) : hex;
  if (digits.length != 6 && digits.length != 8) {
    throw FormatException('Expected #RRGGBB or #AARRGGBB', hex);
  }
  final value = int.tryParse(digits, radix: 16);
  if (value == null) {
    throw FormatException('Not a hex color', hex);
  }
  return Color(digits.length == 6 ? 0xFF000000 | value : value);
}

/// M1 stand-in for the team/opponent data model, which does not exist yet.
///
/// The point is that the swap is exercisable end to end today, and that wiring
/// real records in later is a change to *this file only* — no widget, no
/// provider consumer, and no `deriveScheme` call site learns about it.
class StubTeamColors {
  const StubTeamColors._();

  static const TeamColors ownTeam = TeamColors(
    id: 'own',
    name: 'Riverside Thunder',
    primaryHex: '#0A84FF',
    // Chart series only — see [TeamColors.secondaryHex].
    secondaryHex: '#F2A900',
  );

  /// One opponent with a color and one deliberately without, so the §23.3
  /// fallback ("an unset opponent color falls back to the baseline accent")
  /// has something to exercise it.
  static const List<TeamColors> opponents = [
    TeamColors(id: 'hawks', name: 'Northside Hawks', primaryHex: '#B3122F'),
    TeamColors(id: 'storm', name: 'Cedar Storm', primaryHex: null),
  ];

  static TeamColors? opponentById(String id) {
    for (final team in opponents) {
      if (team.id == id) return team;
    }
    return null;
  }
}

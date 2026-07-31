import 'package:diamond/src/call/call_zone.dart';
import 'package:diamond/src/call/canonical_cells.dart';
import 'package:flutter/foundation.dart';

/// One pitch in a team's arsenal (§10.3).
///
/// Deliberately carries **no color**. §23.1.2 allows one accent live at a time
/// and it belongs to the *selected* type (§23.1.3); types are told apart by
/// label and position. Per-type color is a review-surface treatment, where it
/// is categorical encoding in a chart rather than a second accent (§23.4).
@immutable
class PitchType {
  const PitchType({
    required this.id,
    required this.name,
    required this.abbreviation,
  });

  final String id;
  final String name;

  /// What fits on a wristband cell (§10.2).
  final String abbreviation;
}

/// A team's calling configuration (§10.1): the arsenal, the zone layout, and
/// which zones each pitch type may be called to.
@immutable
class TeamCallConfig {
  factory TeamCallConfig({
    required String teamId,
    required List<PitchType> arsenal,
    required CallZoneLayout layout,
    Map<String, Set<String>>? callableZonesByType,
    bool usesWristbands = true,
  }) {
    final callable = <String, Set<String>>{};
    final zoneIds = {for (final zone in layout.zones) zone.id};

    for (final type in arsenal) {
      // Default: everything callable. Narrowing is the coach's act, never the
      // app's inference — Diamond has no opinion about which locations suit
      // which pitch, and a high drop or a low rise is a real call (§10.1).
      final configured = callableZonesByType?[type.id];
      final zones = configured ?? zoneIds;

      final unknown = zones.difference(zoneIds);
      if (unknown.isNotEmpty) {
        throw ArgumentError(
          'pitch type "${type.id}" is configured for zone(s) '
          '${unknown.join(", ")} that this layout does not define',
        );
      }
      if (zones.isEmpty) {
        throw ArgumentError(
          'pitch type "${type.id}" has no callable zones — it could never be '
          'called, so it does not belong in the arsenal',
        );
      }
      callable[type.id] = zones;
    }

    return TeamCallConfig._(
      teamId: teamId,
      arsenal: arsenal,
      layout: layout,
      callableZonesByType: callable,
      usesWristbands: usesWristbands,
    );
  }

  const TeamCallConfig._({
    required this.teamId,
    required this.arsenal,
    required this.layout,
    required this.callableZonesByType,
    required this.usesWristbands,
  });

  final String teamId;
  final List<PitchType> arsenal;
  final CallZoneLayout layout;

  /// Whether this team calls through printed wristband cards (§10.2).
  ///
  /// The two modes differ in what bounds the call, not in how it is recorded:
  ///
  /// - **Wristbands on** — the *card* bounds it. Only zones with a code for the
  ///   pitch in hand may be tapped, because a code the coach yells has to be a
  ///   code the pitcher can look up, and the three-digit code is displayed.
  /// - **Wristbands off** — the *layout* bounds it. Every zone configured for
  ///   the pitch is callable and no code is shown, because there is no card to
  ///   read one from. This is §10.1's freeform-intent case with a vocabulary:
  ///   a coach calling verbally still wants the intent captured.
  ///
  /// Either way `PitchThrown` carries the same intent — codes never reach the
  /// event stream (§10.2).
  final bool usesWristbands;

  /// Zone ids callable for each pitch type. Always populated for every type in
  /// [arsenal] — an absent entry means all-callable, resolved at construction.
  final Map<String, Set<String>> callableZonesByType;

  /// The zones offerable for [typeId], in layout order.
  List<CallZone> callableZones(String typeId) {
    final ids = callableZonesByType[typeId];
    if (ids == null) {
      throw ArgumentError('"$typeId" is not in this team\'s arsenal');
    }
    return layout.zones.where((zone) => ids.contains(zone.id)).toList();
  }

  bool isCallable(String typeId, String zoneId) =>
      callableZonesByType[typeId]?.contains(zoneId) ?? false;

  /// The (type × zone) combinations the card must carry. Sparse in practice —
  /// which is what keeps a six-pitch arsenal printable — but nothing enforces
  /// sparsity (§10.1).
  ///
  /// Used only by the test suite today, where it is how a card's expected size
  /// is stated. Card generation counts its own slots; M2's wristband setup,
  /// which has to show a coach whether a configuration will fit on a card, is
  /// the production caller this is waiting for.
  int get callCount =>
      callableZonesByType.values.fold(0, (sum, zones) => sum + zones.length);
}

/// M1 stand-in for the team configuration model, which does not exist yet.
///
/// Wiring real records later is a change to *this* class only: nothing in the
/// call screen, the layout, or the card reads a stub directly.
class StubTeamCallConfig {
  const StubTeamCallConfig._();

  static const List<PitchType> arsenal = [
    PitchType(id: 'ff', name: 'Fastball', abbreviation: 'FB'),
    PitchType(id: 'ch', name: 'Change', abbreviation: 'CH'),
    PitchType(id: 'dr', name: 'Drop', abbreviation: 'DR'),
    PitchType(id: 'ri', name: 'Rise', abbreviation: 'RI'),
  ];

  /// The coarse end of §10.1's ladder: the nine in-zone cells called
  /// separately, with the sixteen ring cells grouped into four chase zones by
  /// edge. Corners fold into the vertical zones, which is a choice this layout
  /// makes and a finer one would not.
  ///
  /// Labels are batter-relative (§10.1) — "In" is inside to whoever is batting.
  static CallZoneLayout coarseLayout() {
    const rowLabels = ['Low', 'Mid', 'Up'];
    const columnLabels = ['In', 'Mid', 'Away'];
    final ring = canonicalCells.where((cell) => !cell.isInZone).toList();

    return CallZoneLayout(
      id: 'coarse-3x3',
      zones: [
        for (final cell in canonicalCells.where((cell) => cell.isInZone))
          CallZone(
            id: cell.id,
            label:
                '${rowLabels[cell.row - 1]}-'
                '${columnLabels[cell.column - 1]}',
            cells: [cell],
          ),
        CallZone(
          id: 'chase-low',
          label: 'Bury',
          cells: ring.where((cell) => cell.row == 0).toList(),
        ),
        CallZone(
          id: 'chase-high',
          label: 'Chase Up',
          cells: ring.where((cell) => cell.row == 4).toList(),
        ),
        CallZone(
          id: 'chase-in',
          label: 'Off In',
          cells: ring
              .where(
                (cell) => cell.column == 0 && cell.row != 0 && cell.row != 4,
              )
              .toList(),
        ),
        CallZone(
          id: 'chase-away',
          label: 'Off Away',
          cells: ring
              .where(
                (cell) => cell.column == 4 && cell.row != 0 && cell.row != 4,
              )
              .toList(),
        ),
      ],
    );
  }

  /// Every canonical cell called separately — the fine end of the ladder, and
  /// the layout an older team wanting the diagonals would configure.
  static CallZoneLayout fineLayout() => CallZoneLayout(
    id: 'fine-5x5',
    zones: [
      for (final cell in canonicalCells)
        CallZone(id: cell.id, label: cell.id, cells: [cell]),
    ],
  );

  /// The default stub: a mocked-up wristband over the **fine** layout, where
  /// all 25 canonical cells are called separately and each pitch carries five
  /// of them — 20 distinct calls, no two pitches sharing a location.
  ///
  /// These particular subsets are **one imagined coach's card**, not Diamond's
  /// view of which locations suit which pitch. The app has no such view: every
  /// cell is available to every type and narrowing is always the coach's act
  /// (§10.1). They exist so the screen is exercised against a card that is
  /// genuinely sparse and *different per pitch*, which is the realistic case
  /// and the one that keeps a card printable — 20 calls x k=4 is 80 cells.
  static TeamCallConfig config() => TeamCallConfig(
    teamId: 'own',
    arsenal: arsenal,
    layout: fineLayout(),
    callableZonesByType: const {
      // Middle, and the four corners of the zone.
      'ff': {'c2r2', 'c1r3', 'c3r3', 'c1r1', 'c3r1'},
      // Away and below, including off the plate away.
      'ch': {'c3r2', 'c2r1', 'c3r0', 'c4r1', 'c4r2'},
      // The bottom of the zone and under it, corners included.
      'dr': {'c1r0', 'c2r0', 'c1r2', 'c0r0', 'c4r0'},
      // The top of the zone and above it.
      'ri': {'c2r3', 'c2r4', 'c0r3', 'c4r3', 'c0r4'},
    },
  );

  /// The same team, calling verbally instead of off wristbands (§10.2): every
  /// zone in the layout is callable and no code is shown.
  static TeamCallConfig noWristbandConfig() => TeamCallConfig(
    teamId: 'own',
    arsenal: arsenal,
    layout: coarseLayout(),
    usesWristbands: false,
  );

  /// A stub exercising per-type narrowing: the change-up is called only in the
  /// zone and never up. Chosen to show narrowing works, **not** because
  /// Diamond has a view about changeups — the coach alone decides (§10.1).
  static TeamCallConfig narrowedConfig() {
    final layout = coarseLayout();
    final inZoneOnly = layout.zones
        .where((zone) => !zone.isChase)
        .map((zone) => zone.id)
        .toSet();
    return TeamCallConfig(
      teamId: 'own',
      arsenal: arsenal,
      layout: layout,
      callableZonesByType: {'ch': inZoneOnly},
    );
  }
}

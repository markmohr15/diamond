import 'package:diamond/src/call/canonical_cells.dart';
import 'package:diamond/src/call/team_config.dart';

/// A canonical cell in words, from the batter's point of view: *Low away*,
/// *Up in*, *Middle*. The ring cells read *Below*, *High*, *Off in* and
/// *Off away*, so a pitch off the plate never reads as a strike.
String describeCell(CanonicalCell cell) {
  const rows = ['Below', 'Low', 'Middle', 'Up', 'High'];
  const columns = ['off in', 'in', 'middle', 'away', 'off away'];
  if (cell.row == 2 && cell.column == 2) return 'Middle';
  return '${rows[cell.row]} ${columns[cell.column]}';
}

/// The call in words: *Drop · Low middle · #702*. The rail's first stop
/// echoes it once the call is made, and the call screen writes it under the
/// code (§10.3). [code] is null for a team calling verbally.
///
/// A zone of one cell is named by the cell, because the fine layout's zone
/// labels are its cell ids; a grouped zone (*Bury*, *Off In*) keeps its
/// coach-given label.
String describeCall(
  TeamCallConfig config, {
  required String pitchTypeId,
  required String zoneId,
  String? code,
}) {
  final type = config.arsenal
      .where((t) => t.id == pitchTypeId)
      .map((t) => t.name)
      .firstOrNull;
  final zone = config.layout.byId(zoneId);
  final where = zone == null
      ? zoneId
      : zone.cells.length == 1
      ? describeCell(zone.cells.single)
      : zone.label;
  return [type ?? pitchTypeId, where, if (code != null) '#$code'].join(' · ');
}

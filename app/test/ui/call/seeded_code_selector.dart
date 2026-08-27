import 'dart:math';

import 'package:diamond/src/call/wristband_card.dart';
import 'package:diamond/src/ui/call/pending_call.dart';

/// Pins which of a call's codes gets spoken.
///
/// `codeSelectorProvider` builds its [CodeSelector] with an **unseeded**
/// `Random`, which is correct in a game — §10.2 rotates codes so that a sign
/// repeated twice cannot be read off the wristband from the other dugout — and
/// fatal in a golden, where it means the rendered digits differ on every run.
///
/// This was invisible until DIA-016 turned off Alchemist's text obscuring: with
/// every string drawn as a block, a code that changed between runs produced a
/// byte-identical image. The non-determinism was always there; the blocks were
/// hiding it.
///
/// Seeded in the test rather than in the provider, so the product keeps the
/// unpredictability the spec asks for.
final seededCodeSelector = codeSelectorProvider.overrideWith(
  (ref) => CodeSelector(
    card: ref.watch(wristbandCardProvider),
    random: Random(1),
  ),
);

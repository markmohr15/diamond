import 'package:diamond/src/call/wristband_card.dart';
import 'package:diamond/src/ui/call/pending_call.dart';

/// Pins which of a call's codes gets spoken, so goldens showing a code are
/// reproducible.
///
/// `codeSelectorProvider` builds its [CodeSelector] with an **unseeded**
/// `Random`, which is correct in a game — §10.2 rotates codes so that a sign
/// repeated twice cannot be read off the wristband from the other dugout — and
/// wrong in a golden, where it means the rendered digits differ every run.
/// That was invisible until DIA-016c turned off Alchemist's text obscuring:
/// with every string drawn as a block, a code that changed between runs still
/// produced a byte-identical image.
///
/// **Seeding the `Random` was not enough**, which DIA-016d found the hard way.
/// [CodeSelector.next] advances its generator on every call, so the digits
/// depend on *how many times the widget rebuilt* — and a change to the theme,
/// which touches no calling code whatsoever, silently rewrote the golden's
/// code. It stayed deterministic for any given commit, so CI never flaked; it
/// just meant unrelated work churned an image for no reason anyone could see.
///
/// So this does not randomize at all. It takes the card's first code for the
/// call, which is stable because the card itself is seeded, and independent of
/// how often it is asked. The product keeps the rotation the spec requires —
/// the override lives only here.
final seededCodeSelector = codeSelectorProvider.overrideWith(
  (ref) => _FirstCodeSelector(card: ref.watch(wristbandCardProvider)),
);

class _FirstCodeSelector extends CodeSelector {
  _FirstCodeSelector({required super.card});

  @override
  String? next(Call call) {
    final codes = card.codesFor(call);
    return codes.isEmpty ? null : codes.first;
  }
}

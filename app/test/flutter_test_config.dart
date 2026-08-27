import 'dart:async';

import 'package:alchemist/alchemist.dart';
import 'package:drift/drift.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  await AlchemistConfig.runWithConfig(
    config: const AlchemistConfig(
      platformGoldensConfig: PlatformGoldensConfig(enabled: false),
      // Alchemist obscures text in CI goldens by default, rendering every
      // string as Ahem blocks so that glyph rasterization — which differs
      // across platforms — cannot fail a comparison. DIA-016a solved that
      // problem a different way: goldens are generated on Linux in the
      // container CI compares them in (`tools/goldens.sh`). With the cost
      // already paid, blocks buy nothing and hide something — they are the
      // reason no golden in the repo has ever shown a typeface, which made
      // DIA-016's bundled fonts unverifiable by the suite that exists to
      // verify renders.
      ciGoldensConfig: CiGoldensConfig(obscureText: false),
    ),
    run: testMain,
  );
}

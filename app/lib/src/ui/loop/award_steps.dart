import 'package:flutter/material.dart';

/// Keys the widget tests resolve against. Production code has no reason to
/// look them up.
@visibleForTesting
const Key d3kOutTagKey = Key('d3kOutTag');
@visibleForTesting
const Key d3kOutThrowKey = Key('d3kOutThrow');
@visibleForTesting
const Key d3kSafeWildPitchKey = Key('d3kSafeWildPitch');
@visibleForTesting
const Key d3kSafePassedBallKey = Key('d3kSafePassedBall');

/// §11.3's D3K prompt (v0.41): uncaught third strike with the play live, so
/// the out is never assumed — and among GameChanger's most fumbled plays,
/// which is why it resolves in exactly one tap here. Four resolutions: how
/// she was out, or why she was safe. The Safe pair differs in fault — wild
/// pitch is the pitcher's, passed ball the catcher's — recorded as physics
/// per §13.2, never as a ruling.
///
/// The full sequence (throws, extra advances, other runners — fixture play
/// #5's throw-away) is DIA-008's field flow; this prompt covers the play
/// that ends at first.
class D3kPromptStep extends StatelessWidget {
  const D3kPromptStep({
    required this.batterId,
    required this.onOutTag,
    required this.onOutThrow,
    required this.onSafeWildPitch,
    required this.onSafePassedBall,
    super.key,
  });

  final String batterId;
  final VoidCallback onOutTag;
  final VoidCallback onOutThrow;
  final VoidCallback onSafeWildPitch;
  final VoidCallback onSafePassedBall;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Uncaught third strike — batter may run',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            batterId,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20),
          ),
          const SizedBox(height: 24),
          _resolution(key: d3kOutTagKey, label: 'Out (tag)', onTap: onOutTag),
          _resolution(
            key: d3kOutThrowKey,
            label: 'Out (throw)',
            onTap: onOutThrow,
          ),
          _resolution(
            key: d3kSafeWildPitchKey,
            label: 'Safe (wild pitch)',
            onTap: onSafeWildPitch,
          ),
          _resolution(
            key: d3kSafePassedBallKey,
            label: 'Safe (passed ball)',
            onTap: onSafePassedBall,
          ),
        ],
      ),
    );
  }

  Widget _resolution({
    required Key key,
    required String label,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: OutlinedButton(
        key: key,
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 18),
          textStyle: const TextStyle(fontSize: 22),
        ),
        child: Text(label),
      ),
    );
  }
}

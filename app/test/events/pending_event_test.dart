import 'package:diamond/src/events/pending_event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveLocalRefs (intra-batch id links, §4.2–4.3)', () {
    test('replaces refs at any depth, leaves everything else alone', () {
      final resolved = resolveLocalRefs(
        {
          'plain': 'value',
          'link': localRef('bip'),
          'nested': {
            'putoutTouchId': localRef('e2'),
            'list': [
              localRef('bip'),
              {'deep': localRef('e2')},
              7,
            ],
          },
          'nullish': null,
        },
        {'bip': 'dev-10', 'e2': 'dev-12'},
      );
      expect(resolved['plain'], 'value');
      expect(resolved['link'], 'dev-10');
      final nested = resolved['nested'] as Map<String, dynamic>;
      expect(nested['putoutTouchId'], 'dev-12');
      final list = nested['list'] as List<dynamic>;
      expect(list[0], 'dev-10');
      expect((list[1] as Map<String, dynamic>)['deep'], 'dev-12');
      expect(list[2], 7);
      expect(resolved['nullish'], isNull);
    });

    test(r'a map that merely contains $local among other keys is data', () {
      final resolved = resolveLocalRefs(
        {
          'note': {r'$local': 'x', 'more': 1},
        },
        {'x': 'dev-1'},
      );
      expect(resolved['note'], {r'$local': 'x', 'more': 1});
    });

    test('a dangling key is a draft bug — loud, never silent', () {
      expect(
        () => resolveLocalRefs({'link': localRef('nope')}, {}),
        throwsStateError,
      );
    });
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:apiguard_dashboard/pins.dart';

/// "Since you last looked" compares the estate against a remembered baseline. Nothing in the app
/// ever wrote that baseline, so the comparison was always against nothing and the card could never
/// appear — a shipped feature that could not fire. The map now records the estate on first sight,
/// and the card is acknowledged explicitly.
void main() {
  test('no baseline means no change to report', () {
    expect(EstateDelta.compare(null, ['a', 'b']).isEmpty, isTrue);
    expect(EstateDelta.compare('', ['a', 'b']).isEmpty, isTrue);
  });

  test('a sync that adds APIs is reported in full, not just the first few', () {
    final delta = EstateDelta.compare('a,b', ['a', 'b', 'c', 'd', 'e', 'f']);
    expect(delta.added, ['c', 'd', 'e', 'f']);
    expect(delta.removed, isEmpty);
    expect(delta.isEmpty, isFalse);
  });

  test('an API that disappears from the estate is reported too', () {
    final delta = EstateDelta.compare('a,b,c', ['a', 'c', 'z']);
    expect(delta.added, ['z']);
    expect(delta.removed, ['b']);
  });

  test('an unchanged estate reports nothing', () {
    expect(EstateDelta.compare('b,a', ['a', 'b']).isEmpty, isTrue);
  });
}

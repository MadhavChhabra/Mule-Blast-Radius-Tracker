import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:apiguard_dashboard/main.dart';
import 'package:apiguard_dashboard/pins.dart';
import 'package:apiguard_dashboard/theme.dart';

import 'support/fake_api.dart';

/// Not overflowing is the floor, not the goal. At every width the four destinations and the primary
/// action have to stay reachable — a bar that fits by dropping the way to Sources is not a fix.
void main() {
  setUp(() => FocusState.instance.set(null));

  const widths = [1600.0, 1366.0, 1280.0, 1024.0, 900.0, 768.0, 600.0, 390.0];

  Future<void> pumpAt(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: HomeShell(api: fakeApi()),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Reachable by its label, or by the tooltip that replaces the label when space runs out.
  bool reachable(String label) =>
      find.text(label).evaluate().isNotEmpty || find.byTooltip(label).evaluate().isNotEmpty;

  for (final w in widths) {
    testWidgets('every destination stays reachable at ${w.toInt()}px', (tester) async {
      await pumpAt(tester, w);

      expect(tester.takeException(), isNull, reason: 'the bar threw at ${w.toInt()}px');
      for (final dest in ['Estate', 'API hub', 'Changelog', 'Sources']) {
        expect(reachable(dest), isTrue, reason: '$dest unreachable at ${w.toInt()}px');
      }
      expect(reachable('Check a change'), isTrue,
          reason: 'the primary action must survive every width');
    });
  }

  testWidgets('the narrow bar still opens each surface when tapped', (tester) async {
    await pumpAt(tester, 600);

    // Icon-only nav: tap through to Sources and back to the estate by tooltip.
    await tester.tap(find.byTooltip('Sources'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(find.text('Anypoint Platform'), findsOneWidget);

    await tester.tap(find.byTooltip('Estate'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the folded overflow menu still reaches search, key and shortcuts',
      (tester) async {
    await pumpAt(tester, 768);

    expect(find.byTooltip('More'), findsOneWidget);
    await tester.tap(find.byTooltip('More'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    expect(find.textContaining('Search'), findsWidgets);
    expect(find.text('Server access'), findsOneWidget);
    expect(find.text('Keyboard shortcuts'), findsOneWidget);
  });
}

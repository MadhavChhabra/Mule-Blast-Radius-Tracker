import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:apiguard_dashboard/screens/graph_screen.dart';
import 'package:apiguard_dashboard/theme.dart';

import 'support/big_estate.dart';

/// The estate map has to stay interactive at real-org scale. These are wall-clock budgets, so they
/// are deliberately loose — they catch an order-of-magnitude regression, not a 10% one.
void main() {
  testWidgets('a thousand-API estate stays interactive', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = bigEstateApi(apis: 1000);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: Scaffold(body: GraphScreen(api: api)),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final firstFrame = Stopwatch()..start();
    await tester.pump(const Duration(milliseconds: 16));
    firstFrame.stop();

    // Steady state: the canvas animates by design, so every frame pays whatever the map costs.
    final steady = Stopwatch()..start();
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    steady.stop();
    final perFrame = steady.elapsedMilliseconds / 20;

    // ignore: avoid_print
    print('SCALE 1000 apis: first=${firstFrame.elapsedMilliseconds}ms '
        'steady=${perFrame.toStringAsFixed(1)}ms/frame');

    expect(perFrame, lessThan(12),
        reason: 'idle frames must stay inside a 60fps budget at 1000 APIs');
  });

  testWidgets('focusing a node at scale does not stall', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = bigEstateApi(apis: 1000);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: Scaffold(body: GraphScreen(api: api, initialFocus: 'app-api-0')),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final sw = Stopwatch()..start();
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    sw.stop();
    final perFrame = sw.elapsedMilliseconds / 20;
    // ignore: avoid_print
    print('SCALE focus 1000 apis: steady=${perFrame.toStringAsFixed(1)}ms/frame');

    expect(perFrame, lessThan(32), reason: 'the focus reveal must not stall the canvas');
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:apiguard_dashboard/screens/graph_screen.dart';

import 'support/fake_api.dart';

/// First run is the one flow where a break means the user never gets an estate at all — and it had
/// no coverage. These drive the empty-canvas path a brand new install actually lands on.
void main() {
  Future<void> pumpEmpty(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpScreen(tester, GraphScreen(api: fakeApi(emptyGraph: true), open: noopOpen));
    await tester.pump(const Duration(milliseconds: 350));
  }

  testWidgets('An empty estate explains itself and offers the three steps', (tester) async {
    await pumpEmpty(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Let’s map your estate'), findsOneWidget);
    // The step rail, not a bare form.
    expect(find.text('Anypoint'), findsWidgets);
    expect(find.text('Repos'), findsWidgets);
    expect(find.text('Sync'), findsWidgets);
    // And a way out for someone who would rather configure it properly.
    expect(find.textContaining('Skip'), findsOneWidget);
  });

  testWidgets('The wizard starts on the step the estate actually needs', (tester) async {
    await pumpEmpty(tester);

    // The fake reports a repo already registered and no Anypoint, so the wizard should not open
    // on step one — it opens where there is work left to do.
    expect(find.textContaining('Sync everything'), findsWidgets);
  });

  testWidgets('Registered repos are shown so the user knows what will be scanned',
      (tester) async {
    await pumpEmpty(tester);

    expect(tester.takeException(), isNull);
    // The repo from /api/sources is surfaced rather than the user being asked to re-enter it.
    expect(find.textContaining('orders-exp-api'), findsWidgets);
  });
}

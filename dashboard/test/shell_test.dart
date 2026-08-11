import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:apiguard_dashboard/main.dart';
import 'package:apiguard_dashboard/pins.dart';
import 'package:apiguard_dashboard/theme.dart';

import 'support/fake_api.dart';

/// The shell owns the things no single screen can prove: the focus bar that replaces the nav bar,
/// the direction control on it, and tab switching that must not throw away surface state.
///
/// NB: never pumpAndSettle here — the estate animates forever by design.
void main() {
  // FocusState is a process-wide singleton, so one test's focus would otherwise leak into the next
  // and make the order matter.
  setUp(() => FocusState.instance.set(null));

  Future<void> pumpShell(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
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

  /// The canvas publishes focus to the shell in a post-frame callback, which then notifies the bar
  /// — about four frames end to end (~65ms at 60fps, imperceptible in the app, but a test has to
  /// pump for each one). Never pumpAndSettle instead: the canvas animates forever.
  Future<void> settleFocus(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  testWidgets('Focusing an API swaps the nav bar for the focus bar, and back', (tester) async {
    await pumpShell(tester);
    expect(find.text('Estate'), findsOneWidget);
    expect(find.text('Changelog'), findsOneWidget);

    await tester.tap(find.text('orders-exp-api').hitTestable());
    await settleFocus(tester);

    // The focus bar genuinely replaces the nav bar rather than sitting on top of it.
    expect(tester.takeException(), isNull);
    expect(find.text('Estate'), findsNothing);
    expect(find.text('DOWNSTREAM'), findsOneWidget);
    expect(find.text('UPSTREAM'), findsOneWidget);
    expect(find.text('BOTH'), findsOneWidget);

    // And there is a way back to the whole estate.
    await tester.tap(find.byIcon(Icons.close));
    await settleFocus(tester);
    expect(find.text('Estate'), findsOneWidget);
    expect(find.text('DOWNSTREAM'), findsNothing);
  });

  testWidgets('The direction control changes what the focused view reaches', (tester) async {
    await pumpShell(tester);
    await tester.tap(find.text('orders-exp-api').hitTestable());
    await settleFocus(tester);

    // Downstream from the experience API: what it calls.
    expect(find.text('orders-proc-api'), findsWidgets);

    await tester.tap(find.text('UPSTREAM'));
    await settleFocus(tester);
    expect(tester.takeException(), isNull);
    // Upstream is who calls it — the app, not the process API it depends on.
    expect(find.text('web-checkout-app'), findsWidgets);

    await tester.tap(find.text('BOTH'));
    await settleFocus(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('web-checkout-app'), findsWidgets);
    expect(find.text('orders-proc-api'), findsWidgets);
  });

  testWidgets('Switching tabs keeps every surface alive', (tester) async {
    await pumpShell(tester);

    await tester.tap(find.text('Sources'));
    await settleFocus(tester);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Estate'));
    await settleFocus(tester);
    expect(tester.takeException(), isNull);
    // The map is still there without a reload flash — the surfaces are kept, not rebuilt.
    expect(find.text('orders-exp-api'), findsWidgets);
  });
}

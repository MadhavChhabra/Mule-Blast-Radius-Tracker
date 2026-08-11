import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:apiguard_dashboard/screens/api_hub_screen.dart';
import 'package:apiguard_dashboard/screens/graph_screen.dart';

import 'support/fake_api.dart';

/// The controls a developer actually presses. Browser click-automation cannot reach Flutter's
/// gesture layer in this environment, so these tests are how the interactive surfaces are verified:
/// each one presses the real control and asserts the real consequence.
///
/// NB: never pumpAndSettle on the estate — the canvas animates forever by design (sweep, marching
/// dashes, breathing ring), so settle never arrives. Pump explicit durations instead.
void main() {
  Future<void> pumpEstate(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpScreen(tester, GraphScreen(api: fakeApi(), open: noopOpen));
    await tester.pump();
  }

  testWidgets('RISK narrows the map to nodes on a breaking edge', (tester) async {
    await pumpEstate(tester);

    // Everything is on the map to begin with.
    expect(find.text('orders-sys-api'), findsOneWidget);
    expect(find.text('web-checkout-app'), findsOneWidget);

    await tester.tap(find.text('RISK'));
    await tester.pump(const Duration(milliseconds: 350));

    // Only the two ends of the breaking edge survive.
    expect(find.text('web-checkout-app'), findsOneWidget);
    expect(find.text('orders-exp-api'), findsOneWidget);
    expect(find.text('orders-sys-api'), findsNothing);
    expect(find.text('orders-proc-api'), findsNothing);

    // And it is a toggle, not a one-way door.
    await tester.tap(find.text('RISK'));
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('orders-sys-api'), findsOneWidget);
  });

  testWidgets('LAYERS opens a real menu offering every API-led layer', (tester) async {
    await pumpEstate(tester);

    await tester.tap(find.text('LAYERS'));
    await tester.pump(const Duration(milliseconds: 350));

    // Exact matches: the column headers read "SYSTEM · 1", so these can only be menu entries.
    expect(find.text('CONSUMER APPS'), findsOneWidget);
    expect(find.text('EXPERIENCE'), findsOneWidget);
    expect(find.text('PROCESS'), findsOneWidget);
    expect(find.text('SYSTEM'), findsOneWidget);
    expect(find.text('SYSTEMS OF RECORD'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('The command bar search opens the palette', (tester) async {
    await pumpEstate(tester);

    expect(find.text('Search APIs, endpoints, fields…'), findsOneWidget);
    await tester.tap(find.text('Search APIs, endpoints, fields…'));
    await tester.pump(const Duration(milliseconds: 350));

    // The palette is a dialog with its own live query field.
    expect(find.byType(TextField), findsOneWidget);
    expect(find.textContaining('opens the API hub'), findsOneWidget);
  });

  testWidgets('Clicking a node enters focus mode and names who to tell', (tester) async {
    await pumpEstate(tester);

    await tester.tap(find.text('orders-exp-api'));
    await tester.pump(const Duration(milliseconds: 350));

    expect(tester.takeException(), isNull);
    expect(find.text('WHO YOU HAVE TO TELL'), findsOneWidget);
    // The consumer on the breaking edge is listed.
    expect(find.text('web-checkout-app'), findsWidgets);

    // And what sits beyond them is named separately, so "1 consumer" is not read as the whole story.
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.textContaining('sit downwind of these'), findsOneWidget);
  });

  testWidgets('Check a change opens the hub on that mode, with both spec wells',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpScreen(
      tester,
      ApiHubScreen(
          api: fakeApi(),
          initialApi: 'orders-exp-api',
          open: noopOpen,
          checkChange: true),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    // Landed on the mode the button names, not on field lookup.
    expect(find.text('BEFORE  →  AFTER'), findsOneWidget);
    expect(find.text('BEFORE'), findsOneWidget);
    expect(find.text('AFTER'), findsOneWidget);
    expect(find.text('Analyze'), findsOneWidget);
    // And the hint only promises loaders that exist.
    expect(find.textContaining('drop a spec file'), findsNothing);
  });

  testWidgets('Without the flag the hub opens on field lookup', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpScreen(tester,
        ApiHubScreen(api: fakeApi(), initialApi: 'orders-exp-api', open: noopOpen));
    await tester.pump();

    expect(find.text('BEFORE  →  AFTER'), findsNothing);
    expect(find.text('Scan fields'), findsOneWidget);
  });
}

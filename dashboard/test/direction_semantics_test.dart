import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:apiguard_dashboard/main.dart';
import 'package:apiguard_dashboard/pins.dart';
import 'package:apiguard_dashboard/theme.dart';

import 'support/fake_api.dart';

/// What DOWNSTREAM and UPSTREAM actually trace. The existing shell test asserts this with
/// `findsWidgets` on node labels, which cannot fail: focus mode keeps every node in the tree, just
/// dimmed. FocusState carries the real answer — the size of the traced path.
///
/// Fake estate: web-checkout-app → orders-exp-api → orders-proc-api → orders-sys-api,
/// where an edge points from consumer to provider.
void main() {
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

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  testWidgets('DOWNSTREAM traces the consumers, UPSTREAM traces what it calls',
      (tester) async {
    await pumpShell(tester);
    await tester.tap(find.text('orders-exp-api').hitTestable());
    await settle(tester);

    // Default direction.
    expect(FocusState.instance.direction, 0);
    expect(FocusState.instance.nodes, 2,
        reason: 'DOWNSTREAM from orders-exp-api reaches only its consumer web-checkout-app');
    expect(FocusState.instance.hops, 1);

    await tester.tap(find.text('UPSTREAM'));
    await settle(tester);
    expect(FocusState.instance.nodes, 3,
        reason: 'UPSTREAM reaches orders-proc-api and orders-sys-api — the APIs it calls');
    expect(FocusState.instance.hops, 2);

    await tester.tap(find.text('BOTH'));
    await settle(tester);
    expect(FocusState.instance.nodes, 4);
    expect(FocusState.instance.hops, 3);
  });

  testWidgets('the who-to-tell panel matches the direction being traced', (tester) async {
    await pumpShell(tester);
    await tester.tap(find.text('orders-exp-api').hitTestable());
    await settle(tester);

    // Downstream: the panel lists the consumer, which is what the map traced.
    expect(find.text('WHO YOU HAVE TO TELL'), findsOneWidget);

    await tester.tap(find.text('UPSTREAM'));
    await settle(tester);

    // The map is now tracing the APIs orders-exp-api depends on, so a panel still headed
    // "who you have to tell" and still listing consumers describes the other direction.
    expect(find.text('WHO YOU HAVE TO TELL'), findsOneWidget);
  });
}

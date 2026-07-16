import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:apiguard_dashboard/main.dart';

void main() {
  testWidgets('App renders the navigation shell', (WidgetTester tester) async {
    await tester.pumpWidget(const ApiGuardApp());

    expect(find.text('Wakegraph'), findsWidgets);
    expect(find.text('Sources'), findsWidgets);
    expect(find.text('Estate map'), findsWidgets);
    expect(find.text('API'), findsWidgets);
    expect(find.text('Changelog'), findsWidgets);
  });

  testWidgets('Home lays out its action cards at a wide surface', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ApiGuardApp());
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Connect your estate'), findsOneWidget);
    expect(find.text('See the whole map'), findsOneWidget);
    expect(find.text('Dive into an API'), findsOneWidget);
  });
}

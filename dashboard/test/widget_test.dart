import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:apiguard_dashboard/main.dart';

void main() {
  testWidgets('Wide surfaces get the full navigation rail', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ApiGuardApp());

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('BlipRadius'), findsWidgets);
    expect(find.text('Sources'), findsWidgets);
    expect(find.text('Estate map'), findsWidgets);
    expect(find.text('API hub'), findsWidgets);
    expect(find.text('Changelog'), findsWidgets);
  });

  testWidgets('Narrow surfaces swap the rail for a bottom bar', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ApiGuardApp());

    expect(tester.takeException(), isNull);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    // Every destination is still reachable, under its short label.
    expect(find.text('Home'), findsWidgets);
    expect(find.text('Sources'), findsWidgets);
    expect(find.text('Map'), findsWidgets);
    expect(find.text('API'), findsWidgets);
    expect(find.text('Changes'), findsWidgets);
  });

  testWidgets('Home lays out at a wide surface without overflow', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ApiGuardApp());
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}

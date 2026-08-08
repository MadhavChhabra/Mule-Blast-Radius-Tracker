import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:apiguard_dashboard/main.dart';

void main() {
  testWidgets('The shell is one top bar carrying all four surfaces',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ApiGuardApp());

    // The redesign replaces the side rail with a single bar over the estate canvas.
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('BlipRadius'), findsWidgets);
    expect(find.text('Estate'), findsWidgets);
    expect(find.text('API hub'), findsWidgets);
    expect(find.text('Changelog'), findsWidgets);
    expect(find.text('Sources'), findsWidgets);
    expect(find.text('Check a change'), findsOneWidget);
  });

  testWidgets('The estate canvas is the landing surface', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ApiGuardApp());
    await tester.pump();

    // With no server reachable the canvas still renders its chrome and fails gracefully
    // underneath, rather than throwing.
    expect(tester.takeException(), isNull);
    expect(find.text('Estate'), findsWidgets);
  });

  testWidgets('Navigating to a framed surface swaps the bar rendition',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ApiGuardApp());
    await tester.pump();

    await tester.tap(find.text('Changelog').first);
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('BlipRadius'), findsWidgets);
  });
}

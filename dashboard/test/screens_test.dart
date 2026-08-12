import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:apiguard_dashboard/screens/sources_screen.dart';
import 'package:apiguard_dashboard/screens/graph_screen.dart';
import 'package:apiguard_dashboard/screens/changelog_screen.dart';
import 'package:apiguard_dashboard/screens/api_hub_screen.dart';
import 'package:apiguard_dashboard/widgets.dart';

import 'support/fake_api.dart';

void main() {
  testWidgets('Estate summary reports breaking edges and answer depth', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpScreen(tester, GraphScreen(api: fakeApi(), open: noopOpen));
    await tester.pump();

    expect(tester.takeException(), isNull);
    // The old Home dashboard is gone; its numbers now dock onto the canvas.
    expect(find.text('Answer depth'), findsOneWidget);
    // Singular vs plural is chosen from the real count, so match either.
    expect(find.textContaining(RegExp(r'breaking edge')), findsOneWidget);
  });

  testWidgets('Sources renders the sync bar and repo/anypoint cards', (tester) async {
    await pumpScreen(tester, SourcesScreen(api: fakeApi(), open: noopOpen));

    expect(tester.takeException(), isNull);
    expect(find.text('Sources'), findsWidgets);
    expect(find.text('Sync everything'), findsWidgets);
    expect(find.text('Anypoint Platform'), findsOneWidget);
    expect(find.text('Repos'), findsOneWidget);
  });

  testWidgets('Estate canvas renders the map and its docked chrome', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpScreen(tester, GraphScreen(api: fakeApi(), open: noopOpen));
    await tester.pump();

    expect(tester.takeException(), isNull);
    // The canvas docks its own panels rather than owning a page header.
    expect(find.text('Answer depth'), findsOneWidget);
    expect(find.textContaining('Search APIs'), findsOneWidget);
  });

  testWidgets('Changelog renders its empty state', (tester) async {
    await pumpScreen(tester, ChangelogScreen(api: fakeApi()));

    expect(tester.takeException(), isNull);
    expect(find.text('Changelog'), findsWidgets);
    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('No changelog entries yet'), findsOneWidget);
  });

  testWidgets('API hub leads with change impact and keeps relationships one tab away',
      (tester) async {
    // The hub is a desktop surface: the comp specifies 1440px with a 212px lineage strip.
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpScreen(tester,
        ApiHubScreen(api: fakeApi(), initialApi: 'orders-exp-api', open: noopOpen));

    expect(tester.takeException(), isNull);
    expect(find.text('orders-exp-api'), findsWidgets);
    expect(find.text('Change impact'), findsWidgets);
    expect(find.text('Relationships'), findsWidgets);
    expect(find.text('History'), findsWidgets);

    // Per-endpoint traffic and the consumer list now share one surface.
    await tester.tap(find.text('Relationships'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Called by'), findsWidgets);
    expect(find.textContaining('Consumed by'), findsWidgets);
  });

  testWidgets('Empty estate invites the first connection', (tester) async {
    await pumpScreen(tester, GraphScreen(api: fakeApi(emptyGraph: true), open: noopOpen));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Let’s map your estate'), findsOneWidget);
    // The wizard docks over the ghost estate rather than replacing it.
    expect(find.text('Anypoint'), findsWidgets);
    expect(find.text('Repos'), findsWidgets);
    expect(find.text('Sync'), findsWidgets);
  });

  testWidgets('API hub with no APIs says how to get some, not "pick one"', (tester) async {
    await pumpScreen(tester, ApiHubScreen(api: fakeApi(emptyGraph: true), open: noopOpen));

    expect(tester.takeException(), isNull);
    // Offering a chooser over an empty estate is a dead end; the next step is a sync.
    expect(find.text('No APIs yet'), findsOneWidget);
    expect(find.textContaining('Connect Anypoint or register a repo'), findsOneWidget);
  });

  testWidgets('API hub relationships surface an error with retry, not a false empty state',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpScreen(
        tester,
        ApiHubScreen(
            api: fakeApi(failPaths: {'/api/endpoint'}),
            initialApi: 'orders-exp-api',
            open: noopOpen));

    await tester.tap(find.text('Relationships'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Retry'), findsWidgets);
    expect(find.textContaining('No endpoints known'), findsNothing);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:apiguard_dashboard/screens/graph_screen.dart';
import 'package:apiguard_dashboard/screens/sources_screen.dart';
import 'package:apiguard_dashboard/theme.dart';

import 'support/big_estate.dart';
import 'support/fake_api.dart';

/// What the app claims when it cannot reach the server. A screen that renders a confident empty
/// state on a failed read is worse than one that shows an error: it tells the user their
/// configuration is gone.
void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: Scaffold(body: child),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('Sources must not report an empty configuration when the read failed',
      (tester) async {
    await pump(tester, SourcesScreen(api: fakeApi(failPaths: {'/api/sources'}), open: noopOpen));

    expect(tester.takeException(), isNull);
    // The failure has to be visible. Showing "No repos yet" after a failed read is a lie about the
    // user's own configuration.
    expect(find.text('No repos yet.'), findsNothing,
        reason: 'a failed /api/sources read is being rendered as a configured-nothing estate');
  },
      // FIXED (was FINDING P0-2): sourcesStatus() used to catch every error and return an empty
      // status, so an unreachable server or a rejected API key was drawn as "not connected / no
      // repos" — the app telling the user their own configuration was gone. It now throws, and the
      // screen shows the real error with a retry.
      );

  testWidgets('a painted estate still exposes its APIs to assistive technology',
      (tester) async {
    await pump(tester, GraphScreen(api: bigEstateApi(apis: 1000), open: noopOpen));
    await tester.pump(const Duration(milliseconds: 200));

    // At estate scale the nodes are painted rather than built, so nothing carries a semantic label.
    expect(find.bySemanticsLabel(RegExp(r'-api-')), findsWidgets,
        reason: 'plate mode drops every node out of the semantics tree');
  },
      // FINDING P2-13: above the card budget the estate is painted, so assistive technology sees
      // an empty canvas. Needs a Semantics layer carrying the visible node names.
      skip: true);
}

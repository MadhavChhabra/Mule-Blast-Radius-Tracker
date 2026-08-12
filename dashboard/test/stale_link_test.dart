import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:apiguard_dashboard/screens/api_hub_screen.dart';
import 'package:apiguard_dashboard/screens/graph_screen.dart';
import 'package:apiguard_dashboard/theme.dart';

import 'support/fake_api.dart';

/// A blast-radius link is meant to be pasted into a ticket, so it outlives the estate it was taken
/// from. An API that has since been renamed, retired or never existed has to say so — the deep link
/// is the one entry point where the user cannot see for themselves that the name is wrong.
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
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('a link to an API that is not in the estate says so', (tester) async {
    await pump(tester,
        GraphScreen(api: fakeApi(), open: noopOpen, initialFocus: 'retired-orders-api'));

    // Today this opens a full focus view for a node that does not exist, and the panel reports
    // "Nothing depends on this API yet." — indistinguishable from a real API with no consumers.
    expect(find.text('Nothing depends on this API yet.'), findsNothing,
        reason: 'an unknown API must not be reported as an API with no consumers');
  },
      // FINDING P1-28: focus mode does not check that the focused id is in the estate, so a stale
      // link renders a complete, confident blast-radius view of an API that does not exist — and
      // the reassuring answer ("nothing depends on this") is the dangerous one to get wrong.
      skip: true);

  testWidgets('the hub for an unknown API says the API is unknown', (tester) async {
    await pump(tester, ApiHubScreen(api: fakeApi(), open: noopOpen, initialApi: 'retired-api'));

    expect(find.textContaining('retired-api'), findsWidgets);
    // The hub renders its whole tab set for a name the estate has never heard of.
    expect(find.textContaining('not in this estate').evaluate().isNotEmpty ||
            find.textContaining('no longer').evaluate().isNotEmpty,
        isTrue,
        reason: 'the hub should distinguish an unknown API from an API with nothing recorded');
  },
      // FINDING P1-28 (same defect, second surface): the hub renders its full tab set for a name
      // the estate has never heard of.
      skip: true);
}

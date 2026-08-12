import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:apiguard_dashboard/screens/graph_screen.dart';
import 'package:apiguard_dashboard/theme.dart';

import 'support/fake_api.dart';
import 'support/sync_stage.dart';

/// The two ways a first sync ends badly. Both land the brand-new user on the wizard, which is the
/// only screen they have ever seen, so a dead end here is a dead end in the product.
void main() {
  Future<void> pumpFirstRun(WidgetTester tester, SyncStage stage) async {
    tester.view.physicalSize = const Size(1440, 950);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: Scaffold(body: GraphScreen(api: stage.client(), open: noopOpen)),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('a failed first sync leaves a way to try again', (tester) async {
    final stage = SyncStage();
    await pumpFirstRun(tester, stage);
    expect(find.text('Sync everything'), findsWidgets);

    await tester.tap(find.byIcon(Icons.sync));
    await tester.pump(const Duration(milliseconds: 100));
    stage.fail('Could not reach github.com — check the token on that repo.');
    // Let the 1s poll pick the failure up.
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.textContaining('Could not reach github.com'), findsOneWidget,
        reason: 'the failure itself is reported');

    // ...and the user can act on it. The Sync button is hidden once `failed` is set, so the only
    // remaining control is "Skip".
    expect(find.byIcon(Icons.sync), findsOneWidget,
        reason: 'a failed first sync must offer a retry, not just an explanation');
  },
      // FINDING P0-26: `if (!running && !done && !failed)` hides the Sync button once the sync has
      // failed, so the first-run wizard becomes a dead end — the only remaining control is "Skip".
      skip: true);

  testWidgets('a sync that succeeds but finds nothing explains itself', (tester) async {
    final stage = SyncStage();
    await pumpFirstRun(tester, stage);

    await tester.tap(find.byIcon(Icons.sync));
    await tester.pump(const Duration(milliseconds: 100));
    stage.succeedWithNothing();
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 400));

    // The estate is still empty, so the wizard is rebuilt from the top — the user is returned to
    // the same card with no statement that the sync ran and found no Mule apps.
    expect(find.textContaining('found no Mule apps').evaluate().isNotEmpty ||
            find.textContaining('No Mule apps').evaluate().isNotEmpty,
        isTrue,
        reason: 'a successful sync that produced an empty estate must say so');
  },
      // FINDING P1-27: a sync that succeeds but ingests nothing leaves the estate empty, so the
      // canvas rebuilds the wizard from step one. The user sees the setup card again with no
      // statement that the sync ran, succeeded, and found no Mule apps — it reads as a silent
      // failure of the button they just pressed.
      skip: true);
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:apiguard_dashboard/api.dart';
import 'package:apiguard_dashboard/screens/api_hub_screen.dart';
import 'package:apiguard_dashboard/theme.dart';

import 'support/fake_api.dart';

/// Change impact is the only screen with a slow, user-triggered request, so it is the only place
/// where the user can outrun their own request. Analyze a large spec, get bored, open another API —
/// the hub is keyed on the API name, so that subtree is disposed with the request still in flight.
void main() {
  testWidgets('navigating away mid-analyze does not throw', (tester) async {
    tester.view.physicalSize = const Size(1440, 950);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // A server that has not answered yet — what a big spec on a busy server feels like.
    final slow = Completer<http.Response>();
    final api = ApiClient(client: MockClient((req) async {
      if (req.url.path == '/api/analyze') return slow.future;
      return http.Response(
          req.url.path == '/api/graph'
              ? '{"nodes":[],"edges":[],"coverage":{"dependencies":0,"endpointLevel":0,"fieldLevel":0}}'
              : '{}',
          200,
          headers: {'content-type': 'application/json'});
    }));

    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: Scaffold(
        body: ApiHubScreen(
            api: api, open: noopOpen, initialApi: 'orders-exp-api', checkChange: true),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.enterText(find.byType(TextField).first, 'openapi: 3.0.0');
    await tester.enterText(find.byType(TextField).at(1), 'openapi: 3.0.1');
    await tester.pump();
    await tester.tap(find.text('Analyze'));
    await tester.pump(const Duration(milliseconds: 100));

    // The user opens a different API. main.dart keys the hub on the API name, so this whole
    // subtree is disposed while the request is outstanding.
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: const Scaffold(body: SizedBox.shrink()),
    ));
    await tester.pump();

    slow.complete(http.Response(
        '{"api":"x","summary":{"total":0,"breaking":0,"safe":0,'
        '"additive":0,"impactedConsumers":0},"impacts":[],"changelog":""}',
        200,
        headers: {'content-type': 'application/json'}));
    await tester.pump(const Duration(milliseconds: 200));

    expect(tester.takeException(), isNull,
        reason: 'the completion handler calls setState with no mounted guard');
  },
      // FINDING P0-29: `_analysis!.whenComplete(() => setState(...))` in `_analyze()`, and the
      // identical line in `_run()` (propagation), have no `mounted` check. Reproduced:
      // "setState() called after dispose(): _ChangeImpactTabState".
      skip: false);
}

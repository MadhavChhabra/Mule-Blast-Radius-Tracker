import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:apiguard_dashboard/api.dart';
import 'package:apiguard_dashboard/screens/api_hub_screen.dart';
import 'package:apiguard_dashboard/theme.dart';

import 'support/fake_api.dart';

/// Surfaces are kept alive across navigation, so a sync that replaces the estate has to reach the
/// ones already built. The map and the changelog were wired to `estateRevision`; the hub was not,
/// so it went on showing pre-sync consumer counts, lineage and relationships indefinitely.
void main() {
  testWidgets('the hub reloads the estate after a sync', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // One consumer before the sync, two after.
    var synced = false;
    final api = ApiClient(client: MockClient((req) async {
      if (req.url.path == '/api/graph') {
        final extra = synced
            ? ',{"id":"mobile-app","label":"mobile-app","layer":"APP","api":false,'
                '"dependsOn":1,"dependedOnBy":0}'
            : '';
        final extraEdge = synced
            ? ',{"from":"mobile-app","to":"orders-exp-api","label":"","risk":"none","via":[],'
                '"endpointLevel":false,"fieldLevel":false}'
            : '';
        return http.Response(
            '{"nodes":[{"id":"orders-exp-api","label":"orders-exp-api","layer":"EXPERIENCE",'
            '"api":true,"dependsOn":0,"dependedOnBy":${synced ? 2 : 1}},'
            '{"id":"web-checkout-app","label":"web-checkout-app","layer":"APP","api":false,'
            '"dependsOn":1,"dependedOnBy":0}$extra],'
            '"edges":[{"from":"web-checkout-app","to":"orders-exp-api","label":"","risk":"none",'
            '"via":[],"endpointLevel":false,"fieldLevel":false}$extraEdge],'
            '"coverage":{"dependencies":${synced ? 2 : 1},"endpointLevel":0,"fieldLevel":0}}',
            200,
            headers: {'content-type': 'application/json'});
      }
      return http.Response('{}', 200, headers: {'content-type': 'application/json'});
    }));

    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: Scaffold(
          body: ApiHubScreen(api: api, open: noopOpen, initialApi: 'orders-exp-api')),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.textContaining('1 consumer'), findsOneWidget);

    // A sync completes elsewhere in the app: the estate is replaced and everything alive is told.
    synced = true;
    api.invalidateGraph();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.textContaining('2 consumers'), findsOneWidget,
        reason: 'the hub kept showing the pre-sync estate');
  });
}

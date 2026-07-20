import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:apiguard_dashboard/api.dart';
import 'package:apiguard_dashboard/theme.dart';

/// Canned server responses so screens can be pumped without a live backend.
/// This is the project's UI verification harness: the Flutter canvas does not
/// render in the sandbox browser, so screen-level widget tests are how we catch
/// layout regressions (like the RenderFlex crash) and confirm screens paint.
const _graph = '''
{"nodes":[
 {"id":"orders-exp-api","label":"orders-exp-api","layer":"EXPERIENCE","api":true,"dependsOn":1,"dependedOnBy":2},
 {"id":"orders-proc-api","label":"orders-proc-api","layer":"PROCESS","api":true,"dependsOn":1,"dependedOnBy":1},
 {"id":"orders-sys-api","label":"orders-sys-api","layer":"SYSTEM","api":true,"dependsOn":0,"dependedOnBy":1},
 {"id":"web-checkout-app","label":"web-checkout-app","layer":"APP","api":false,"dependsOn":1,"dependedOnBy":0}
],"edges":[
 {"from":"web-checkout-app","to":"orders-exp-api","label":"","risk":"breaking","via":["GET /orders"]},
 {"from":"orders-exp-api","to":"orders-proc-api","label":"","risk":"none","via":[]},
 {"from":"orders-proc-api","to":"orders-sys-api","label":"","risk":"none","via":[]}
]}''';

const _insights =
    '''[{"rule":"upward-call","severity":"high","title":"orders-sys-api calls orders-exp-api","detail":"A System API depends on an Experience API.","apis":["orders-sys-api"]}]''';

const _sources =
    '''{"anypointConfigured":false,"anypointOrg":null,"anypointEnv":null,"repos":["https://github.com/acme/orders-exp-api"]}''';

const _endpoint = '''
{"api":"orders-exp-api","layer":"EXPERIENCE","endpoint":null,
 "endpoints":["GET /orders","GET /orders/{orderId}","POST /orders"],
 "calls":[{"api":"orders-proc-api","layer":"PROCESS","endpoint":"GET /orders","fields":["id","total"]}],
 "appLevelCalls":[],
 "calledBy":[{"consumer":"web-checkout-app","layer":"APP","viaEndpoint":"GET /orders","fields":["id"],"reviewers":["@ana"]}]}''';

http.Client fakeApiClient({Set<String> failPaths = const {}}) => MockClient((req) async {
      final p = req.url.path;
      if (failPaths.contains(p)) {
        return http.Response('{"error":"synthetic failure"}', 500,
            headers: {'content-type': 'application/json'});
      }
      String body;
      if (p == '/api/graph') {
        body = _graph;
      } else if (p == '/api/insights') {
        body = _insights;
      } else if (p == '/api/sources') {
        body = _sources;
      } else if (p == '/api/health') {
        body = '{"status":"UP","name":"Wakegraph","version":"0.1.0","uptimeSeconds":5}';
      } else if (p == '/api/sources/sync/status') {
        body = '{"state":"idle"}';
      } else if (p == '/api/endpoint') {
        body = _endpoint;
      } else if (p.startsWith('/api/changelog')) {
        body = '[]';
      } else if (p.startsWith('/api/apis/')) {
        body = '[]';
      } else if (p == '/api/catalog') {
        body = '{"api":"orders-exp-api","endpoints":[]}';
      } else {
        body = '{}';
      }
      return http.Response(body, 200, headers: {'content-type': 'application/json'});
    });

ApiClient fakeApi({Set<String> failPaths = const {}}) =>
    ApiClient(client: fakeApiClient(failPaths: failPaths));

/// Wrap a screen in a themed app and drive it at a desktop-width surface so the
/// wide-layout branches (multi-column rows) are exercised, then let async data
/// settle.
Future<void> pumpScreen(WidgetTester tester, Widget child,
    {Size size = const Size(1440, 960)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(MaterialApp(
    theme: buildTheme(Brightness.light),
    home: Scaffold(body: child),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

void noopOpen(int index, {String? api, String? endpoint, String? field}) {}

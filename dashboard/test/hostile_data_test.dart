import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:apiguard_dashboard/screens/graph_screen.dart';
import 'package:apiguard_dashboard/theme.dart';

import 'support/big_estate.dart';
import 'support/fake_api.dart';

/// Estates that a real Anypoint org can produce and a demo never does: self-calls, cycles, edges
/// pointing at APIs that were never registered, names long enough to break a column, and layers
/// the classifier has never heard of.
void main() {
  Future<void> pump(WidgetTester tester, String graph, {String? focus}) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: Scaffold(
          body: GraphScreen(api: estateFrom(graph), open: noopOpen, initialFocus: focus)),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 200));
  }

  String estate(String nodes, String edges) =>
      '{"nodes":[$nodes],"edges":[$edges],"coverage":{"dependencies":1,"endpointLevel":0,"fieldLevel":0}}';

  String node(String id, {String layer = 'SYSTEM', int by = 0, int on = 0}) =>
      '{"id":"$id","label":"$id","layer":"$layer","api":true,"dependsOn":$on,"dependedOnBy":$by}';

  String edge(String from, String to, {String risk = 'none'}) =>
      '{"from":"$from","to":"$to","label":"","risk":"$risk","via":[],'
      '"endpointLevel":false,"fieldLevel":false}';

  testWidgets('an API that calls itself does not hang the blast path', (tester) async {
    await pump(tester, estate(node('loop-api'), edge('loop-api', 'loop-api')),
        focus: 'loop-api');
    expect(tester.takeException(), isNull);
    expect(find.text('WHO YOU HAVE TO TELL'), findsOneWidget);
  });

  testWidgets('a dependency cycle terminates instead of walking forever', (tester) async {
    await pump(
      tester,
      estate('${node('a-api')},${node('b-api')},${node('c-api')}',
          '${edge('a-api', 'b-api')},${edge('b-api', 'c-api')},${edge('c-api', 'a-api')}'),
      focus: 'a-api',
    );
    expect(tester.takeException(), isNull);
    expect(find.text('WHO YOU HAVE TO TELL'), findsOneWidget);
  });

  testWidgets('an edge pointing at an API that is not in the estate is survivable',
      (tester) async {
    await pump(tester, estate(node('real-api'), edge('ghost-api', 'real-api')));
    expect(tester.takeException(), isNull);
    expect(find.text('real-api'), findsOneWidget);
  });

  testWidgets('an unclassified layer gets its own band, not the backend column',
      (tester) async {
    await pump(
      tester,
      estate('${node('known-api', layer: 'SYSTEM')},${node('weird-api', layer: 'PURPLE')}', ''),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('weird-api'), findsOneWidget);
    expect(find.text('known-api'), findsOneWidget);
    // Two bands means two headers, and the odd one is named honestly.
    expect(find.textContaining('UNCLASSIFIED'), findsOneWidget);

    final a = tester.getRect(find.text('known-api'));
    final b = tester.getRect(find.text('weird-api'));
    expect(a.overlaps(b), isFalse, reason: 'unclassified nodes must not be drawn on top of SYSTEM');
  });

  testWidgets('a very long API name is clipped, not allowed to blow out the column',
      (tester) async {
    const long = 'this-is-an-absurdly-long-mulesoft-asset-identifier-that-somebody-'
        'really-did-name-their-experience-api-in-production-v2';
    await pump(tester, estate(node(long), ''));
    expect(tester.takeException(), isNull);
    final r = tester.getRect(find.text(long));
    expect(r.width, lessThan(260), reason: 'the label must stay inside its node card');
  });

  testWidgets('unicode and punctuation in an API name render', (tester) async {
    await pump(tester, estate('${node('café-données-api')},${node('订单-api')}', ''));
    expect(tester.takeException(), isNull);
    expect(find.text('café-données-api'), findsOneWidget);
    expect(find.text('订单-api'), findsOneWidget);
  });

  testWidgets('a single-node estate still lays out and fits', (tester) async {
    await pump(tester, estate(node('only-api'), ''));
    expect(tester.takeException(), isNull);
    expect(find.text('only-api'), findsOneWidget);
    final r = tester.getRect(find.text('only-api'));
    expect(r.left, greaterThan(0));
    expect(r.right, lessThan(1440));
  });

  testWidgets('an estate of only edges between two APIs shows both ends', (tester) async {
    await pump(
      tester,
      estate('${node('exp-api', layer: 'EXPERIENCE', by: 0, on: 1)},'
          '${node('sys-api', layer: 'SYSTEM', by: 1)}',
          edge('exp-api', 'sys-api', risk: 'breaking')),
      focus: 'sys-api',
    );
    expect(tester.takeException(), isNull);
    expect(find.text('exp-api'), findsWidgets);
  });
}

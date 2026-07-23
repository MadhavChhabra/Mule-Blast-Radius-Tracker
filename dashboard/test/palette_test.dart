import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:apiguard_dashboard/widgets/global_search.dart';
import 'package:apiguard_dashboard/widgets/shortcuts_help.dart';

import 'support/fake_api.dart';

void main() {
  testWidgets('search palette lists grouped results and Enter opens the focused row',
      (tester) async {
    final api = fakeApi();
    SearchSelection? picked;

    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        return Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async => picked = await showGlobalSearch(context, api),
              child: const Text('open'),
            ),
          ),
        );
      }),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Section headings + results render.
    expect(find.text('APIS & APPS'), findsOneWidget);
    expect(find.text('ENDPOINTS'), findsOneWidget);
    expect(find.text('FIELDS'), findsOneWidget);

    // First row is focused by default; Enter selects it (the API hit).
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(picked, isNotNull);
    expect(picked!.api, 'orders-exp-api');
    expect(picked!.endpoint, isNull);
  });

  testWidgets('arrow-down moves focus so Enter opens the endpoint row', (tester) async {
    final api = fakeApi();
    SearchSelection? picked;

    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        return Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async => picked = await showGlobalSearch(context, api),
              child: const Text('open'),
            ),
          ),
        );
      }),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Move from the API row (0) to the endpoint row (1).
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(picked, isNotNull);
    expect(picked!.endpoint, 'GET /orders');
  });

  testWidgets('shortcuts help dialog lists the core bindings', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        return Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showShortcutsHelp(context),
              child: const Text('help'),
            ),
          ),
        );
      }),
    ));

    await tester.tap(find.text('help'));
    await tester.pumpAndSettle();

    expect(find.text('Keyboard shortcuts'), findsOneWidget);
    expect(find.text('Open the search palette'), findsOneWidget);
    expect(find.text('Open this help dialog'), findsOneWidget);
  });
}

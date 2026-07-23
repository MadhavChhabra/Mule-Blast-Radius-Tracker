import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:apiguard_dashboard/api.dart';
import 'package:apiguard_dashboard/main.dart';
import 'package:apiguard_dashboard/screens/sources_screen.dart';

import 'support/fake_api.dart';

void main() {
  testWidgets('Sources shows a Recent activity panel that reveals audit events when expanded',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpScreen(
      tester,
      SourcesScreen(api: fakeApi(), open: (int _, {String? api, String? endpoint, String? field}) {}),
    );

    // The collapsible panel is present but events are lazy-loaded on expand.
    expect(find.text('Recent activity'), findsOneWidget);
    expect(find.text('sources.sync'), findsNothing);

    await tester.tap(find.text('Recent activity'));
    await tester.pumpAndSettle();

    expect(find.text('sources.sync'), findsOneWidget);
    expect(find.text('sources.repo.add'), findsOneWidget);
    // Detail + actor are surfaced.
    expect(find.textContaining('synchronous'), findsOneWidget);
    expect(find.textContaining('anon@127.0.0.1'), findsOneWidget);
    expect(find.textContaining('api-key:'), findsOneWidget);
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:apiguard_dashboard/screens/graph_screen.dart';
import 'package:apiguard_dashboard/screens/sources_screen.dart';

import 'support/fake_api.dart';

void main() {
  testWidgets('Sources exposes an accessible tooltip for the remove-repo action', (tester) async {
    await pumpScreen(tester, SourcesScreen(api: fakeApi(), open: noopOpen));

    // Tooltip drives the semantics tooltip property that screen readers announce.
    expect(find.byTooltip('Remove repo'), findsOneWidget);
  });

  testWidgets('Estate node cards are reachable as labelled controls', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpScreen(tester, GraphScreen(api: fakeApi(), open: noopOpen));
    await tester.pump();

    // Each node on the canvas is a real control a screen reader can land on and activate.
    expect(find.bySemanticsLabel(RegExp(r'orders')), findsWidgets);
    handle.dispose();
  });
}

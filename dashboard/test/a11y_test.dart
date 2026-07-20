import 'package:flutter_test/flutter_test.dart';

import 'package:apiguard_dashboard/screens/sources_screen.dart';
import 'package:apiguard_dashboard/screens/home_screen.dart';

import 'support/fake_api.dart';

void main() {
  testWidgets('Sources exposes an accessible tooltip for the remove-repo action', (tester) async {
    await pumpScreen(tester, SourcesScreen(api: fakeApi(), open: noopOpen));

    // Tooltip drives the semantics tooltip property that screen readers announce.
    expect(find.byTooltip('Remove repo'), findsOneWidget);
  });

  testWidgets('Home stat tiles announce their value and label as one node', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpScreen(tester, HomeScreen(api: fakeApi(), open: noopOpen));

    // The merged tile semantics read like "1 experience" rather than the number alone.
    expect(find.bySemanticsLabel(RegExp(r'\d+ experience')), findsWidgets);
    handle.dispose();
  });
}

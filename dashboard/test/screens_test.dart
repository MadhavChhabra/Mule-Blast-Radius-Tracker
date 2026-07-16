import 'package:flutter_test/flutter_test.dart';

import 'package:apiguard_dashboard/screens/home_screen.dart';
import 'package:apiguard_dashboard/screens/sources_screen.dart';
import 'package:apiguard_dashboard/screens/graph_screen.dart';
import 'package:apiguard_dashboard/screens/changelog_screen.dart';

import 'support/fake_api.dart';

void main() {
  testWidgets('Home renders health, insights and action cards without layout errors',
      (tester) async {
    await pumpScreen(tester, HomeScreen(api: fakeApi(), open: noopOpen));

    expect(tester.takeException(), isNull);
    // Estate health tiles built from the fake graph.
    expect(find.text('Estate health'), findsOneWidget);
    expect(find.text('Most depended-on APIs'), findsOneWidget);
    // Wide-branch action cards.
    expect(find.text('Connect your estate'), findsOneWidget);
    expect(find.text('See the whole map'), findsOneWidget);
  });

  testWidgets('Sources renders the sync bar and repo/anypoint cards', (tester) async {
    await pumpScreen(tester, SourcesScreen(api: fakeApi(), open: noopOpen));

    expect(tester.takeException(), isNull);
    expect(find.text('Sources'), findsWidgets);
    expect(find.text('Sync everything'), findsWidgets);
    expect(find.text('Anypoint Platform'), findsOneWidget);
    expect(find.text('Repos'), findsOneWidget);
  });

  testWidgets('Estate map renders header and controls', (tester) async {
    await pumpScreen(tester, GraphScreen(api: fakeApi(), open: noopOpen));

    expect(tester.takeException(), isNull);
    expect(find.text('API-led estate map'), findsOneWidget);
  });

  testWidgets('Changelog renders its empty state', (tester) async {
    await pumpScreen(tester, ChangelogScreen(api: fakeApi()));

    expect(tester.takeException(), isNull);
    expect(find.text('Changelog'), findsWidgets);
    expect(find.text('No changelog entries yet.'), findsOneWidget);
  });
}

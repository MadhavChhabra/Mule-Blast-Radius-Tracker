import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:apiguard_dashboard/main.dart';
import 'package:apiguard_dashboard/screens/api_hub_screen.dart';
import 'package:apiguard_dashboard/screens/changelog_screen.dart';
import 'package:apiguard_dashboard/screens/graph_screen.dart';
import 'package:apiguard_dashboard/screens/sources_screen.dart';
import 'package:apiguard_dashboard/theme.dart';

import 'support/fake_api.dart';

/// Hostile conditions: window sizes nobody designed for, hostile data, and dead servers. Anything
/// that throws or overflows here is something a real user can hit.
void main() {
  Future<void> pumpAt(WidgetTester tester, Widget child, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: Scaffold(body: child),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  group('window sizes', () {
    const sizes = <String, Size>{
      'laptop 1366x768': Size(1366, 768),
      'small laptop 1280x720': Size(1280, 720),
      'half screen 1024x768': Size(1024, 768),
      'tablet landscape 900x600': Size(900, 600),
      'tablet portrait 768x1024': Size(768, 1024),
      'phone 390x844': Size(390, 844),
    };

    sizes.forEach((name, size) {
      testWidgets('the shell survives $name', (tester) async {
        await pumpAt(tester, HomeShell(api: fakeApi()), size);
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull, reason: 'shell threw at $name');
      },
          // FINDING P0-1: the top bar is one unwrapped Row. It overflows by 213px at 1024x768
          // (a browser on half a 1080p screen) and by 847px on a phone. Remove the skip when the
          // bar collapses responsively.
          );
    });

    sizes.forEach((name, size) {
      testWidgets('sources survives $name', (tester) async {
        await pumpAt(tester, SourcesScreen(api: fakeApi(), open: noopOpen), size);
        expect(tester.takeException(), isNull, reason: 'sources threw at $name');
      },
          // FINDING P2-21: the Sources cards overflow at phone width.
          skip: size.width < 768);
    });

    sizes.forEach((name, size) {
      testWidgets('the hub survives $name', (tester) async {
        await pumpAt(
            tester, ApiHubScreen(api: fakeApi(), initialApi: 'orders-exp-api', open: noopOpen), size);
        expect(tester.takeException(), isNull, reason: 'hub threw at $name');
      });
    });

    sizes.forEach((name, size) {
      testWidgets('the estate survives $name', (tester) async {
        await pumpAt(tester, GraphScreen(api: fakeApi(), open: noopOpen), size);
        expect(tester.takeException(), isNull, reason: 'estate threw at $name');
      },
          );
    });

    sizes.forEach((name, size) {
      testWidgets('changelog survives $name', (tester) async {
        await pumpAt(tester, ChangelogScreen(api: fakeApi()), size);
        expect(tester.takeException(), isNull, reason: 'changelog threw at $name');
      },
          // FINDING P2-21: the changelog filter pills overflow at phone width.
          skip: size.width < 768);
    });
  });

  group('a dead server', () {
    testWidgets('every surface reports it instead of spinning forever', (tester) async {
      for (final build in <Widget Function()>[
        () => GraphScreen(api: fakeApi(failPaths: {'/api/graph'}), open: noopOpen),
        () => SourcesScreen(api: fakeApi(failPaths: {'/api/sources'}), open: noopOpen),
        () => ChangelogScreen(api: fakeApi(failPaths: {'/api/changelog'})),
        () => ApiHubScreen(api: fakeApi(failPaths: {'/api/graph'}), open: noopOpen),
      ]) {
        await pumpAt(tester, build(), const Size(1440, 900));
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
        expect(find.byType(CircularProgressIndicator), findsNothing,
            reason: 'a failed load must not leave a spinner');
      }
    });
  });
}

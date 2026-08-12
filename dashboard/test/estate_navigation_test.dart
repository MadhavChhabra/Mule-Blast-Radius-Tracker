import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:apiguard_dashboard/screens/graph_screen.dart';
import 'package:apiguard_dashboard/theme.dart';

import 'support/big_estate.dart';
import 'support/fake_api.dart';

/// Getting around the map. The estate used to be a vertical scroll view wrapping a horizontal one,
/// which meant: no diagonal movement, no horizontal scrollbar, and — because Flutter scrollables
/// ignore mouse drags — no way to reach the right-hand columns with a mouse at all. The docked
/// panel sat on top of those same columns.
void main() {
  const size = Size(1440, 900);

  Future<void> pumpEstate(WidgetTester tester, {int apis = 400, String? focus}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: Scaffold(
          body: GraphScreen(api: bigEstateApi(apis: apis), open: noopOpen, initialFocus: focus)),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 100));
  }

  Finder theMap() => find.byType(InteractiveViewer);

  testWidgets('the map pans on both axes at once', (tester) async {
    await pumpEstate(tester, apis: 120);
    expect(theMap(), findsOneWidget);

    final viewport = tester.getRect(theMap());
    // Probe with whichever node sits nearest the middle, so a drag cannot simply carry it out of
    // the built region and leave nothing to measure.
    final centre = viewport.center;
    String? probeName;
    double best = double.infinity;
    for (final element in find.byType(Text).evaluate()) {
      final name = (element.widget as Text).data;
      if (name == null || !name.contains('-api-')) continue;
      final r = tester.getRect(find.byWidget(element.widget));
      final d = (r.center - centre).distance;
      if (d < best) {
        best = d;
        probeName = name;
      }
    }
    expect(probeName, isNotNull);
    final before = tester.getRect(find.text(probeName!));

    // A single diagonal drag has to move the map both ways — the nested scroll views could only
    // ever do one axis per gesture, and neither of them answered a mouse drag at all.
    await tester.drag(theMap(), const Offset(-160, -90));
    await tester.pump(const Duration(milliseconds: 60));
    final after = tester.getRect(find.text(probeName));

    expect(after.left, closeTo(before.left - 160, 2), reason: 'the canvas did not pan horizontally');
    expect(after.top, closeTo(before.top - 90, 2), reason: 'the canvas did not pan vertically');
    expect(tester.getRect(theMap()), viewport, reason: 'the viewport itself must not move');
  });

  testWidgets('anything under the docked panel can be pulled out from under it',
      (tester) async {
    await pumpEstate(tester, apis: 120);

    // The panel is docked at right:28 over a 300px body, so it covers this band of the window.
    final panelLeft = size.width - 328;

    String? coveredName;
    late Rect covered;
    for (final element in find.byType(Text).evaluate()) {
      final name = (element.widget as Text).data;
      if (name == null || !name.startsWith('backend-api-')) continue;
      final r = tester.getRect(find.byWidget(element.widget));
      if (r.right > panelLeft) {
        coveredName = name;
        covered = r;
        break;
      }
    }
    expect(coveredName, isNotNull,
        reason: 'expected the estate to run under the panel — otherwise this proves nothing');

    await tester.drag(theMap(), const Offset(-420, 0));
    await tester.pump(const Duration(milliseconds: 60));

    final moved = tester.getRect(find.text(coveredName!));
    expect(moved.right, lessThan(panelLeft),
        reason: 'dragging left must bring the covered columns into the open');
    expect(moved.left, closeTo(covered.left - 420, 2));
  });

  testWidgets('the attention panel folds away', (tester) async {
    await pumpEstate(tester, apis: 40);

    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byIcon(Icons.chevron_left), findsOneWidget,
        reason: 'folded panel keeps a way back');
    expect(find.text('SINCE YOU LAST LOOKED'), findsNothing);
  });

  testWidgets('focusing a node brings it into view instead of leaving it off screen',
      (tester) async {
    // A node deep in the estate — bottom of the last sub-column, nowhere near where the map opens.
    await pumpEstate(tester, apis: 120, focus: 'system-api-118');
    await tester.pump(const Duration(milliseconds: 200));

    // Focus mode is on the named API and the canvas moved to it, so what the panel talks about is
    // actually on screen.
    expect(find.text('WHO YOU HAVE TO TELL'), findsOneWidget);
    final card = find.text('system-api-118');
    expect(card, findsOneWidget);
    final r = tester.getRect(card);
    expect(r.left, greaterThan(0));
    expect(r.right, lessThan(size.width));
    expect(r.top, greaterThan(0));
    expect(r.bottom, lessThan(size.height));
  });

  testWidgets('a huge estate says how much of itself it is showing', (tester) async {
    await pumpEstate(tester, apis: 1000);
    expect(find.textContaining('Zoom in to read names'), findsOneWidget);
  });

  testWidgets('nodes stay clickable when the map draws plates instead of cards',
      (tester) async {
    await pumpEstate(tester, apis: 1000);
    // Plate mode is on, so there are no node cards to tap — only painted plates.
    expect(find.textContaining('Zoom in to read names'), findsOneWidget);
    expect(find.text('WHO YOU HAVE TO TELL'), findsNothing);

    // Walk a short line across the middle of the map so the assertion does not depend on a node
    // happening to sit under one exact pixel — the rows are 120 apart, so this crosses several.
    final map = tester.getRect(theMap());
    for (double dy = -160; dy <= 160; dy += 20) {
      await tester.tapAt(Offset(map.center.dx, map.center.dy + dy));
      await tester.pump(const Duration(milliseconds: 250));
      if (find.text('WHO YOU HAVE TO TELL').evaluate().isNotEmpty) break;
    }

    expect(find.text('WHO YOU HAVE TO TELL'), findsOneWidget,
        reason: 'a painted node must still select on click');
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:apiguard_dashboard/main.dart';
import 'package:apiguard_dashboard/pins.dart';
import 'package:apiguard_dashboard/theme.dart';

import 'support/fake_api.dart';

/// Controls that look alive, and navigation that quietly disappears. These are the two ways a
/// console loses a user's trust without ever throwing an error.
void main() {
  setUp(() => FocusState.instance.set(null));

  Future<void> pumpShell(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: HomeShell(api: fakeApi()),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  testWidgets('focus mode keeps a way to reach the other surfaces', (tester) async {
    await pumpShell(tester);
    expect(find.text('Sources'), findsOneWidget);
    expect(find.text('Changelog'), findsOneWidget);

    await tester.tap(find.text('orders-exp-api').hitTestable());
    await settle(tester);

    // The focus bar replaces the nav bar wholesale, so every global destination — and the search
    // button — is gone until the user works out that Esc or the X brings them back.
    expect(find.text('Sources'), findsOneWidget,
        reason: 'focus mode must not strip global navigation');
  },
      // FINDING P1-32: FocusBar carries no nav pills, no search and no brand, so while a blast
      // radius is open there is no mouse route to Sources or Changelog. Ctrl-K still works, but
      // only for someone who already knows it exists.
      skip: true);

  testWidgets('the command bar offers no control that cannot do anything', (tester) async {
    await pumpShell(tester);

    // GOVERNANCE, RISK and LAYERS all toggle something. FOCUS MODE is rendered in the same row,
    // in the same style, with `onTap: focusing ? onExitFocus : null` — so on the screen everybody
    // starts on it is a word that looks live and is inert. There is nothing to exit yet, and the
    // focus bar already announces focus when there is, so it should not be here at all.
    expect(find.text('FOCUS MODE'), findsNothing,
        reason: 'an inert word styled like its live neighbours trains users to distrust the row');
  },
      // FINDING P2-34: the command bar's four words have three different behaviours and one
      // identical style — two toggles, one popup menu, and FOCUS MODE which is inert until there
      // is something to exit.
      skip: true);

  testWidgets('the estate explains what its colours and dashes mean', (tester) async {
    await pumpShell(tester);

    // The map encodes meaning in five layer colours, three edge colours, dashed-versus-solid
    // strokes, a MAYBE tag and a warning triangle. None of it is written down anywhere.
    // A key has to name the encoding, not merely count things: what a dashed stroke means, what
    // the five layer colours are, what MAYBE on a node card is telling you.
    final hasLegend = find.textContaining('Legend').evaluate().isNotEmpty ||
        find.byTooltip('Legend').evaluate().isNotEmpty ||
        find.textContaining('What the').evaluate().isNotEmpty ||
        find.textContaining('dashed').evaluate().isNotEmpty;
    expect(hasLegend, isTrue,
        reason: 'a console whose primary surface is colour-coded needs a key');
  },
      // FINDING P1-33: there is no legend anywhere in the app.
      skip: true);
}

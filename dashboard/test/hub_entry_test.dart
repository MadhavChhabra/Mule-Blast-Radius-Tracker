import 'package:flutter_test/flutter_test.dart';

import 'package:apiguard_dashboard/screens/api_hub_screen.dart';

import 'support/fake_api.dart';

/// Arriving at the hub from the nav bar, with nothing selected. It used to silently open whichever
/// API sorted first — on a real estate, an API the developer has never heard of, on a screen that
/// never says why it is there.
void main() {
  testWidgets('the hub asks which API rather than opening an arbitrary one', (tester) async {
    await pumpScreen(tester, ApiHubScreen(api: fakeApi(), open: noopOpen));
    await tester.pump(const Duration(milliseconds: 200));

    // Not opened on orders-exp-api (first alphabetically) or anything else.
    expect(find.text('Change impact'), findsNothing);
    expect(find.text('API hub'), findsOneWidget);
    expect(find.textContaining('Pick the API you are about to touch'), findsOneWidget);

    // And the ways in are the ones a developer would actually pick from.
    expect(find.text('Search all 3 APIs'), findsOneWidget);
    expect(find.text('A BREAKING CHANGE IS IN FLIGHT'), findsOneWidget);
    expect(find.text('MOST DEPENDED ON'), findsOneWidget);
  });

  testWidgets('picking an API from the shortlist opens it', (tester) async {
    await pumpScreen(tester, ApiHubScreen(api: fakeApi(), open: noopOpen));
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.text('orders-exp-api').first);
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Change impact'), findsOneWidget);
    expect(find.text('Relationships'), findsOneWidget);
  });

  testWidgets('an explicit API still opens straight away', (tester) async {
    await pumpScreen(tester,
        ApiHubScreen(api: fakeApi(), open: noopOpen, initialApi: 'orders-proc-api'));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Change impact'), findsOneWidget);
    expect(find.textContaining('Pick the API you are about to touch'), findsNothing);
  });
}

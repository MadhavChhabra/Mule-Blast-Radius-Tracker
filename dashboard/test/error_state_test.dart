import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:apiguard_dashboard/theme.dart';
import 'package:apiguard_dashboard/widgets.dart';

void main() {
  test('describeApiError distinguishes auth, offline and generic failures', () {
    final auth = describeApiError(Exception('This server requires an API key'));
    expect(auth.title, contains('API key'));
    expect(auth.offline, isFalse);

    final offline = describeApiError(Exception('ClientException: Failed to fetch'));
    expect(offline.offline, isTrue);

    final generic = describeApiError(Exception('GET /api/graph failed: 500 boom'));
    expect(generic.offline, isFalse);
    expect(generic.title, 'Something went wrong');
  });

  testWidgets('ApiErrorState shows a Retry button and fires the callback', (tester) async {
    var retried = 0;
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(
        body: ApiErrorState(
          error: Exception('Failed to fetch'),
          onRetry: () => retried++,
        ),
      ),
    ));

    expect(find.text('Retry'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    expect(retried, 1);
  });

  testWidgets('ApiErrorState omits Retry when no callback is given', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(body: ApiErrorState(error: Exception('boom'))),
    ));

    expect(find.text('Retry'), findsNothing);
  });
}

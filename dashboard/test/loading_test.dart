import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:apiguard_dashboard/theme.dart';
import 'package:apiguard_dashboard/widgets.dart';
import 'package:apiguard_dashboard/widgets/skeleton.dart';

void main() {
  testWidgets('AsyncView shows a shimmer skeleton while loading, then content', (tester) async {
    final completer = Completer<List<int>>();
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(
        body: AsyncView<List<int>>(
          future: completer.future,
          builder: (_, data) => Text('loaded ${data.length}'),
        ),
      ),
    ));
    await tester.pump();

    expect(find.byType(Shimmer), findsOneWidget);
    expect(find.textContaining('loaded'), findsNothing);

    completer.complete([1, 2, 3]);
    await tester.pump();
    await tester.pump();

    expect(find.byType(Shimmer), findsNothing);
    expect(find.text('loaded 3'), findsOneWidget);
  });
}

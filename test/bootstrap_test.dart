import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelbox/bootstrap.dart';

void main() {
  testWidgets('shows initialization progress before opening the real app', (
    tester,
  ) async {
    final ready = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(
      ReelboxBootstrap(
        initialize: () {
          calls++;
          return ready.future;
        },
        builder: (_) => const MaterialApp(home: Text('Application ready')),
      ),
    );
    expect(calls, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Application ready'), findsNothing);
    ready.complete();
    await tester.pumpAndSettle();
    expect(find.text('Application ready'), findsOneWidget);
  });
  testWidgets(
    'initialization failure is recoverable and never displays raw vendor text',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        ReelboxBootstrap(
          initialize: () async {
            if (calls++ == 0) throw StateError('نورتون https://t.me/support');
          },
          builder: (_) => const MaterialApp(home: Text('Application ready')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Try again'), findsOneWidget);
      expect(find.textContaining('نورتون'), findsNothing);
      expect(find.textContaining('t.me'), findsNothing);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.text('Application ready'), findsOneWidget);
    },
  );
  testWidgets('late initialization completion does not update disposed UI', (
    tester,
  ) async {
    final ready = Completer<void>();
    await tester.pumpWidget(
      ReelboxBootstrap(
        initialize: () => ready.future,
        builder: (_) => const MaterialApp(home: Text('Application ready')),
      ),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    ready.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

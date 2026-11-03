import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelbox/data/models.dart';
import 'package:reelbox/media/player_page.dart';
import 'package:reelbox/state/app_state.dart';

void main() {
  testWidgets(
    'Untrusted source is rejected before initializing a native player',
    (tester) async {
      final state = AppState();
      await tester.pumpWidget(
        AppScope(
          state: state,
          child: const MaterialApp(
            home: PlayerPage(
              title: TitleRecord(id: 1, title: 'Invalid source'),
              source: MediaSource(url: 'javascript:alert(1)'),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Unable to play this source'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );
}

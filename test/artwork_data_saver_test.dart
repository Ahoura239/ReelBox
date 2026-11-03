import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelbox/state/app_state.dart';
import 'package:reelbox/ui/common.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'data saver never builds network images and retains artwork placeholder',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final state = AppState();
      await state.updateSettings(state.prefs.copyWith(dataSaver: true));
      await tester.pumpWidget(
        AppScope(
          state: state,
          child: const MaterialApp(
            home: Scaffold(
              body: MediaArtwork(
                url: 'https://example.test/poster.jpg',
                width: 100,
                height: 140,
              ),
            ),
          ),
        ),
      );
      expect(find.byType(Image), findsNothing);
      expect(find.byIcon(Icons.local_movies_outlined), findsOneWidget);
      final size = tester.getSize(find.byType(MediaArtwork));
      expect(size, const Size(100, 140));
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );
}

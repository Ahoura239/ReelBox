import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelbox/app.dart';
import 'package:reelbox/data/api_service.dart';
import 'package:reelbox/data/models.dart';
import 'package:reelbox/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NavigationFixtureApi extends ApiService {
  @override
  Future<Map<String, dynamic>> home() async => {'genres': []};

  @override
  Future<void> initialize({bool discover = true}) async {}

  @override
  Future<List<Map<String, dynamic>>> actors({
    int page = 1,
    String search = '',
  }) async => [];

  @override
  Future<List<Tag>> countries() async => [];
}

void main() {
  testWidgets('Account-free app exposes its five core destinations', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final state = AppState(
      api: _NavigationFixtureApi(),
      storage: await SharedPreferences.getInstance(),
    );
    await state.initialize(discover: false);
    // This fixture exercises the shell, not first-run onboarding.
    await state.updateSettings(state.prefs.copyWith(introCompleted: true));
    await tester.pumpWidget(MyApp(state: state));
    await tester.pumpAndSettle();
    for (final label in ['Discover', 'Browse', 'Search', 'Library', 'More']) {
      expect(
        find.text(label),
        findsWidgets,
        reason: 'Missing destination: $label',
      );
    }
    for (final label in [
      'Sign in',
      'Register',
      'Subscribe',
      'Buy subscription',
    ]) {
      expect(find.text(label), findsNothing);
    }
    await tester.tap(find.byIcon(Icons.video_library_outlined).last);
    await tester.pumpAndSettle();
    expect(find.text('Watchlist (0)'), findsOneWidget);
    expect(find.text('Continue (0)'), findsOneWidget);
    expect(find.text('Collections (0)'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });
}

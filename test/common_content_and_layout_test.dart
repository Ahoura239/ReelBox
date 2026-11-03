import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:reelbox/data/api_service.dart';
import 'package:reelbox/data/models.dart';
import 'package:reelbox/state/app_state.dart';
import 'package:reelbox/ui/common.dart';

Future<AppState> stateForTest() async {
  SharedPreferences.setMockInitialValues({});
  final state = AppState(api: ApiService());
  await state.initialize(discover: false);
  return state;
}

Widget host(AppState state, Widget child) => AppScope(
  state: state,
  child: MaterialApp(home: Scaffold(body: child)),
);

void main() {
  const movie = TitleRecord(id: 1, title: 'A real film');
  const promo = TitleRecord(id: 2, title: 'ملودی باکس');
  const station = TitleRecord(
    id: 3,
    title: 'Old live station',
    type: 'channel',
  );

  testWidgets(
    'shared grids reject removed records even when API parsing is bypassed',
    (tester) async {
      final state = await stateForTest();
      await tester.pumpWidget(
        host(state, const PosterGrid(items: [movie, promo, station])),
      );
      expect(find.text('A real film'), findsOneWidget);
      expect(find.text('ملودی باکس'), findsNothing);
      expect(find.text('Old live station'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
    },
  );
  testWidgets('a directly constructed removed poster never paints its label', (
    tester,
  ) async {
    final state = await stateForTest();
    await tester.pumpWidget(
      host(state, const SizedBox(height: 280, child: PosterCard(title: promo))),
    );
    expect(find.text('ملودی باکس'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });
  testWidgets('a promotional rail heading cannot reintroduce vendor content', (
    tester,
  ) async {
    final state = await stateForTest();
    await tester.pumpWidget(
      host(state, const PosterRail(title: 'نورتون', items: [movie])),
    );
    expect(find.text('نورتون'), findsNothing);
    expect(find.byType(PosterCard), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });
  testWidgets(
    'compact preference renders usable rows rather than poster grids',
    (tester) async {
      final state = await stateForTest();
      await state.updateSettings(state.prefs.copyWith(compactCatalog: true));
      await tester.pumpWidget(host(state, const PosterGrid(items: [movie])));
      expect(find.byType(GridView), findsNothing);
      expect(
        find.byKey(const ValueKey('compact-title-row:poster:1')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
    },
  );
  testWidgets('status messages have an explicit accessible dismiss action', (
    tester,
  ) async {
    final state = await stateForTest();
    await tester.pumpWidget(
      host(
        state,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => toast(context, 'Saved locally'),
            child: const Text('Show status'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Show status'));
    await tester.pumpAndSettle();
    final closeTooltip = MaterialLocalizations.of(
      tester.element(find.byType(SnackBar)),
    ).closeButtonTooltip;
    expect(find.byTooltip(closeTooltip), findsOneWidget);
    await tester.tap(find.byTooltip(closeTooltip));
    await tester.pumpAndSettle();
    expect(find.text('Saved locally'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });
}

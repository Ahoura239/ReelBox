import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelbox/data/api_service.dart';
import 'package:reelbox/state/app_state.dart';
import 'package:reelbox/ui/catalog.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service_test.dart' show StubAdapter, jsonBody;

Future<AppState> mountPaging(
  WidgetTester tester,
  ApiService api,
  Widget page, {
  bool settle = true,
}) async {
  SharedPreferences.setMockInitialValues({});
  final state = AppState(
    api: api,
    storage: await SharedPreferences.getInstance(),
  );
  addTearDown(state.dispose);
  await state.initialize(discover: false);
  await tester.pumpWidget(
    AppScope(
      state: state,
      child: MaterialApp(home: page),
    ),
  );
  if (settle) await tester.pumpAndSettle();
  return state;
}

Map<String, dynamic> titleRow(int id, String kind) => {
  'id': id,
  'type': kind,
  'title': '$kind $id',
};

void main() {
  testWidgets(
    'failed raw page retries the same cursor without losing prior titles',
    (tester) async {
      final pages = <int>[];
      var failed = false;
      final adapter = StubAdapter((request) {
        if (request.uri.path.contains('/all/')) return jsonBody([]);
        final page = int.parse(request.uri.pathSegments[7]);
        pages.add(page);
        if (page == 1 && !failed) {
          failed = true;
          return jsonBody({}, status: 503);
        }
        return jsonBody(page < 2 ? [titleRow(30 + page, 'movie')] : []);
      });
      await mountPaging(
        tester,
        ApiService(dio: Dio()..httpClientAdapter = adapter),
        const BrowsePage(initialCountry: 9),
      );
      // Short pages now prefetch automatically; a failure still retains its cursor.
      expect(pages, [0, 1]);
      expect(find.text('movie 30'), findsOneWidget);
      await tester.ensureVisible(find.text('Try again'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('movie 30'), findsOneWidget);
      expect(find.text('movie 31'), findsOneWidget);
      expect(pages, [0, 1, 1, 2]);
    },
  );

  testWidgets('filter changes reject stale raw pages', (tester) async {
    final delayed = Completer<ResponseBody>();
    addTearDown(() {
      if (!delayed.isCompleted) delayed.complete(jsonBody([]));
    });
    var pendingRequested = false;
    final adapter = StubAdapter((request) {
      final path = request.uri.path;
      if (path.contains('/all/')) return jsonBody([]);
      if (path.contains('/movie/')) {
        if (path.contains('/created/1/')) {
          pendingRequested = true;
          return delayed.future;
        }
        return jsonBody([titleRow(40, 'movie')]);
      }
      return jsonBody(
        path.contains('/created/0/') ? [titleRow(50, 'serie')] : [],
      );
    });
    await mountPaging(
      tester,
      ApiService(dio: Dio()..httpClientAdapter = adapter),
      const BrowsePage(),
      settle: false,
    );
    for (var frame = 0; frame < 24 && !pendingRequested; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(pendingRequested, true);
    await tester.ensureVisible(find.text('Series'));
    await tester.tap(find.text('Series'));
    await tester.pumpAndSettle();
    delayed.complete(jsonBody([titleRow(41, 'movie')]));
    await tester.pumpAndSettle();
    expect(find.text('serie 50'), findsOneWidget);
    expect(find.text('movie 41'), findsNothing);
    expect(find.text('movie 40'), findsNothing);
  });

  testWidgets('duplicate-only title pages do not truncate later results', (
    tester,
  ) async {
    final pages = <int>[];
    final adapter = StubAdapter((request) {
      final query = request.uri.queryParameters;
      if (['search-trand', 'best-rand-top'].contains(query['action'])) {
        return jsonBody([]);
      }
      final page = int.parse(query['pageno']!);
      pages.add(page);
      return jsonBody(switch (page) {
        1 || 2 => [titleRow(20, 'movie')],
        3 => [titleRow(21, 'movie')],
        _ => [],
      });
    });
    await mountPaging(
      tester,
      ApiService(dio: Dio()..httpClientAdapter = adapter),
      const SearchPage(),
    );
    await tester.enterText(find.byType(TextField).first, 'movie');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('movie 20'), findsOneWidget);
    expect(find.text('movie 21'), findsOneWidget);
    expect(pages, [1, 2, 3, 4]);
    expect(find.text('Load more'), findsNothing);
  });

  testWidgets(
    'duplicate-only actor directory pages retain server continuation',
    (tester) async {
      final pages = <int>[];
      final adapter = StubAdapter((request) {
        final page = int.parse(request.uri.queryParameters['pageno']!);
        pages.add(page);
        return jsonBody(switch (page) {
          1 || 2 => [
            {'id': 1, 'name': 'Actor one'},
          ],
          3 => [
            {'id': 2, 'name': 'Actor two'},
          ],
          _ => [],
        });
      });
      await mountPaging(
        tester,
        ApiService(dio: Dio()..httpClientAdapter = adapter),
        const ActorsPage(),
      );
      expect(find.text('Actor one'), findsOneWidget);
      expect(find.text('Actor two'), findsOneWidget);
      expect(pages, [1, 2, 3, 4]);
    },
  );

  testWidgets('country movies retain continuation across opposite-kind pages', (
    tester,
  ) async {
    final pages = <int>[];
    final adapter = StubAdapter((request) {
      if (request.uri.path.contains('/all/')) return jsonBody([]);
      final page = int.parse(request.uri.pathSegments[7]);
      pages.add(page);
      return jsonBody(switch (page) {
        0 => [titleRow(10, 'serie')],
        1 => [titleRow(11, 'serie')],
        2 => [titleRow(12, 'movie')],
        _ => [],
      });
    });
    await mountPaging(
      tester,
      ApiService(dio: Dio()..httpClientAdapter = adapter),
      const BrowsePage(initialCountry: 9),
    );
    expect(find.text('No titles found'), findsNothing);
    expect(find.text('movie 12'), findsOneWidget);
    expect(find.text('serie 10'), findsNothing);
    expect(pages, [0, 1, 2, 3]);
    expect(find.text('Load more'), findsNothing);
    expect(find.text('You’re all caught up'), findsOneWidget);
  });
}

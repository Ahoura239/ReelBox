import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelbox/data/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service_test.dart' as fixtures;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('verified cache is restored by a fresh instance without contacting discovery', () async {
    final adapter = fixtures.StubAdapter(
      (request) => request.uri.host == 'ninnies-server.info'
          ? ResponseBody.fromString(ApiService.defaultBaseUrl, 200)
          : fixtures.jsonBody([
              {'id': 1, 'title': 'Drama'},
            ]),
    );
    await ApiService(dio: Dio()..httpClientAdapter = adapter).initialize();
    var reads = 0;
    final offline = fixtures.StubAdapter(
      (_) => throw StateError('No network permitted'),
    );
    final restored = ApiService(
      dio: Dio()..httpClientAdapter = offline,
      preferences: () async {
        reads++;
        return SharedPreferences.getInstance();
      },
    );
    await restored.initialize(discover: false);
    expect(reads, 1);
    expect(restored.baseUrl, ApiService.defaultBaseUrl);
    expect(offline.requests, isEmpty);
  });

  for (final value in [
    'broken',
    'https://untrusted.example/api/',
    'http://ninwinios.info/api/',
    'https://fixture:fixture@ninwinios.info/api/',
    'https://ninwinios.info/api/?x=1',
    'https://ninwinios.info/api/#fragment',
    'https://127.0.0.1/api/',
    'https://ninwinios.info:444/api/',
  ]) {
    test(
      'invalid cached configuration cannot change the trusted destination: ${Uri.tryParse(value)?.host ?? 'malformed'}',
      () async {
        SharedPreferences.setMockInitialValues({
          'reelbox.trusted-api.v1': value,
        });
        final adapter = fixtures.StubAdapter(
          (_) => throw StateError('No network permitted'),
        );
        final api = ApiService(dio: Dio()..httpClientAdapter = adapter);
        await api.initialize(discover: false);
        expect(api.baseUrl, ApiService.defaultBaseUrl);
        expect(adapter.requests, isEmpty);
      },
    );
  }

  test('discovery outage keeps last trusted cache and an invalid schema is not cached', () async {
    SharedPreferences.setMockInitialValues({
      'reelbox.trusted-api.v1': ApiService.defaultBaseUrl,
    });
    final offline = fixtures.StubAdapter(
      (r) => throw DioException(
        requestOptions: r,
        type: DioExceptionType.connectionError,
      ),
    );
    final api = ApiService(dio: Dio()..httpClientAdapter = offline);
    await api.initialize();
    expect(api.baseUrl, ApiService.defaultBaseUrl);
    expect(offline.requests, hasLength(1));
    expect(
      (await SharedPreferences.getInstance()).getString(
        'reelbox.trusted-api.v1',
      ),
      ApiService.defaultBaseUrl,
    );
    SharedPreferences.setMockInitialValues({});
    final invalid = fixtures.StubAdapter(
      (r) => r.uri.host == 'ninnies-server.info'
          ? ResponseBody.fromString(ApiService.defaultBaseUrl, 200)
          : fixtures.jsonBody([]),
    );
    await ApiService(dio: Dio()..httpClientAdapter = invalid).initialize();
    expect(
      (await SharedPreferences.getInstance()).getString(
        'reelbox.trusted-api.v1',
      ),
      isNull,
    );
  });

  test(
    'read-only transport failure recovers once without a discovery storm',
    () async {
      var attempts = 0;
      final adapter = fixtures.StubAdapter((r) {
        if (++attempts == 1) {
          throw DioException(
            requestOptions: r,
            type: DioExceptionType.connectionError,
          );
        }
        return fixtures.jsonBody([
          {'id': 1, 'title': 'Drama'},
        ]);
      });
      final result = await ApiService(dio: Dio()..httpClientAdapter = adapter)
          .genres();
      expect(result.single.title, 'Drama');
      expect(attempts, 2);
      expect(
        adapter.requests.every((r) => r.uri.host == 'ninwinios.info'),
        true,
      );
    },
  );

  test('persistent transport failure is bounded to two GET attempts', () async {
    final adapter = fixtures.StubAdapter(
      (r) => throw DioException(
        requestOptions: r,
        type: DioExceptionType.receiveTimeout,
      ),
    );
    await expectLater(
      ApiService(dio: Dio()..httpClientAdapter = adapter).genres(),
      throwsA(isA<ApiException>()),
    );
    expect(adapter.requests, hasLength(2));
  });

  for (final status in [401, 403, 404, 429, 500]) {
    test('HTTP $status is preserved without automatic retry', () async {
      final adapter = fixtures.StubAdapter(
        (_) => fixtures.jsonBody({}, status: status),
      );
      await expectLater(
        ApiService(dio: Dio()..httpClientAdapter = adapter).genres(),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'status', status),
        ),
      );
      expect(adapter.requests, hasLength(1));
    });
  }

  for (final type in [
    DioExceptionType.cancel,
    DioExceptionType.badCertificate,
  ]) {
    test('$type is never retried', () async {
      final adapter = fixtures.StubAdapter(
        (r) => throw DioException(requestOptions: r, type: type),
      );
      await expectLater(
        ApiService(dio: Dio()..httpClientAdapter = adapter).genres(),
        throwsA(isA<ApiException>()),
      );
      expect(adapter.requests, hasLength(1));
    });
  }

  test('POST transport failure is not replayed', () async {
    final adapter = fixtures.StubAdapter(
      (r) => throw DioException(
        requestOptions: r,
        type: DioExceptionType.connectionError,
      ),
    );
    await expectLater(
      ApiService(dio: Dio()..httpClientAdapter = adapter)
          .post('genre/read', {'fixture': true}),
      throwsA(isA<ApiException>()),
    );
    expect(adapter.requests, hasLength(1));
  });

  test(
    'concurrent failed GETs share cache loading and each retry only once',
    () async {
      var reads = 0;
      final attempts = <String, int>{};
      final adapter = fixtures.StubAdapter((r) {
        final n = attempts.update(r.uri.path, (n) => n + 1, ifAbsent: () => 1);
        if (n == 1) {
          throw DioException(
            requestOptions: r,
            type: DioExceptionType.connectionError,
          );
        }
        return fixtures.jsonBody([]);
      });
      final cache = Completer<SharedPreferences>();
      final api = ApiService(
        dio: Dio()..httpClientAdapter = adapter,
        preferences: () {
          reads++;
          return cache.future;
        },
      );
      final requests = Future.wait([
        for (final n in [1, 2, 3]) api.get('fixture-$n'),
      ]);
      await Future<void>.delayed(Duration.zero);
      cache.complete(await SharedPreferences.getInstance());
      await requests;
      expect(reads, 1);
      expect(attempts.values, everyElement(2));
      expect(adapter.requests, hasLength(6));
    },
  );

  test(
    'production default persists only a schema-verified trusted base',
    () async {
      SharedPreferences.setMockInitialValues({});
      final adapter = fixtures.StubAdapter((request) {
        if (request.uri.host == 'ninnies-server.info') {
          return ResponseBody.fromString(ApiService.defaultBaseUrl, 200);
        }
        return fixtures.jsonBody([
          {'id': 1, 'title': 'Drama'},
        ]);
      });
      final api = ApiService(dio: Dio()..httpClientAdapter = adapter);
      await api.initialize();
      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences.getString('reelbox.trusted-api.v1'),
        ApiService.defaultBaseUrl,
      );
      expect(adapter.requests, hasLength(2));
    },
  );
}

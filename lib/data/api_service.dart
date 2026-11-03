import 'dart:collection';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'content_policy.dart';

List<dynamic> _array(dynamic raw) {
  if (raw == null) return [];
  if (raw is List) return raw;
  if (raw is Map) {
    for (final key in ['posters', 'data', 'result', 'items']) {
      if (raw[key] is List) return raw[key] as List;
    }
  }
  throw const ApiException(
    'The service returned an unsupported response shape.',
  );
}

List<Map<String, dynamic>> _maps(dynamic raw) =>
    _array(raw)
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
Map<String, dynamic> _object(dynamic raw) {
  if (raw is Map) return Map<String, dynamic>.from(raw);
  throw const ApiException(
    'The service returned an unsupported response shape.',
  );
}

List<TitleRecord> _titles(dynamic raw) =>
    _maps(raw)
        .where(ContentPolicy.allowsTitleJson)
        .map(TitleRecord.fromJson)
        .where((title) => title.id > 0 && title.title.isNotEmpty)
        .toList();

/// Safe error suitable for presentation. Never holds request URLs or form data.
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  const ApiException(this.message, {this.statusCode});
  @override
  String toString() => message;
}

/// A single raw server page, compatible with existing List-based callers.
/// Visible items may be empty even when the raw page has a continuation.
class CatalogPage extends ListBase<TitleRecord> {
  CatalogPage(Iterable<TitleRecord> items, {required this.nextPage})
    : _items = List.unmodifiable(items);
  final List<TitleRecord> _items;
  final int? nextPage;
  @override
  int get length => _items.length;
  @override
  set length(int value) => throw UnsupportedError('Read-only page');
  @override
  TitleRecord operator [](int index) => _items[index];
  @override
  void operator []=(int index, TitleRecord value) =>
      throw UnsupportedError('Read-only page');
}

class ApiService {
  static const sharedKey = String.fromEnvironment('REELBOX_API_KEY');
  static const actorKey = String.fromEnvironment('REELBOX_ACTOR_KEY');
  static const defaultBaseUrl = 'https://ninwinios.info/api/';
  static const _configUrl =
      'https://ninnies-server.info/api-user/newapi/config-server186.txt';
  // Unsigned discovery must not be able to add a credential destination.
  static const _serviceHosts = {'ninwinios.info'};
  static const _legacyHosts = {
    'simbaapp.info',
    'winbedrives.com',
    'boxlimon.com',
    'gitcss.info',
  };
  final Dio _dio;
  final Future<SharedPreferences> Function() _preferences;
  bool _cacheRead = false;
  Future<void>? _cacheRestore, _discovery;
  static const _cacheKey = 'reelbox.trusted-api.v1';
  String _baseUrl;
  ApiService({
    Dio? dio,
    String? baseUrl,
    Future<SharedPreferences> Function()? preferences,
  }) : _dio = dio ?? Dio(),
       _preferences = preferences ?? SharedPreferences.getInstance,
       _baseUrl = _validatedBase(baseUrl ?? defaultBaseUrl) {
    // Do not inherit caller default credentials on the configuration request.
    _dio.options = BaseOptions(
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 25),
      sendTimeout: const Duration(seconds: 12),
      followRedirects: false,
      maxRedirects: 0,
      responseType: ResponseType.plain,
      headers: {'Accept': 'application/json'},
    );
  }
  String get baseUrl => _baseUrl;
  String get hostRoot => Uri.parse(_baseUrl).origin;
  static bool _loopback(Uri uri) =>
      {'localhost', '127.0.0.1', '::1', '[::1]'}.contains(uri.host);
  static String _validatedBase(String value) {
    try {
      final uri = Uri.parse(value.trim());
      final trusted =
          _serviceHosts.contains(uri.host) &&
          uri.scheme == 'https' &&
          uri.port == 443;
      final local =
          _loopback(uri) && (uri.scheme == 'http' || uri.scheme == 'https');
      if ((!trusted && !local) ||
          uri.userInfo.isNotEmpty ||
          uri.hasQuery ||
          uri.hasFragment ||
          !{'/api', '/api/'}.contains(uri.path)) {
        throw const FormatException();
      }
      return uri.replace(path: '/api/').toString();
    } on FormatException {
      throw const ApiException('Use a trusted HTTPS API server.');
    }
  }

  Future<void> setBaseUrl(String url) async {
    final validated = _validatedBase(url);
    _baseUrl = validated;
  }

  Future<void> initialize({bool discover = true}) async {
    await _restoreCachedBase();
    if (!discover || _loopback(Uri.parse(_baseUrl))) return;
    final running = _discovery;
    if (running != null) return running;
    late final Future<void> work;
    work = _discoverBase().whenComplete(() {
      if (identical(_discovery, work)) _discovery = null;
    });
    _discovery = work;
    await work;
  }

  Future<void> _restoreCachedBase() {
    if (_cacheRead || _loopback(Uri.parse(_baseUrl))) {
      return Future<void>.value();
    }
    final running = _cacheRestore;
    if (running != null) return running;
    late final Future<void> work;
    work =
        (() async {
          final originalBase = _baseUrl;
          try {
            final saved = (await _preferences()).getString(_cacheKey);
            if (saved == null) return;
            final uri = Uri.parse(saved);
            // Constructor loopback injection is for local fixtures, never a cache trust grant.
            if (_loopback(uri) || uri.scheme != 'https') return;
            final validated = _validatedBase(saved);
            if (_baseUrl == originalBase) _baseUrl = validated;
          } catch (_) {
            // Corrupt/unavailable local storage must not break the trusted default.
          }
        })().whenComplete(() {
          _cacheRead = true;
          if (identical(_cacheRestore, work)) _cacheRestore = null;
        });
    _cacheRestore = work;
    return work;
  }

  Future<void> _discoverBase() async {
    try {
      final response = await _dio.get<String>(
        _configUrl,
        options: Options(
          responseType: ResponseType.plain,
          followRedirects: false,
          maxRedirects: 0,
        ),
      );
      if (response.statusCode != 200) return;
      final advertised = Uri.parse((response.data ?? '').trim());
      final candidate = _validatedBase(
        advertised.replace(scheme: 'https').toString(),
      );
      // A domain in unsigned configuration is accepted only after a read-only
      // HTTPS schema check, and only if already in the trust allowlist.
      final probe = await _request(
        'GET',
        Uri.parse('${candidate}genre/all/$sharedKey/'),
        retryTransport: false,
      );
      if (probe is List &&
          probe.any(
            (item) =>
                item is Map && item['id'] != null && item['title'] is String,
          )) {
        _baseUrl = candidate;
        try {
          await (await _preferences()).setString(_cacheKey, candidate);
        } catch (_) {
          // A storage failure does not invalidate the successful HTTPS probe.
        }
      }
    } catch (_) {
      // Discovery is optional. Preserve the independently verified HTTPS base.
    }
  }

  Uri _resolve(String path, {bool allowLegacy = true}) {
    try {
      if (path != path.trim() || path.startsWith('//')) {
        throw const FormatException();
      }
      var rawPath = path.split('?').first;
      for (var i = 0; i < 3; i++) {
        if (RegExp(r'[\\\x00-\x20\x7f]').hasMatch(rawPath) ||
            RegExp(r'(^|/)\.{1,2}(/|$)').hasMatch(rawPath)) {
          throw const FormatException();
        }
        final decoded = Uri.decodeComponent(rawPath);
        if (decoded == rawPath) break;
        rawPath = decoded;
      }
      var uri = Uri.parse(path);
      if (uri.hasFragment || uri.userInfo.isNotEmpty) {
        throw const FormatException();
      }
      final base = Uri.parse(_baseUrl);
      if (uri.hasScheme || uri.hasAuthority) {
        if (!{'http', 'https'}.contains(uri.scheme)) {
          throw const FormatException();
        }
        if (uri.origin == base.origin) {
          // Current-host requests never downgrade HTTPS.
        } else if (allowLegacy &&
            _legacyHosts.contains(uri.host) &&
            (uri.scheme == 'http' || uri.scheme == 'https') &&
            ((!uri.hasPort) || uri.port == 80 || uri.port == 443) &&
            (uri.path.startsWith('/api-user/newapi/') ||
                uri.path.startsWith('/api/'))) {
          uri = Uri.parse(
            '$hostRoot${uri.path}${uri.hasQuery ? '?${uri.query}' : ''}',
          );
        } else {
          throw const FormatException();
        }
      } else {
        uri = base.resolve(path);
      }
      if (uri.origin != base.origin ||
          !(uri.path.startsWith('/api/') ||
              uri.path.startsWith('/api-user/'))) {
        throw const FormatException();
      }
      return uri;
    } on FormatException {
      throw const ApiException('The service link is not trusted.');
    }
  }

  List<TitleRecord> decodeTitles(dynamic raw) => _titles(raw);
  Future<dynamic> _legacy(String file, Map<String, dynamic> query) => _request(
    'GET',
    _resolve('$hostRoot/api-user/newapi/$file'),
    query: query,
  );

  Future<List<TitleRecord>> _titlePage(
    Future<dynamic> request,
    int page,
  ) async {
    final raw = _array(await request);
    // Hidden announcements must not terminate upstream catalog pagination.
    return CatalogPage(_titles(raw), nextPage: raw.isEmpty ? null : page + 1);
  }

  Future<List<TitleRecord>> search(
    String query, {
    int page = 1,
    bool english = false,
  }) => _titlePage(
    _legacy('like.php', {
      'action': english ? 'search-movie-en' : 'search-movie',
      'q': query,
      'pageno': page,
    }),
    page,
  );
  Future<List<TitleRecord>> recommended(int genre, {int page = 1}) async =>
      _titlePage(
        _legacy('filter.php', {
          'action': 'pishnahad',
          'garid': genre,
          'pageno': page,
        }),
        page,
      );
  Future<List<TitleRecord>> bestRandom({bool byYear = false, int page = 1}) =>
      _titlePage(
        _legacy('like.php', {
          'action': byYear ? 'best-rand-year' : 'best-rand-top',
          'pageno': page,
        }),
        page,
      );
  Future<List<String>> trending() async {
    final raw = _array(
      await _legacy('like.php', {'action': 'search-trand', 'pageno': 1}),
    );
    return raw
        .map(
          (item) => item is String
              ? item
              : item is Map
              ? item['title'] ?? item['q']
              : null,
        )
        .whereType<String>()
        .where(ContentPolicy.allowsText)
        .where((title) => title.trim().isNotEmpty)
        .take(14)
        .toList();
  }

  Future<List<Map<String, dynamic>>> actors({
    int page = 1,
    String search = '',
  }) async {
    if (search.trim().isEmpty) {
      return _maps(
        ContentPolicy.sanitizeJson(
          await _legacy('like.php', {'action': 'all-actor', 'pageno': page}),
        ),
      );
    }
    // Native Retrofit evidence; the desktop like.php starsearch route currently
    // returns an empty non-JSON body rather than actor results.
    return _maps(
      await get(
        '$hostRoot/api-user/filmahang/star.php',
        query: {
          'key': actorKey,
          'action': 'starsearch',
          'q': search.trim(),
          'pageno': page,
        },
      ),
    );
  }

  Future<List<Map<String, dynamic>>> playlists({
    bool mine = false,
    String userId = '',
    int page = 1,
  }) async {
    // No-network compatibility seam for older callers. Public lists are removed.
    if (mine) {
      throw const ApiException('Server playlists are not part of Reelbox.');
    }
    return const [];
  }

  Future<List<Map<String, dynamic>>> playlistItems(
    int listId, {
    int page = 1,
  }) async => const [];
  Future<List<Map<String, dynamic>>> curatedLinks({bool best = false}) async {
    final groups = _maps(
      await _legacy(best ? 'bartar.php' : 'pishnahad.php', {}),
    );
    final result = <Map<String, dynamic>>[];
    for (final group in groups) {
      final titles = group['title'], links = group['link'];
      if (titles is! List || links is! List) continue;
      for (var i = 0; i < titles.length && i < links.length; i++) {
        if (titles[i] is! String || links[i] is! String) continue;
        if (!ContentPolicy.allowsText(titles[i] as String) ||
            !ContentPolicy.allowsUrl(links[i] as String)) {
          continue;
        }
        try {
          result.add({
            'title': titles[i],
            'link': _resolve(links[i] as String).toString(),
          });
        } on ApiException {
          // Never expose a server-supplied arbitrary destination as API content.
        }
      }
    }
    return result;
  }

  Future<List<TitleRecord>> curatedContent(String link, {int page = 1}) async {
    final uri = _resolve(link);
    final params = {...uri.queryParameters, 'pageno': '$page'};
    return _titles(await get(uri.replace(queryParameters: params).toString()));
  }

  Future<Map<String, dynamic>> home() async {
    final data = _object(await get('first/$sharedKey/'));
    // Unknown future server fields cannot silently introduce vendor feeds.
    const keys = {
      'posters',
      'genres',
      'slides',
      'actors',
      'countries',
      'movies',
      'series',
      'featured',
      'popular',
      'trending',
    };
    return {
      for (final entry in data.entries)
        if (keys.contains(entry.key)) entry.key: entry.value,
    };
  }

  Future<List<Tag>> _tags(String name) async =>
      _maps(await get('$name/all/$sharedKey/')).map(Tag.fromJson).toList();
  Future<List<Tag>> genres() => _tags('genre');
  Future<List<Tag>> countries() => _tags('country');
  Future<List<Tag>> categories() async => const [];
  Future<List<TitleRecord>> catalog({
    String kind = 'movie',
    int genre = 0,
    int country = 0,
    String order = 'created',
    int page = 0,
  }) async {
    if (!{'movie', 'serie', 'series', 'mixed', 'poster'}.contains(kind) ||
        page < 0) {
      throw const ApiException('Unsupported catalog filter.');
    }
    final normalized = kind == 'series' ? 'serie' : kind;
    final mixed =
        normalized == 'mixed' || normalized == 'poster' || country != 0;
    final route = mixed
        ? 'poster/by/filtres/$genre/$country/${Uri.encodeComponent(order)}/$page'
        : '$normalized/by/filtres/$genre/${Uri.encodeComponent(order)}/$page';
    final raw = _array(await _request('GET', _resolve('$route/$sharedKey/')));
    final titles = _titles(raw);
    return CatalogPage(
      country != 0 && {'movie', 'serie'}.contains(normalized)
          ? titles.where((title) => title.type == normalized)
          : titles,
      nextPage: raw.isEmpty ? null : page + 1,
    );
  }

  Future<List<TitleRecord>> channels({
    int category = 0,
    int country = 0,
    int page = 0,
  }) async => const [];
  Future<TitleRecord> poster(int id) async =>
      TitleRecord.fromJson(_object(await get('movie/by/$id/$sharedKey/')));
  Future<TitleRecord> channel(int id) async =>
      throw const ApiException('This content is not part of Reelbox.');
  Future<List<SeasonRecord>> seasons(int id) async =>
      _maps(await get('season/by/serie/$id/$sharedKey/'))
          .map(SeasonRecord.fromJson)
          .toList();
  Future<List<TitleRecord>> actorTitles(int id) async =>
      _titles(await get('movie/by/actor/$id/$sharedKey/'));
  Future<List<Map<String, dynamic>>> roles(int posterId) async =>
      _maps(await get('role/by/poster/$posterId/$sharedKey/'));
  Future<List<Map<String, dynamic>>> subtitles(String kind, int id) async {
    if (!{'movie', 'episode'}.contains(kind)) {
      throw const ApiException('Unsupported subtitle kind.');
    }
    return _maps(await get('subtitles/by/$kind/$id/$sharedKey/'));
  }

  Future<List<Map<String, dynamic>>> comments(int posterId) async =>
      _maps(await get('comments/by/poster/$posterId/$sharedKey/'));

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async =>
      ContentPolicy.sanitizeJson(
        await _request('GET', _resolve(path), query: query),
      );
  Future<dynamic> post(String path, Map<String, dynamic> form) async =>
      _request('POST', _resolve(path, allowLegacy: false), form: form);
  Future<dynamic> _request(
    String method,
    Uri uri, {
    Map<String, dynamic>? query,
    Map<String, dynamic>? form,
    bool retryTransport = true,
  }) async {
    final policyUri = uri.replace(
      queryParameters: {
        ...uri.queryParameters,
        if (query?['action'] != null) 'action': '${query!['action']}',
        if (form?['action'] != null) 'action': '${form!['action']}',
      },
    );
    if (!ContentPolicy.allowsApiPath(policyUri) ||
        !ContentPolicy.allowsUrl(uri.toString())) {
      throw const ApiException('This content is not part of Reelbox.');
    }
    for (var attempt = 0; ; attempt++) {
      try {
        final response = await _dio.request<dynamic>(
          uri.toString(),
          data: form,
          queryParameters: query,
          options: Options(
            method: method,
            followRedirects: false,
            maxRedirects: 0,
            responseType: ResponseType.plain,
            contentType: form == null
                ? null
                : Headers.formUrlEncodedContentType,
          ),
        );
        final status = response.statusCode ?? 0;
        if (status < 200 || status >= 300) {
          throw ApiException(
            'The service rejected the request.',
            statusCode: status,
          );
        }
        if (response.data is String) {
          final text = (response.data as String)
              .replaceFirst('\uFEFF', '')
              .trim();
          return jsonDecode(text);
        }
        return response.data;
      } on DioException catch (error) {
        if (attempt == 0 &&
            retryTransport &&
            method == 'GET' &&
            error.response == null &&
            const {
              DioExceptionType.connectionError,
              DioExceptionType.connectionTimeout,
              DioExceptionType.sendTimeout,
              DioExceptionType.receiveTimeout,
            }.contains(error.type)) {
          // One replay of an idempotent read only. No discovery request storm,
          // alternate untrusted destination, denial retry or mutation replay.
          await _restoreCachedBase();
          continue;
        }
        final code = error.response?.statusCode;
        final message = switch (error.type) {
          DioExceptionType.connectionTimeout ||
          DioExceptionType.sendTimeout ||
          DioExceptionType.receiveTimeout =>
            'The service timed out. Please retry.',
          DioExceptionType.connectionError =>
            'Unable to connect. Check your connection and retry.',
          DioExceptionType.cancel => 'The request was cancelled.',
          _ when code == 401 || code == 403 =>
            'The service denied access to this content.',
          _ => 'The service request failed. Please retry.',
        };
        throw ApiException(message, statusCode: code);
      } on FormatException {
        throw const ApiException('The service returned an invalid response.');
      }
    }
  }
}

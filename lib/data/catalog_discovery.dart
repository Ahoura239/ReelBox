import 'dart:collection';

import 'api_service.dart';
import 'content_policy.dart';
import 'models.dart';

/// Original read-only discovery contracts, independent of account APIs.
class CatalogDiscovery {
  CatalogDiscovery(this.api);
  final ApiService api;

  Future<dynamic> _legacy(String file, Map<String, dynamic> query) =>
      api.get('${api.hostRoot}/api-user/$file', query: query);

  Future<CatalogPage> suggestions({int page = 1}) async =>
      _preservePage(await api.bestRandom(page: page), page);

  Future<CatalogPage> search(
    String query, {
    int page = 1,
    bool english = false,
    DiscoverySearchFilter filter = const DiscoverySearchFilter(),
  }) async {
    final result = _preservePage(
      await api.search(query, page: page, english: english),
      page,
    );
    return CatalogPage(result.where(filter.accepts), nextPage: result.nextPage);
  }

  CatalogPage _preservePage(List<TitleRecord> rows, int page) => CatalogPage(
    rows,
    nextPage: rows is CatalogPage
        ? rows.nextPage
        : rows.isEmpty
        ? null
        : page + 1,
  );

  Future<DiscoveryObjectPage> directory(
    DiscoveryDirectory kind, {
    int page = 1,
  }) async {
    final themes = kind == DiscoveryDirectory.themes;
    final raw = discoveryRows(
      await _legacy(themes ? 'filmahang/star.php' : 'newapi/like.php', {
        if (themes) 'key': ApiService.actorKey,
        'action': themes ? 'mazmon' : 'colection',
        'pageno': page,
      }),
    );
    return DiscoveryObjectPage(
      raw.map((row) => {...row, 'title': row['title'] ?? row['mazmon'] ?? ''}),
      nextPage: themes || raw.isEmpty ? null : page + 1,
    );
  }

  /// These endpoints return poster identifiers, not playable poster objects.
  Future<CatalogPage> sharedTitles({int page = 1, bool newest = false}) async {
    final rows = discoveryRows(
      await _legacy('filmahang/star.php', {
        'key': ApiService.actorKey,
        'action': newest ? 'new' : 'share',
        'pageno': page,
      }),
    );
    final titles = <TitleRecord>[];
    final ids = <int>{};
    // Sequential hydration bounds server load on the account-free public API.
    for (final row in rows) {
      final id = int.tryParse('${row['id']}') ?? 0;
      if (id > 0 && ids.add(id)) titles.add(await api.poster(id));
    }
    return CatalogPage(titles, nextPage: rows.isEmpty ? null : page + 1);
  }
}

enum DiscoveryDirectory { themes, franchises }

class DiscoveryObjectPage extends ListBase<Map<String, dynamic>> {
  DiscoveryObjectPage(
    Iterable<Map<String, dynamic>> rows, {
    required this.nextPage,
  }) : _rows = List.unmodifiable(rows);
  final List<Map<String, dynamic>> _rows;
  final int? nextPage;
  @override
  int get length => _rows.length;
  @override
  set length(int value) => throw UnsupportedError('Read-only page');
  @override
  Map<String, dynamic> operator [](int index) => _rows[index];
  @override
  void operator []=(int index, Map<String, dynamic> value) =>
      throw UnsupportedError('Read-only page');
}

/// The PHP search API has no evidenced advanced-filter parameters. Apply these
/// explicitly to each returned page, retaining its unfiltered continuation.
class DiscoverySearchFilter {
  const DiscoverySearchFilter({
    this.kind = 'mixed',
    this.minimumYear = 0,
    this.minimumRating = 0,
    this.genre = 0,
    this.country = 0,
  });
  final String kind;
  final int minimumYear, genre, country;
  final double minimumRating;
  bool accepts(TitleRecord title) =>
      (kind == 'mixed' ||
          (kind == 'serie' ? title.isSeries : title.type == kind)) &&
      (minimumYear == 0 || title.year >= minimumYear) &&
      title.imdb >= minimumRating &&
      (genre == 0 || title.genres.any((tag) => tag.id == genre)) &&
      (country == 0 || title.countries.any((tag) => tag.id == country));
  String get key => '$kind:$minimumYear:$minimumRating:$genre:$country';
}

/// A complete actor endpoint is unpaged. Only an empty/unavailable endpoint
/// switches to the observed actor-name search, whose raw pages remain paged.
class ActorFilmography {
  ActorFilmography(this.discovery, {required this.id, required this.name});
  final CatalogDiscovery discovery;
  final int id;
  final String name;
  bool usingNameFallback = false;
  Future<CatalogPage> load(int page) async {
    if (page == 1 && id > 0 && !usingNameFallback) {
      try {
        final titles = await discovery.api.actorTitles(id);
        if (titles.isNotEmpty) return CatalogPage(titles, nextPage: null);
      } on ApiException catch (error) {
        if (error.statusCode == 401 || error.statusCode == 403) rethrow;
      }
    }
    usingNameFallback = true;
    if (name.trim().isEmpty) return CatalogPage([], nextPage: null);
    return discovery.search(name, page: page);
  }
}

Map<String, dynamic> actorMetadata(Map<String, dynamic> row) {
  final nested = row['actor'];
  final person = nested is Map ? Map<String, dynamic>.from(nested) : row;
  return {
    ...person,
    'id': person['star_id'] ?? person['actor_id'] ?? person['id'] ?? 0,
    'name':
        person['star_name'] ??
        person['actor_name'] ??
        person['name'] ??
        person['title'] ??
        '',
    'image': person['image'] ?? person['img'] ?? person['photo'] ?? '',
    'role': row['role'] ?? person['role'] ?? '',
    'bio': person['bio'] ?? person['biography'] ?? person['description'] ?? '',
  };
}

MediaSource? currentHistorySource(
  List<MediaSource> sources,
  String previousUrl,
) {
  final playable = sources.where((source) {
    final uri = Uri.tryParse(source.url);
    return !source.isTrailer &&
        ContentPolicy.allowsUrl(source.url) &&
        uri != null &&
        {'https', 'http'}.contains(uri.scheme) &&
        uri.host.isNotEmpty;
  }).toList();
  return playable.where((source) => source.url == previousUrl).firstOrNull ??
      playable.firstOrNull;
}

List<Map<String, dynamic>> discoveryRows(dynamic raw) {
  if (raw is Map) {
    for (final key in ['posters', 'data', 'result', 'items']) {
      if (raw[key] is List) return discoveryRows(raw[key]);
    }
  }
  if (raw is! List) {
    throw const ApiException(
      'The service returned an unsupported response shape.',
    );
  }
  return raw
      .whereType<Map>()
      .map((row) => Map<String, dynamic>.from(row))
      .toList();
}

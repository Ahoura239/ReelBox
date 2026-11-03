import 'dart:convert';
import 'dart:io';

import 'package:reelbox/data/api_service.dart';

Future<void> main() async {
  final api = ApiService();
  await api.initialize();
  final home = await api.home();
  final movies = await api.catalog();
  final series = await api.catalog(kind: 'serie');
  if (movies.isEmpty || series.isEmpty) {
    throw StateError('Live catalog is empty');
  }
  // Catalogs can lead with announcements or titles whose sources are pending.
  // Still require a real playable-source response, without assuming row zero.
  var detail = await api.poster(movies.first.id);
  final checked = <Map<String, int>>[
    {'id': detail.id, 'source_count': detail.sources.length},
  ];
  for (final candidate in movies.skip(1).take(4)) {
    if (detail.sources.isNotEmpty) break;
    detail = await api.poster(candidate.id);
    checked.add({'id': detail.id, 'source_count': detail.sources.length});
  }
  final seasons = await api.seasons(series.first.id);
  final search = await api.search('Matrix', english: true);
  final recommendations = await api.bestRandom();
  if (detail.sources.isEmpty || search.isEmpty || recommendations.isEmpty) {
    throw StateError('A required public endpoint did not return expected data');
  }
  stdout.writeln(
    jsonEncode({
      'api_base': api.baseUrl,
      'home_sections': (home['genres'] as List?)?.length,
      'movie_page_count': movies.length,
      'series_page_count': series.length,
      'movie_detail_id': detail.id,
      'movie_details_checked': checked,
      'movie_source_count': detail.sources.length,
      'series_detail_id': series.first.id,
      'season_count': seasons.length,
      'episode_source_count': seasons.fold<int>(
        0,
        (sum, s) =>
            sum + s.episodes.fold<int>(0, (n, e) => n + e.sources.length),
      ),
      'english_search_results': search.length,
      'recommendations': recommendations.length,
      'account_used': false,
      'media_downloaded': false,
    }),
  );
}

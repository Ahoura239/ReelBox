import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reelbox/data/models.dart';

Map<String, dynamic> fixture(String name) =>
    jsonDecode(File('test/fixtures/$name.json').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  test('real series has no sources and retains the serie discriminator', () {
    final serie = TitleRecord.fromJson(fixture('serie'));
    expect(serie.id, 35716);
    expect(serie.type, 'serie');
    expect(serie.isSeries, isTrue);
    expect(serie.sources, isEmpty);
    expect(TitleRecord.fromJson(serie.toJson()).type, 'serie');
  });
  test('real season retains episode/source variants and unknown metadata', () {
    final raw = fixture('season');
    final season = SeasonRecord.fromJson(raw);
    expect(season.id, 4263);
    expect(season.episodes, hasLength(2));
    expect(season.episodes.first.id, 72819);
    expect(season.episodes.first.sources.single.id, 83260);
    expect(season.episodes.first.sources.single.quality, '');
    expect(
      season.episodes.first.sources.single.url,
      raw['episodes'][0]['sources'][0]['url'],
    );
    expect(season.episodes.first.raw['playas'], '1');
    expect(
      SeasonRecord.fromJson(season.toJson()).episodes.first.toJson(),
      season.episodes.first.toJson(),
    );
  });
  test(
    'real movie preserves source IDs, URLs, countries and entitlement metadata',
    () {
      final raw = fixture('movie');
      final movie = TitleRecord.fromJson(raw);
      expect(movie.id, 35721);
      expect(movie.type, 'movie');
      expect(movie.title, 'The Canvas');
      expect(movie.imdb, 5.2);
      expect(movie.year, 2026);
      expect(movie.duration, '');
      expect(movie.classification, '');
      expect(movie.genres.single.id, 1);
      expect(movie.countries.single.id, 1);
      expect(movie.sources.first.id, 520531);
      expect(movie.sources.first.url, raw['sources'][0]['url']);
      expect(movie.sources.first.isTrailer, isTrue);
      expect(movie.sources[1].isTrailer, isFalse);
      expect(movie.raw['playas'], '1');
      expect(movie.raw['downloadas'], '2');
      expect(movie.isSeries, isFalse);
      expect(movie.isChannel, isFalse);
      final restored = TitleRecord.fromJson(movie.toJson());
      expect(restored.sources[1].url, movie.sources[1].url);
      expect(restored.raw['playas'], '1');
      expect(
        restored.countries.single.toJson(),
        movie.countries.single.toJson(),
      );
    },
  );
}

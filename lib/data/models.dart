/// Public service metadata. Source visibility is not an authorization grant.
library;

import 'content_policy.dart';

Map<String, dynamic> _cleanJson(Map<String, dynamic> value) {
  final clean = ContentPolicy.sanitizeJson(value);
  return clean is Map ? Map<String, dynamic>.from(clean) : <String, dynamic>{};
}

String _text(dynamic value, [String fallback = '']) =>
    value is String || value is num || value is bool ? '$value' : fallback;
int _integer(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.isFinite ? value.toInt() : 0;
  return int.tryParse(_text(value).trim()) ?? 0;
}

double _decimal(dynamic value) {
  final parsed = value is num
      ? value.toDouble()
      : double.tryParse(_text(value).trim());
  return parsed != null && parsed.isFinite ? parsed : 0;
}

List<T> _records<T>(dynamic value, T Function(Map<String, dynamic>) parse) =>
    value is List
    ? value
          .whereType<Map>()
          .map((item) => parse(Map<String, dynamic>.from(item)))
          .toList()
    : <T>[];

class Tag {
  final int id;
  final String title, image;
  const Tag({this.id = 0, this.title = '', this.image = ''});
  factory Tag.fromJson(Map<String, dynamic> json) => Tag(
    id: _integer(json['id']),
    title: ContentPolicy.sanitizeText(_text(json['title'])),
    image: ContentPolicy.allowsUrl(_text(json['image']))
        ? _text(json['image'])
        : '',
  );
  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'image': image};
}

class MediaSource {
  final int id;
  final String quality, type, url;
  const MediaSource({
    this.id = 0,
    this.quality = '',
    this.type = '',
    this.url = '',
  });
  factory MediaSource.fromJson(Map<String, dynamic> json) => MediaSource(
    id: _integer(json['id']),
    quality: ContentPolicy.sanitizeText(_text(json['quality'])),
    type: _text(json['type']),
    url: ContentPolicy.allowsUrl(_text(json['url'])) ? _text(json['url']) : '',
  );
  bool get isTrailer =>
      RegExp(
        r'تیزر|تریلر|trailer|teaser',
        caseSensitive: false,
      ).hasMatch(quality) ||
      type.toLowerCase() == 'trailer';
  Map<String, dynamic> toJson() => {
    'id': id,
    'quality': quality,
    'type': type,
    'url': url,
  };
}

class EpisodeRecord {
  final int id;
  final String title, description, duration;
  final List<MediaSource> sources;
  final Map<String, dynamic> raw;
  const EpisodeRecord({
    this.id = 0,
    this.title = '',
    this.description = '',
    this.duration = '',
    this.sources = const [],
    this.raw = const {},
  });
  factory EpisodeRecord.fromJson(Map<String, dynamic> value) {
    final json = _cleanJson(value);
    return EpisodeRecord(
      id: _integer(json['id']),
      title: _text(json['title']),
      description: _text(json['description']),
      duration: _text(json['duration']),
      sources: _records(json['sources'], MediaSource.fromJson),
      raw: Map.unmodifiable(json),
    );
  }
  Map<String, dynamic> toJson() => {
    ...raw,
    'id': id,
    'title': title,
    'description': description,
    'duration': duration,
    'sources': sources.map((source) => source.toJson()).toList(),
  };
}

class SeasonRecord {
  final int id;
  final String title;
  final List<EpisodeRecord> episodes;
  final Map<String, dynamic> raw;
  const SeasonRecord({
    this.id = 0,
    this.title = '',
    this.episodes = const [],
    this.raw = const {},
  });
  factory SeasonRecord.fromJson(Map<String, dynamic> value) {
    final json = _cleanJson(value);
    return SeasonRecord(
      id: _integer(json['id']),
      title: _text(json['title']),
      episodes: _records(json['episodes'], EpisodeRecord.fromJson),
      raw: Map.unmodifiable(json),
    );
  }
  Map<String, dynamic> toJson() => {
    ...raw,
    'id': id,
    'title': title,
    'episodes': episodes.map((episode) => episode.toJson()).toList(),
  };
}

class TitleRecord {
  final int id, year;
  final String type, title, description, duration, classification, image, cover;
  final double imdb, rating;
  final List<Tag> genres, countries;
  final List<MediaSource> sources;
  final Map<String, dynamic> raw;
  const TitleRecord({
    this.id = 0,
    this.type = 'movie',
    this.title = '',
    this.description = '',
    this.duration = '',
    this.classification = '',
    this.image = '',
    this.cover = '',
    this.year = 0,
    this.imdb = 0,
    this.rating = 0,
    this.genres = const [],
    this.countries = const [],
    this.sources = const [],
    this.raw = const {},
  });
  factory TitleRecord.fromJson(Map<String, dynamic> value) {
    final json = _cleanJson(value);
    return TitleRecord(
      id: _integer(json['id'] ?? json['posted_id'] ?? json['movie_id']),
      type: _text(json['type'] ?? json['kind'], 'movie'),
      title: _text(json['title'] ?? json['name']),
      description: _text(json['description']),
      duration: _text(json['duration']),
      classification: _text(json['classification']),
      image: _text(json['image'] ?? json['img'] ?? json['poster']),
      cover: _text(json['cover']),
      year: _integer(json['year']),
      imdb: _decimal(json['imdb']),
      rating: _decimal(json['rating']),
      genres: _records(json['genres'], Tag.fromJson),
      countries: _records(json['country'] ?? json['countries'], Tag.fromJson),
      sources: _records(json['sources'], MediaSource.fromJson),
      raw: Map.unmodifiable(json),
    );
  }
  bool get isSeries => type == 'serie' || type == 'series';
  bool get isChannel => type == 'channel';
  Map<String, dynamic> toJson() => {
    ...raw,
    'id': id,
    'type': type,
    'title': title,
    'description': description,
    'duration': duration,
    'classification': classification,
    'image': image,
    'cover': cover,
    'year': year,
    'imdb': imdb,
    'rating': rating,
    'genres': genres.map((tag) => tag.toJson()).toList(),
    'country': countries.map((tag) => tag.toJson()).toList(),
    'sources': sources.map((source) => source.toJson()).toList(),
  };
}

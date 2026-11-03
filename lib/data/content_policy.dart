/// A presentation boundary for the independent, film/series-only client.
///
/// Catalog/media hosts are not blocked merely because the original service owns
/// them. The removed vendor destinations, announcements and navigation families
/// are rejected separately. This also applies to imported/previously saved data.
class ContentPolicy {
  static const _removedKeys = {
    'channel',
    'channels',
    'livechannel',
    'livechannels',
    'live_channels',
    'publicplaylist',
    'publicplaylists',
    'public_playlists',
    'playlists',
    'news',
    'news_url',
    'announcements',
    'announcement',
    'notifications',
    'notification',
    'update',
    'updates',
    'appupdate',
    'app_update',
    'app_version',
    'latest_version',
    'new_version',
    'version_code',
    'apk',
    'apk_url',
    'download_apk',
    'support',
    'support_url',
    'supportlink',
    'telegram',
    'telegram_url',
    'telegram_channel',
    'telegramaccount',
    'ads',
    'advertisements',
    'advertisement',
    'admob',
    'shop',
    'shop_url',
    'store_url',
    'melodybox',
    'norton',
  };
  static const _removedTypes = {
    'channel',
    'live',
    'live_channel',
    'news',
    'announcement',
    'advertisement',
    'ad',
    'app',
    'apk',
    'update',
    'support',
    'public_playlist',
  };
  static final _formatting = RegExp(
    r'[\u064b-\u065f\u0670\u06d6-\u06ed\u200b-\u200f\u202a-\u202e\u2066-\u2069\ufeff]',
  );
  static final _urls = RegExp(
    r'''(?:https?://|tg://|telegram://|www\.)[^\s<>"')]+''',
    caseSensitive: false,
  );
  static final _handles = RegExp(r'(^|[\s>(])@[a-zA-Z][a-zA-Z0-9_]{3,}');

  static String _decode(String value) {
    var result = value;
    for (var i = 0; i < 3; i++) {
      final decoded = result.replaceAllMapped(RegExp(r'(?:%[0-9a-fA-F]{2})+'), (
        match,
      ) {
        try {
          return Uri.decodeComponent(match.group(0)!);
        } on FormatException {
          return match.group(0)!;
        } on ArgumentError {
          return match.group(0)!;
        }
      });
      if (decoded == result) break;
      result = decoded;
    }
    return result
        .replaceAllMapped(
          RegExp(r'&#(x[0-9a-f]+|[0-9]+);', caseSensitive: false),
          (match) {
            final entity = match.group(1)!;
            final code = int.tryParse(
              entity.startsWith(RegExp('[xX]')) ? entity.substring(1) : entity,
              radix: entity.startsWith(RegExp('[xX]')) ? 16 : 10,
            );
            return code != null && code >= 0 && code <= 0x10ffff
                ? String.fromCharCode(code)
                : '';
          },
        )
        .replaceAll('&amp;', '&')
        .replaceAll('&nbsp;', ' ');
  }

  static String _normal(String value) =>
      _decode(value)
          .toLowerCase()
          .replaceAll('ي', 'ی')
          .replaceAll('ى', 'ی')
          .replaceAll('ك', 'ک')
          .replaceAll(_formatting, '');
  static String _compact(String value) =>
      _normal(value).replaceAll(RegExp(r'[\s_\-\u0640]+'), '');
  static bool _brand(String value) {
    final compact = _compact(value);
    return compact.contains('ملودیباکس') ||
        compact.contains('ملودیبکس') ||
        compact.contains('melodybox') ||
        compact.contains('melodibox') ||
        compact.contains('نورتون') ||
        compact.contains('نورتن') ||
        compact.contains('norton');
  }

  static bool allowsText(String value) {
    final normal = _normal(value);
    final compact = _compact(value);
    if (_brand(value) ||
        normal.contains('تلگرام') ||
        RegExp(r'\btelegram\b').hasMatch(normal) ||
        _handles.hasMatch(normal)) {
      return false;
    }
    if (RegExp(
          r'(دانلود|نصب|دریافت).{0,30}نسخه.{0,18}(برنامه|اپلیکیشن|سیمبا|مووی)',
          dotAll: true,
        ).hasMatch(normal) ||
        RegExp(
          r'(آپدیت|بروزرسانی|بهروز رسانی|بهروزرسانی).{0,20}(برنامه|اپلیکیشن|سیمبا)',
          dotAll: true,
        ).hasMatch(normal) ||
        RegExp(
          r'(install|download|update).{0,24}(latest|new).{0,12}(app|version)',
          dotAll: true,
        ).hasMatch(normal)) {
      return false;
    }
    if ((compact.contains('originalapp') ||
            compact.contains('moviebox') ||
            compact.contains('سیمبا')) &&
        (compact.contains('support') ||
            compact.contains('news') ||
            compact.contains('پشتیبانی'))) {
      return false;
    }
    return _urls
        .allMatches(_decode(value))
        .every((match) => allowsUrl(match.group(0)!));
  }

  static String sanitizeText(String value) =>
      allowsText(value) ? value.replaceAll(_formatting, '').trim() : '';

  static bool allowsUrl(String value) {
    if (value.isEmpty) return true;
    if (value != value.trim() || RegExp(r'[\x00-\x20\x7f]').hasMatch(value)) {
      return false;
    }
    final decoded = _decode(value);
    if (_brand(decoded) || decoded.contains('\\')) return false;
    try {
      final uri = Uri.parse(
        decoded.startsWith('www.') ? 'https://$decoded' : decoded,
      );
      if (uri.userInfo.isNotEmpty ||
          (uri.hasScheme &&
              !{'http', 'https'}.contains(uri.scheme.toLowerCase()))) {
        return false;
      }
      final host = uri.host.toLowerCase();
      if ([
        't.me',
        'telegram.me',
        'telegram.dog',
        'telegram.org',
        'telegra.ph',
      ].any((blocked) => host == blocked || host.endsWith('.$blocked'))) {
        return false;
      }
      final path = _normal(uri.path);
      if (RegExp(r'\.(apk|apks|xapk|aab|exe|msi|dmg|ipa)(/|$)')
          .hasMatch(path)) {
        return false;
      }
      if (RegExp(
        r'(^|/)(original[-_]?app|moviebox|simba)/(support|news|updates?|downloads?)(/|$)',
      ).hasMatch(path)) {
        return false;
      }
      if (RegExp(
        r'(^|/)(app[-_]?updates?|download[-_]?apk|latest[-_]?version)(/|$)',
      ).hasMatch(path)) {
        return false;
      }
      return true;
    } on FormatException {
      return false;
    }
  }

  static bool allowsApiPath(Uri uri) {
    final path = _normal(uri.path);
    final action = _normal(uri.queryParameters['action'] ?? '');
    if (RegExp(
      r'(^|/)(channels?|public[-_]?playlists?|news|updates?|support)(/|$)',
    ).hasMatch(path)) {
      return false;
    }
    return !{
      'showlist',
      'show-list_fav',
      'public-playlists',
      'playlist-items',
      'app-update',
      'app-news',
      'telegram',
      'support',
    }.contains(action);
  }

  static bool _removedRecord(Map<String, dynamic> value) {
    final type = _normal('${value['type'] ?? value['kind'] ?? ''}');
    if (_removedTypes.contains(type)) return true;
    for (final key in [
      'title',
      'name',
      'description',
      'note',
      'message',
      'text',
      'content',
      'body',
      'summary',
      'label',
    ]) {
      final text = value[key];
      if (text is String && !allowsText(text)) return true;
    }
    for (final key in [
      'link',
      'url',
      'website',
      'button_url',
      'download_url',
      'apk_url',
    ]) {
      final url = value[key];
      if (url is String && !allowsUrl(url)) return true;
    }
    return false;
  }

  static bool allowsTitleJson(Map<String, dynamic> json) =>
      !_removedRecord(json);

  /// Returns a fresh JSON tree; removed records/fields never become blank cards.
  static dynamic sanitizeJson(dynamic value) {
    if (value is Map) {
      final map = Map<String, dynamic>.from(value);
      if (_removedRecord(map)) return null;
      final result = <String, dynamic>{};
      for (final entry in map.entries) {
        if (_removedKeys.contains(_normal(entry.key))) continue;
        final item = sanitizeJson(entry.value);
        if (item != null) result[entry.key] = item;
      }
      return result;
    }
    if (value is List) {
      return value.map(sanitizeJson).where((v) => v != null).toList();
    }
    if (value is String) return allowsText(value) ? value : null;
    return value;
  }
}

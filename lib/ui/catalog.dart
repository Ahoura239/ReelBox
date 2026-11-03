import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/api_service.dart';
import '../data/catalog_discovery.dart';
import '../data/content_policy.dart';
import '../data/models.dart';
import '../media/player_page.dart';
import '../media/media_platform.dart';
import '../media/download_service.dart';
import '../state/app_state.dart';
import 'common.dart';
part 'catalog_extras.dart';

void _push(BuildContext context, Widget page) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

List<TitleRecord> _titles(dynamic value) => value is List
    ? value
          .whereType<Map>()
          .where(
            (row) =>
                ContentPolicy.allowsTitleJson(Map<String, dynamic>.from(row)),
          )
          .map((e) => TitleRecord.fromJson(Map<String, dynamic>.from(e)))
          .where((e) => e.id > 0 && !e.isChannel)
          .toList()
    : [];
List<Map<String, dynamic>> _maps(dynamic value) => value is List
    ? value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
    : [];
String _text(Map<String, dynamic> item, List<String> keys) {
  for (final key in keys) {
    if (item[key] != null && '${item[key]}'.isNotEmpty) return '${item[key]}';
  }
  return '';
}

int _id(Map<String, dynamic> item, List<String> keys) =>
    int.tryParse(_text(item, keys)) ?? 0;

class DiscoverPage extends StatefulWidget {
  const DiscoverPage({super.key});
  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage> {
  Future<Map<String, dynamic>>? _home;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _home ??= AppScope.read(context).api.home();
  }

  void _retry() => setState(() {
    _home = AppScope.read(context).api.home();
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: RefreshIndicator(
        onRefresh: () async {
          _retry();
          try {
            await _home;
          } catch (_) {}
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'REELBOX',
                          style: TextStyle(
                            letterSpacing: 4,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          tr(
                            context,
                            'Find your next story.',
                            'داستان بعدی‌ات را پیدا کن.',
                          ),
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () =>
                        _push(context, const DiscoveryDirectoryPage()),
                    tooltip: tr(context, 'Explore more', 'کشف بیشتر'),
                    icon: const Icon(Icons.explore_outlined),
                  ),
                  IconButton(
                    onPressed: () => _push(context, const SearchPage()),
                    tooltip: tr(context, 'Search', 'جستجو'),
                    icon: const Icon(Icons.search_rounded),
                  ),
                ],
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                spacing: 8,
                children: [
                  _shortcut(
                    context,
                    'Movies',
                    'فیلم‌ها',
                    Icons.movie_outlined,
                    const BrowsePage(),
                  ),
                  _shortcut(
                    context,
                    'Series',
                    'سریال‌ها',
                    Icons.video_library_outlined,
                    const BrowsePage(initialKind: 'serie'),
                  ),
                  _shortcut(
                    context,
                    'Anime & animation',
                    'انیمه و انیمیشن',
                    Icons.auto_awesome_outlined,
                    const BrowsePage(initialKind: 'mixed', initialGenre: 3),
                  ),
                  _shortcut(
                    context,
                    'Actors',
                    'بازیگران',
                    Icons.people_outline,
                    const ActorsPage(),
                  ),
                  _shortcut(
                    context,
                    'Countries',
                    'کشورها',
                    Icons.public,
                    const CountriesPage(),
                  ),
                ],
              ),
            ),
            AsyncResult<Map<String, dynamic>>(
              future: _home!,
              onRetry: _retry,
              builder: (data) {
                final rails = _maps(data['genres'])
                    .where(
                      (row) => ContentPolicy.allowsText(_text(row, ['title'])),
                    )
                    .toList();
                final featured = [
                  ..._titles(data['posters']),
                  ...rails.expand((g) => _titles(g['posters'])),
                ];
                final slides = _maps(data['slides'])
                    .where(
                      (slide) =>
                          ContentPolicy.allowsText(
                            _text(slide, ['title', 'name']),
                          ) &&
                          ContentPolicy.allowsUrl(_text(slide, ['url'])) &&
                          ContentPolicy.allowsUrl(_text(slide, ['image'])),
                    )
                    .toList();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (featured.isNotEmpty) _CinemaHero(title: featured.first),
                    if (slides.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                        child: SizedBox(
                          height: 100,
                          child: PageView(
                            children: [
                              for (final slide in slides)
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: InkWell(
                                    onTap: () => _openWeb(
                                      context,
                                      _text(slide, ['url']),
                                    ),
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        MediaArtwork(
                                          url: _text(slide, ['image']),
                                        ),
                                        const PositionedDirectional(
                                          end: 10,
                                          bottom: 10,
                                          child: Icon(
                                            Icons.open_in_new_rounded,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    for (final rail in rails)
                      if (_titles(rail['posters']).isNotEmpty)
                        PosterRail(
                          title: _text(rail, ['title']),
                          items: _titles(rail['posters']),
                          onMore: _id(rail, ['id']) > 0
                              ? () => _push(
                                  context,
                                  BrowsePage(
                                    initialKind: 'mixed',
                                    initialGenre: _id(rail, ['id']),
                                    heading: _text(rail, ['title']),
                                  ),
                                )
                              : null,
                        ),
                    if (featured.isEmpty)
                      EmptyView(
                        title: tr(
                          context,
                          'No discoveries yet',
                          'هنوز محتوایی وجود ندارد',
                        ),
                        onRetry: _retry,
                      ),
                  ],
                );
              },
            ),
            const _DiscoveryHomeShelves(),
            const _ContinueWatchingShelf(),
            for (final genre in AppScope.of(
              context,
            ).prefs.preferredGenres.take(3))
              _RecommendationRail(
                key: ValueKey('preference:$genre'),
                genre: genre,
              ),
            const SizedBox(height: 18),
          ],
        ),
      ),
    ),
  );
  Widget _shortcut(
    BuildContext context,
    String en,
    String fa,
    IconData icon,
    Widget page,
  ) => ActionChip(
    avatar: Icon(icon, size: 17),
    label: Text(tr(context, en, fa)),
    onPressed: () => _push(context, page),
  );
}

class _CinemaHero extends StatelessWidget {
  const _CinemaHero({required this.title});
  final TitleRecord title;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).width > 700 ? 400 : 345,
        child: Stack(
          fit: StackFit.expand,
          children: [
            MediaArtwork(
              url: title.cover.isNotEmpty ? title.cover : title.image,
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x18000000), Color(0xF5080A0F)],
                  stops: [.1, 1],
                ),
              ),
            ),
            PositionedDirectional(
              start: 22,
              end: 22,
              bottom: 24,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr(context, 'IN THE SPOTLIGHT', 'در کانون توجه'),
                    style: const TextStyle(
                      color: Color(0xFFFFA298),
                      letterSpacing: 2,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    title.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      height: 1.05,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    [
                      if (title.year > 0) '${title.year}',
                      if (title.imdb > 0) '★ ${title.imdb.toStringAsFixed(1)}',
                      ...title.genres.take(2).map((g) => g.title),
                    ].join('  ·  '),
                    style: const TextStyle(
                      color: Color(0xFFDDDEE3),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: () => goTitle(context, title),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: Text(
                          tr(context, 'Explore title', 'مشاهده عنوان'),
                        ),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white38),
                        ),
                        onPressed: () => _save(context, title),
                        icon: Icon(
                          AppScope.of(context)
                                  .hasSaved(title.id, kind: title.type)
                              ? Icons.check
                              : Icons.add,
                        ),
                        label: Text(tr(context, 'Watchlist', 'تماشای بعدی')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _save(BuildContext context, TitleRecord title) async {
  final state = AppScope.read(context);
  try {
    await state.toggleSaved(title);
  } catch (_) {
    if (context.mounted) {
      toast(
        context,
        tr(
          context,
          'Could not save locally. Please retry.',
          'ذخیره محلی ممکن نشد. دوباره تلاش کنید.',
        ),
      );
    }
  }
}

Future<void> _openWeb(BuildContext context, String value) async {
  final uri = Uri.tryParse(value);
  if (!ContentPolicy.allowsUrl(value) ||
      uri == null ||
      !{'http', 'https'}.contains(uri.scheme) ||
      uri.host.isEmpty) {
    toast(
      context,
      tr(context, 'This link is unavailable.', 'این پیوند در دسترس نیست.'),
    );
    return;
  }
  try {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw StateError('Unavailable');
    }
  } catch (_) {
    if (context.mounted) {
      toast(
        context,
        tr(context, 'Could not open this link.', 'باز کردن پیوند ممکن نشد.'),
      );
    }
  }
}

/// Paged requests retain successful pages and the raw server cursor.
class _PagedTitles extends StatefulWidget {
  const _PagedTitles({
    super.key,
    required this.load,
    this.firstPage = 1,
    this.headerBuilder,
  }) : header = null;
  final Future<List<TitleRecord>> Function(int page) load;
  final int firstPage;
  final Widget? header;
  final Widget Function()? headerBuilder;
  @override
  State<_PagedTitles> createState() => _PagedTitlesState();
}

class _PagedTitlesState extends State<_PagedTitles> {
  final _items = <TitleRecord>[];
  final _scroll = ScrollController();
  bool _busy = false, _end = false, _failed = false;
  late int _page;
  int _emptyPages = 0;
  @override
  void initState() {
    super.initState();
    _page = widget.firstPage;
    _scroll.addListener(_nearEnd);
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _nearEnd() {
    if (!_failed &&
        _emptyPages < 4 &&
        _scroll.hasClients &&
        _scroll.position.extentAfter < 450) {
      _load(automatic: true);
    }
  }

  void _fillViewport() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_busy && !_end && !_failed) _nearEnd();
    });
  }

  Future<void> _load({bool automatic = false}) async {
    if (_busy || _end || !mounted) return;
    if (!automatic) _emptyPages = 0;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final next = await widget.load(_page);
      if (!mounted) return;
      final known = _items.map((e) => e.libraryKey).toSet();
      final fresh = next
          .where(
            (e) =>
                e.id > 0 &&
                e.title.isNotEmpty &&
                !e.isChannel &&
                ContentPolicy.allowsTitleJson(e.toJson()) &&
                known.add(e.libraryKey),
          )
          .toList();
      setState(() {
        _items.addAll(fresh);
        _emptyPages = fresh.isEmpty ? _emptyPages + 1 : 0;
        // Never derive exhaustion/cursor from locally visible or deduped rows.
        _end = next is CatalogPage ? next.nextPage == null : next.isEmpty;
        _page = next is CatalogPage ? next.nextPage ?? _page : _page + 1;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _fillViewport();
      }
    }
  }

  Future<void> _refresh() async {
    if (_busy) return;
    setState(() {
      _items.clear();
      _end = false;
      _failed = false;
      _emptyPages = 0;
      _page = widget.firstPage;
    });
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final compact = AppScope.of(context).prefs.compactCatalog;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (widget.headerBuilder != null) widget.headerBuilder!(),
          if (widget.header != null) widget.header!,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${_items.length} ${tr(context, 'titles loaded', 'عنوان بارگذاری شده')}',
                  ),
                ),
                IconButton(
                  tooltip: compact
                      ? tr(context, 'Poster grid', 'نمای پوستر')
                      : tr(context, 'Compact rows', 'ردیف‌های فشرده'),
                  icon: Icon(compact ? Icons.grid_view : Icons.view_list),
                  onPressed: () async {
                    try {
                      final state = AppScope.read(context);
                      await state.updateSettings(
                        state.prefs.copyWith(compactCatalog: !compact),
                      );
                    } catch (_) {
                      if (context.mounted) {
                        toast(
                          context,
                          tr(
                            context,
                            'Could not save preference',
                            'ذخیره تنظیم ممکن نشد',
                          ),
                        );
                      }
                    }
                  },
                ),
              ],
            ),
          ),
          if (_items.isNotEmpty) PosterGrid(items: _items),
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_failed)
            EmptyView(
              title: tr(
                context,
                'Could not load titles',
                'بارگذاری عنوان‌ها ممکن نشد',
              ),
              message: tr(
                context,
                'Check your connection or try again later.',
                'اتصال را بررسی کنید یا بعداً دوباره تلاش کنید.',
              ),
              icon: Icons.wifi_off_rounded,
              onRetry: _load,
            ),
          if (!_busy && !_failed && _end && _items.isEmpty)
            EmptyView(
              title: tr(context, 'No titles found', 'عنوانی پیدا نشد'),
              message: tr(
                context,
                'Try a different search or filter.',
                'جستجو یا فیلتر دیگری را امتحان کنید.',
              ),
              onRetry: _refresh,
            ),
          if (!_busy && !_failed && !_end)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.expand_more),
                label: Text(tr(context, 'Load more', 'نمایش بیشتر')),
              ),
            ),
          if (_end && _items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text(
                  tr(
                    context,
                    'You’re all caught up',
                    'همه موارد نمایش داده شد',
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class BrowsePage extends StatefulWidget {
  const BrowsePage({
    super.key,
    this.initialKind = 'movie',
    this.initialGenre = 0,
    this.initialCountry = 0,
    this.initialOrder = 'created',
    this.heading,
  });
  final String initialKind, initialOrder;
  final int initialGenre, initialCountry;
  final String? heading;
  @override
  State<BrowsePage> createState() => _BrowsePageState();
}

class _BrowsePageState extends State<BrowsePage> {
  late String _kind;
  late int _genre, _country;
  String _order = 'created';
  Future<List<List<Tag>>>? _filters;
  @override
  void initState() {
    super.initState();
    _kind = {'movie', 'serie', 'mixed'}.contains(widget.initialKind)
        ? widget.initialKind
        : 'movie';
    _genre = widget.initialGenre;
    _country = widget.initialCountry;
    _order = widget.initialOrder;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _filters ??= _loadFilters();
  }

  Future<List<List<Tag>>> _loadFilters() async {
    final api = AppScope.read(context).api;
    return Future.wait([api.genres(), api.countries()]);
  }

  Future<List<TitleRecord>> _load(int page) {
    final api = AppScope.read(context).api;
    return api.catalog(
      kind: _kind,
      genre: _genre,
      country: _country,
      order: _order,
      page: page,
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.heading ?? tr(context, 'Browse', 'مرور')),
      actions: [
        IconButton(
          onPressed: () => _push(context, const SearchPage()),
          icon: const Icon(Icons.search),
          tooltip: tr(context, 'Search', 'جستجو'),
        ),
      ],
    ),
    body: Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
          child: Row(
            spacing: 8,
            children: [
              for (final option in [
                ('movie', 'Movies', 'فیلم‌ها'),
                ('serie', 'Series', 'سریال‌ها'),
                ('mixed', 'All titles', 'همه عنوان‌ها'),
                ('anime', 'Anime & animation', 'انیمه و انیمیشن'),
              ])
                ChoiceChip(
                  label: Text(tr(context, option.$2, option.$3)),
                  selected: option.$1 == 'anime'
                      ? _kind == 'mixed' && _genre == 3
                      : _kind == option.$1 &&
                            !(option.$1 == 'mixed' && _genre == 3),
                  onSelected: (_) => setState(() {
                    _kind = option.$1 == 'anime' ? 'mixed' : option.$1;
                    _genre = option.$1 == 'anime' ? 3 : 0;
                  }),
                ),
            ],
          ),
        ),
        FutureBuilder<List<List<Tag>>>(
          future: _filters,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return TextButton.icon(
                onPressed: () => setState(() {
                  _filters = _loadFilters();
                }),
                icon: const Icon(Icons.refresh),
                label: Text(
                  tr(
                    context,
                    'Retry loading filters',
                    'تلاش دوباره برای فیلترها',
                  ),
                ),
              );
            }
            if (!snapshot.hasData) return const LinearProgressIndicator();
            final genres = snapshot.data![0];
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  _filterMenu(
                    context,
                    tr(context, 'Genre', 'ژانر'),
                    _genre,
                    genres,
                    (value) => setState(() => _genre = value),
                  ),
                  _filterMenu(
                    context,
                    tr(context, 'Country', 'کشور'),
                    _country,
                    snapshot.data![1],
                    (value) => setState(() => _country = value),
                  ),
                  PopupMenuButton<String>(
                    tooltip: tr(context, 'Sort titles', 'مرتب‌سازی'),
                    initialValue: _order,
                    onSelected: (value) => setState(() => _order = value),
                    itemBuilder: (_) => [
                      for (final option in [
                        ('created', 'Recently added', 'تازه اضافه‌شده'),
                        ('rating', 'Audience rating', 'امتیاز کاربران'),
                        ('views', 'Most viewed', 'پربازدیدترین'),
                        ('imdb', 'IMDb rating', 'امتیاز IMDb'),
                        ('year', 'Release year', 'سال انتشار'),
                        ('title', 'Title', 'عنوان'),
                      ])
                        PopupMenuItem(
                          value: option.$1,
                          child: Text(tr(context, option.$2, option.$3)),
                        ),
                    ],
                    child: Chip(
                      avatar: const Icon(Icons.sort, size: 18),
                      label: Text(_sortLabel(context, _order)),
                    ),
                  ),
                  if (_genre != 0 || _country != 0 || _order != 'created')
                    ActionChip(
                      label: Text(tr(context, 'Reset', 'بازنشانی')),
                      avatar: const Icon(Icons.clear, size: 16),
                      onPressed: () => setState(() {
                        _genre = 0;
                        _country = 0;
                        _order = 'created';
                      }),
                    ),
                ],
              ),
            );
          },
        ),
        Expanded(
          child: _PagedTitles(
            key: ValueKey('$_kind:$_genre:$_country:$_order'),
            load: _load,
            firstPage: 0,
          ),
        ),
      ],
    ),
  );
}

String _sortLabel(BuildContext context, String order) => switch (order) {
  'rating' => tr(context, 'Audience rating', 'امتیاز کاربران'),
  'views' => tr(context, 'Most viewed', 'پربازدیدترین'),
  'imdb' => tr(context, 'IMDb rating', 'امتیاز IMDb'),
  'year' => tr(context, 'Release year', 'سال انتشار'),
  'title' => tr(context, 'Title', 'عنوان'),
  _ => tr(context, 'Recently added', 'تازه اضافه‌شده'),
};
Widget _filterMenu(
  BuildContext context,
  String label,
  int current,
  List<Tag> options,
  ValueChanged<int> changed,
) => PopupMenuButton<int>(
  tooltip: label,
  initialValue: current,
  onSelected: changed,
  itemBuilder: (_) => [
    PopupMenuItem(value: 0, child: Text(tr(context, 'All', 'همه'))),
    for (final tag in options)
      if (tag.id > 0 && ContentPolicy.allowsText(tag.title))
        PopupMenuItem(value: tag.id, child: Text(tag.title)),
  ],
  child: Chip(
    avatar: const Icon(Icons.tune_rounded, size: 17),
    label: Text(
      options.where((e) => e.id == current).firstOrNull?.title ??
          (current == 0 ? label : '$label: $current'),
    ),
  ),
);

class SearchPage extends StatefulWidget {
  const SearchPage({super.key, this.initialQuery = ''});
  final String initialQuery;
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _input = TextEditingController();
  Future<List<String>>? _trending;
  Future<CatalogPage>? _suggestions;
  Future<List<List<Tag>>>? _filterOptions;
  String _query = '';
  bool _english = false, _help = false;
  String _kind = 'mixed';
  int _year = 0, _genre = 0, _country = 0;
  double _rating = 0;
  DiscoverySearchFilter get _filter => DiscoverySearchFilter(
    kind: _kind,
    minimumYear: _year,
    minimumRating: _rating,
    genre: _genre,
    country: _country,
  );
  @override
  void initState() {
    super.initState();
    _query = widget.initialQuery.trim();
    _input.text = _query;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final api = AppScope.read(context).api;
    _trending ??= api.trending();
    _suggestions ??= CatalogDiscovery(api).suggestions();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _submit(String value) {
    final query = value.trim();
    _input.text = query;
    setState(() => _query = query);
    if (query.isNotEmpty && ContentPolicy.allowsText(query)) {
      AppScope.read(context).rememberSearch(query).catchError((Object _) {});
    }
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'Search', 'جستجو')),
        actions: [
          IconButton(
            tooltip: tr(context, 'Search help', 'راهنمای جستجو'),
            icon: const Icon(Icons.help_outline),
            onPressed: () => setState(() => _help = !_help),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) => Column(
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: constraints.maxHeight * .65,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: TextField(
                        controller: _input,
                        textInputAction: TextInputAction.search,
                        onSubmitted: _submit,
                        decoration: InputDecoration(
                          hintText: tr(
                            context,
                            'Titles in Persian or English',
                            'عنوان به فارسی یا انگلیسی',
                          ),
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIcon: IconButton(
                            onPressed: () => _submit(''),
                            tooltip: tr(
                              context,
                              'Clear search',
                              'پاک کردن جستجو',
                            ),
                            icon: const Icon(Icons.close),
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                      ),
                    ),
                    if (_help)
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          tr(
                            context,
                            'Search in Persian or use English search for the original title. Advanced filters apply to loaded search results, not a separate server query. Counts show loaded matching titles, not the server total.',
                            'به فارسی جستجو کنید یا برای عنوان اصلی جستجوی انگلیسی را انتخاب کنید. فیلترهای پیشرفته روی نتایج بارگذاری‌شده اعمال می‌شوند. شمارش، تعداد نتایج بارگذاری‌شده است نه کل سرویس.',
                          ),
                        ),
                      ),
                    ExpansionTile(
                      title: Text(
                        tr(context, 'Advanced filters', 'فیلترهای پیشرفته'),
                      ),
                      onExpansionChanged: (expanded) {
                        if (expanded && _filterOptions == null) {
                          setState(() {
                            _filterOptions = Future.wait([
                              state.api.genres(),
                              state.api.countries(),
                            ]);
                          });
                        }
                      },
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              FilterChip(
                                selected: _english,
                                label: Text(
                                  tr(
                                    context,
                                    'English search',
                                    'جستجوی انگلیسی',
                                  ),
                                ),
                                onSelected: (value) =>
                                    setState(() => _english = value),
                              ),
                              for (final option in [
                                ('mixed', 'All titles', 'همه عنوان‌ها'),
                                ('movie', 'Movies', 'فیلم‌ها'),
                                ('serie', 'Series', 'سریال‌ها'),
                              ])
                                ChoiceChip(
                                  label: Text(
                                    tr(context, option.$2, option.$3),
                                  ),
                                  selected: _kind == option.$1,
                                  onSelected: (_) =>
                                      setState(() => _kind = option.$1),
                                ),
                              PopupMenuButton<int>(
                                tooltip: tr(
                                  context,
                                  'Minimum year',
                                  'حداقل سال',
                                ),
                                onSelected: (value) =>
                                    setState(() => _year = value),
                                itemBuilder: (_) => [
                                  for (final value in [
                                    0,
                                    2020,
                                    2010,
                                    2000,
                                    1990,
                                  ])
                                    PopupMenuItem(
                                      value: value,
                                      child: Text(
                                        value == 0
                                            ? tr(
                                                context,
                                                'Any year',
                                                'همه سال‌ها',
                                              )
                                            : '$value+',
                                      ),
                                    ),
                                ],
                                child: Chip(
                                  label: Text(
                                    _year == 0
                                        ? tr(
                                            context,
                                            'Minimum year',
                                            'حداقل سال',
                                          )
                                        : '$_year+',
                                  ),
                                ),
                              ),
                              PopupMenuButton<double>(
                                tooltip: tr(
                                  context,
                                  'Minimum IMDb',
                                  'حداقل IMDb',
                                ),
                                onSelected: (value) =>
                                    setState(() => _rating = value),
                                itemBuilder: (_) => [
                                  for (final value in [0.0, 5.0, 6.0, 7.0, 8.0])
                                    PopupMenuItem(
                                      value: value,
                                      child: Text(
                                        value == 0
                                            ? tr(
                                                context,
                                                'Any rating',
                                                'همه امتیازها',
                                              )
                                            : '$value+',
                                      ),
                                    ),
                                ],
                                child: Chip(
                                  label: Text(
                                    _rating == 0
                                        ? tr(
                                            context,
                                            'Minimum IMDb',
                                            'حداقل IMDb',
                                          )
                                        : 'IMDb $_rating+',
                                  ),
                                ),
                              ),
                              ActionChip(
                                label: Text(
                                  tr(
                                    context,
                                    'Reset filters',
                                    'بازنشانی فیلترها',
                                  ),
                                ),
                                onPressed: () => setState(() {
                                  _english = false;
                                  _kind = 'mixed';
                                  _year = _genre = _country = 0;
                                  _rating = 0;
                                }),
                              ),
                            ],
                          ),
                        ),
                        if (_filterOptions != null)
                          FutureBuilder<List<List<Tag>>>(
                            future: _filterOptions,
                            builder: (context, snapshot) {
                              if (snapshot.hasError) {
                                return TextButton(
                                  onPressed: () => setState(() {
                                    _filterOptions = Future.wait([
                                      state.api.genres(),
                                      state.api.countries(),
                                    ]);
                                  }),
                                  child: Text(
                                    tr(
                                      context,
                                      'Retry loading filters',
                                      'تلاش دوباره برای فیلترها',
                                    ),
                                  ),
                                );
                              }
                              if (!snapshot.hasData) {
                                return const LinearProgressIndicator();
                              }
                              return Wrap(
                                spacing: 8,
                                children: [
                                  _filterMenu(
                                    context,
                                    tr(context, 'Genre', 'ژانر'),
                                    _genre,
                                    snapshot.data![0],
                                    (value) => setState(() => _genre = value),
                                  ),
                                  _filterMenu(
                                    context,
                                    tr(context, 'Country', 'کشور'),
                                    _country,
                                    snapshot.data![1],
                                    (value) => setState(() => _country = value),
                                  ),
                                ],
                              );
                            },
                          ),
                      ],
                    ),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: IconButton.filledTonal(
                          onPressed: () => _submit(_input.text),
                          tooltip: tr(context, 'Search', 'جستجو'),
                          icon: const Icon(Icons.arrow_forward_rounded),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: _query.isNotEmpty
                  ? _PagedTitles(
                      key: ValueKey('$_query:$_english:${_filter.key}'),
                      load: (page) => CatalogDiscovery(state.api).search(
                        _query,
                        page: page,
                        english: _english,
                        filter: _filter,
                      ),
                    )
                  : ListView(
                      children: [
                        if (state.searchHistory.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Row(
                              children: [
                                Expanded(
                                  child: _heading(
                                    context,
                                    tr(
                                      context,
                                      'Recent searches',
                                      'جستجوهای اخیر',
                                    ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () async {
                                    try {
                                      await state.clearSearchHistory();
                                    } catch (_) {
                                      if (context.mounted) {
                                        toast(
                                          context,
                                          tr(
                                            context,
                                            'Could not clear history',
                                            'پاک کردن تاریخچه ممکن نشد',
                                          ),
                                        );
                                      }
                                    }
                                  },
                                  child: Text(tr(context, 'Clear', 'پاک کردن')),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Wrap(
                              spacing: 8,
                              children: [
                                for (final query in state.searchHistory.where(
                                  ContentPolicy.allowsText,
                                ))
                                  InputChip(
                                    label: Text(query),
                                    avatar: const Icon(Icons.history, size: 16),
                                    onPressed: () => _submit(query),
                                    deleteButtonTooltipMessage:
                                        '${tr(context, 'Remove', 'حذف')} $query',
                                    onDeleted: () async {
                                      try {
                                        await state.removeSearch(query);
                                      } catch (_) {
                                        if (context.mounted) {
                                          toast(
                                            context,
                                            tr(
                                              context,
                                              'Could not remove search',
                                              'حذف جستجو ممکن نشد',
                                            ),
                                          );
                                        }
                                      }
                                    },
                                  ),
                              ],
                            ),
                          ),
                        ],
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: _heading(
                            context,
                            tr(
                              context,
                              'Suggested titles',
                              'عنوان‌های پیشنهادی',
                            ),
                          ),
                        ),
                        AsyncResult<CatalogPage>(
                          future: _suggestions!,
                          onRetry: () => setState(() {
                            _suggestions = CatalogDiscovery(state.api)
                                .suggestions();
                          }),
                          builder: (titles) => titles.isEmpty
                              ? EmptyView(
                                  title: tr(
                                    context,
                                    'No suggestions available',
                                    'پیشنهادی موجود نیست',
                                  ),
                                )
                              : PosterGrid(items: titles.take(12).toList()),
                        ),
                        TextButton.icon(
                          onPressed: () => _push(
                            context,
                            const RecommendationsPage(byYear: true),
                          ),
                          icon: const Icon(Icons.shuffle),
                          label: Text(
                            tr(context, 'Best by year', 'بهترین‌های هر سال'),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: _heading(
                            context,
                            tr(
                              context,
                              'Trending searches',
                              'جستجوهای پرطرفدار',
                            ),
                          ),
                        ),
                        AsyncResult<List<String>>(
                          future: _trending!,
                          onRetry: () => setState(() {
                            _trending = state.api.trending();
                          }),
                          builder: (terms) => Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                for (final term in terms.where(
                                  ContentPolicy.allowsText,
                                ))
                                  ActionChip(
                                    label: Text(term),
                                    avatar: const Icon(
                                      Icons.trending_up,
                                      size: 16,
                                    ),
                                    onPressed: () => _submit(term),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _heading(BuildContext context, String text) => Text(
  text,
  style: Theme.of(context).textTheme.titleLarge
      ?.copyWith(fontWeight: FontWeight.w700),
);

class TitlePage extends StatefulWidget {
  const TitlePage({super.key, required this.title});
  final TitleRecord title;
  @override
  State<TitlePage> createState() => _TitlePageState();
}

class _TitlePageState extends State<TitlePage> {
  Future<TitleRecord>? _detail;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _detail ??= _fetch();
  }

  Future<TitleRecord> _fetch() {
    final request = _fetchTitle();
    // Retry may fail before the next frame attaches FutureBuilder's listener.
    // Mark that error handled without changing the future the UI observes.
    request.ignore();
    return request;
  }

  Future<TitleRecord> _fetchTitle() async {
    if (widget.title.isChannel ||
        !ContentPolicy.allowsTitleJson(widget.title.toJson())) {
      throw const ApiException('This title is unavailable.');
    }
    final title = await AppScope.read(context).api.poster(widget.title.id);
    if (title.id <= 0 ||
        title.isChannel ||
        !ContentPolicy.allowsTitleJson(title.toJson())) {
      throw const ApiException('This title is unavailable.');
    }
    return title;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        ContentPolicy.allowsTitleJson(widget.title.toJson()) &&
                !widget.title.isChannel
            ? widget.title.title
            : tr(context, 'Unavailable title', 'عنوان در دسترس نیست'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    ),
    body: SingleChildScrollView(
      child: AsyncResult<TitleRecord>(
        future: _detail!,
        onRetry: () => setState(() {
          _detail = _fetch();
        }),
        builder: (title) => _TitleBody(
          key: ValueKey('${title.type}:${title.id}'),
          title: title,
        ),
      ),
    ),
  );
}

class _TitleBody extends StatelessWidget {
  const _TitleBody({super.key, required this.title});
  final TitleRecord title;
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final api = state.api;
    final genres = title.genres;
    final website = _text(title.raw, ['website']);
    final related = _titles(title.raw['related'] ?? title.raw['posters']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: MediaQuery.sizeOf(context).width > 700 ? 360 : 270,
          child: Stack(
            fit: StackFit.expand,
            children: [
              MediaArtwork(
                url: title.cover.isNotEmpty ? title.cover : title.image,
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Theme.of(context).scaffoldBackgroundColor,
                    ],
                  ),
                ),
              ),
              PositionedDirectional(
                start: 24,
                end: 24,
                bottom: 12,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: MediaArtwork(
                        url: title.image,
                        width: 100,
                        height: 148,
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title.isSeries
                                ? tr(context, 'SERIES', 'سریال')
                                : tr(context, 'MOVIE', 'فیلم'),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              letterSpacing: 2,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            title.title,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w900),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            [
                              if (title.year > 0) '${title.year}',
                              if (title.duration.isNotEmpty) title.duration,
                              if (title.classification.isNotEmpty)
                                title.classification,
                            ].join(' · '),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (title.imdb > 0)
                _badge(context, 'IMDb  ★ ${title.imdb.toStringAsFixed(1)}'),
              if (title.rating > 0)
                _badge(
                  context,
                  '${tr(context, 'Audience', 'کاربران')}  ${title.rating.toStringAsFixed(1)}',
                ),
              for (final country in title.countries)
                ActionChip(
                  label: Text(country.title),
                  onPressed: () => _push(
                    context,
                    BrowsePage(
                      initialKind: 'mixed',
                      initialCountry: country.id,
                      heading: country.title,
                    ),
                  ),
                ),
              for (final genre in genres)
                ActionChip(
                  label: Text(genre.title),
                  onPressed: () => _push(
                    context,
                    BrowsePage(
                      initialKind: 'mixed',
                      initialGenre: genre.id,
                      heading: genre.title,
                    ),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 8),
          child: Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: () => _save(context, title),
                icon: Icon(
                  state.hasSaved(title.id, kind: title.type)
                      ? Icons.bookmark
                      : Icons.bookmark_add_outlined,
                ),
                label: Text(
                  state.hasSaved(title.id, kind: title.type)
                      ? tr(context, 'In watchlist', 'در تماشای بعدی')
                      : tr(
                          context,
                          'Add to watchlist',
                          'افزودن به تماشای بعدی',
                        ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _shareTitle(context, title),
                icon: const Icon(Icons.share_outlined),
                label: Text(tr(context, 'Share', 'اشتراک‌گذاری')),
              ),
              if (website.isNotEmpty && ContentPolicy.allowsUrl(website))
                OutlinedButton.icon(
                  onPressed: () => _openWeb(context, website),
                  icon: const Icon(Icons.language),
                  label: Text(tr(context, 'Website', 'وب‌سایت')),
                ),
            ],
          ),
        ),
        if (title.description.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 16, 22, 8),
            child: _Synopsis(text: title.description),
          ),
        if (title.isSeries)
          _RemotePanel<SeasonRecord>(
            title: tr(context, 'Seasons & episodes', 'فصل‌ها و قسمت‌ها'),
            initiallyExpanded: true,
            load: () => api.seasons(title.id),
            builder: (seasons) {
              final playlist = seasons.expand((s) => s.episodes).toList();
              return Column(
                children: [
                  for (final season in seasons)
                    ExpansionTile(
                      title: Text(
                        season.title.isEmpty
                            ? '${tr(context, 'Season', 'فصل')} ${season.id}'
                            : season.title,
                      ),
                      subtitle: Text(
                        '${season.episodes.length} ${tr(context, 'episodes', 'قسمت')}',
                      ),
                      children: [
                        if (season.episodes.isEmpty)
                          EmptyView(
                            title: tr(
                              context,
                              'No episodes available',
                              'قسمتی موجود نیست',
                            ),
                          ),
                        for (final episode in season.episodes)
                          _EpisodeTile(
                            title: title,
                            episode: episode,
                            playlist: playlist,
                          ),
                      ],
                    ),
                ],
              );
            },
          ),
        if (!title.isSeries || title.sources.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
            child: _heading(context, tr(context, 'Sources', 'منابع پخش')),
          ),
        if (!title.isSeries || title.sources.isNotEmpty)
          _SourceList(title: title, sources: title.sources),
        _RemotePanel<Map<String, dynamic>>(
          title: tr(context, 'Cast & crew', 'بازیگران و عوامل'),
          load: () => api.roles(title.id),
          builder: (actors) => _PeopleGrid(items: actors),
        ),
        if (!title.isSeries)
          _RemotePanel<Map<String, dynamic>>(
            title: tr(context, 'Subtitles', 'زیرنویس‌ها'),
            load: () => api.subtitles('movie', title.id),
            builder: (items) => Column(
              children: [for (final item in items) _SubtitleTile(item: item)],
            ),
          ),
        _RemotePanel<Map<String, dynamic>>(
          title: tr(context, 'Comments', 'نظرات'),
          load: () => api.comments(title.id),
          builder: (comments) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  tr(
                    context,
                    'Public comments · read only',
                    'نظرات عمومی · فقط خواندنی',
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              for (final comment in comments) _CommentTile(comment: comment),
            ],
          ),
        ),
        if (related.isNotEmpty)
          PosterRail(
            title: tr(context, 'Related titles', 'عنوان‌های مرتبط'),
            items: related,
          ),
        if (title.genres.isNotEmpty)
          _RecommendationRail(
            genre: title.genres.first.id,
            excludeId: title.id,
          ),
        const SizedBox(height: 32),
      ],
    );
  }
}

Widget _badge(BuildContext context, String text) => DecoratedBox(
  decoration: BoxDecoration(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    borderRadius: BorderRadius.circular(8),
  ),
  child: Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    child: Text(
      text,
      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
    ),
  ),
);

class _Synopsis extends StatefulWidget {
  const _Synopsis({required this.text});
  final String text;
  @override
  State<_Synopsis> createState() => _SynopsisState();
}

class _SynopsisState extends State<_Synopsis> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _heading(context, tr(context, 'Story', 'داستان')),
      const SizedBox(height: 10),
      SelectableText(
        widget.text,
        maxLines: _expanded ? null : 6,
        style: TextStyle(
          height: 1.7,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      if (widget.text.length > 220)
        TextButton(
          onPressed: () => setState(() => _expanded = !_expanded),
          child: Text(
            _expanded
                ? tr(context, 'Show less', 'نمایش کمتر')
                : tr(context, 'Read more', 'بیشتر بخوانید'),
          ),
        ),
    ],
  );
}

class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile({
    required this.title,
    required this.episode,
    required this.playlist,
  });
  final TitleRecord title;
  final EpisodeRecord episode;
  final List<EpisodeRecord> playlist;
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final watched = state.history
        .where(
          (entry) =>
              entry.title.libraryKey == title.libraryKey &&
              entry.episodeId == episode.id,
        )
        .firstOrNull;
    return ExpansionTile(
      key: ValueKey('episode:${episode.id}'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: state.isEpisodeWatched(title.id, episode.id)
                ? tr(context, 'Mark unwatched', 'علامت ناتماشاشده')
                : tr(context, 'Mark watched', 'علامت تماشاشده'),
            icon: Icon(
              state.isEpisodeWatched(title.id, episode.id)
                  ? Icons.check_circle
                  : Icons.radio_button_unchecked,
            ),
            onPressed: () async {
              try {
                await state.setEpisodeWatched(
                  title,
                  episode,
                  !state.isEpisodeWatched(title.id, episode.id),
                );
              } catch (_) {
                if (context.mounted) {
                  toast(
                    context,
                    tr(
                      context,
                      'Could not save watched status',
                      'ذخیره وضعیت تماشا ممکن نشد',
                    ),
                  );
                }
              }
            },
          ),
          const Icon(Icons.expand_more),
        ],
      ),
      leading: SizedBox(
        width: 52,
        height: 42,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: MediaArtwork(url: _text(episode.raw, ['image'])),
        ),
      ),
      title: Text(
        episode.title.isEmpty
            ? '${tr(context, 'Episode', 'قسمت')} ${episode.id}'
            : episode.title,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            state.isEpisodeWatched(title.id, episode.id)
                ? tr(context, 'Watched', 'تماشاشده')
                : tr(context, 'Unwatched', 'تماشانشده'),
          ),
          if (episode.duration.isNotEmpty) Text(episode.duration),
          if (watched != null) ...[
            const SizedBox(height: 5),
            LinearProgressIndicator(value: watched.progress),
            const SizedBox(height: 3),
            Text(
              '${(watched.progress * 100).round()}% ${tr(context, 'watched', 'تماشاشده')}',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ],
      ),
      children: [
        if (episode.description.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(episode.description),
          ),
        _SourceList(
          title: title,
          sources: episode.sources,
          episode: episode,
          playlist: playlist,
        ),
        _RemotePanel<Map<String, dynamic>>(
          title: tr(context, 'Episode subtitles', 'زیرنویس قسمت'),
          load: () => state.api.subtitles('episode', episode.id),
          builder: (items) => Column(
            children: [for (final item in items) _SubtitleTile(item: item)],
          ),
        ),
      ],
    );
  }
}

class _SourceList extends StatelessWidget {
  const _SourceList({
    required this.title,
    required this.sources,
    this.episode,
    this.playlist = const [],
  });
  final TitleRecord title;
  final List<MediaSource> sources;
  final EpisodeRecord? episode;
  final List<EpisodeRecord> playlist;
  @override
  Widget build(BuildContext context) {
    final visible = sources
        .where(
          (s) =>
              ContentPolicy.allowsUrl(s.url) &&
              ContentPolicy.allowsText(s.quality) &&
              !(AppScope.of(context).prefs.hideTrailers && s.isTrailer),
        )
        .toList();
    if (visible.isEmpty) {
      return EmptyView(
        title: tr(
          context,
          'No public sources available',
          'منبع عمومی موجود نیست',
        ),
        message: tr(
          context,
          'The service has not returned a playable source for this title.',
          'سرویس برای این عنوان منبع پخش برنگردانده است.',
        ),
      );
    }
    return Column(
      children: [
        if (visible.any((s) => !s.isTrailer && s.url.isNotEmpty))
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              key: const ValueKey('play-preferred'),
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(
                tr(context, 'Play preferred source', 'پخش منبع ترجیحی'),
              ),
              onPressed: () async {
                final quality = AppScope.read(context).prefs.defaultQuality;
                final playable = visible
                    .where((s) => !s.isTrailer && s.url.isNotEmpty)
                    .toList();
                var preferred =
                    playable
                        .where(
                          (s) => RegExp(
                            r'(^|\D)' + RegExp.escape(quality) + r'(p\b|\D|$)',
                            caseSensitive: false,
                          ).hasMatch(s.quality),
                        )
                        .firstOrNull ??
                    playable.first;
                if (quality == 'ask') {
                  final selected = await showDialog<MediaSource>(
                    context: context,
                    builder: (context) => SimpleDialog(
                      title: Text(
                        tr(context, 'Choose a source', 'انتخاب منبع'),
                      ),
                      children: [
                        for (final option in playable)
                          SimpleDialogOption(
                            onPressed: () => Navigator.pop(context, option),
                            child: Text(
                              option.quality.isEmpty
                                  ? tr(context, 'Original source', 'منبع اصلی')
                                  : option.quality,
                            ),
                          ),
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(tr(context, 'Cancel', 'لغو')),
                        ),
                      ],
                    ),
                  );
                  if (selected == null || !context.mounted) return;
                  preferred = selected;
                }
                if (!context.mounted) return;
                await _play(
                  context,
                  title,
                  preferred,
                  episode: episode,
                  playlist: playlist,
                  alternatives: visible,
                );
              },
            ),
          ),
        for (final source in visible)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 6),
            child: Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          source.isTrailer
                              ? Icons.local_play_outlined
                              : Icons.high_quality_outlined,
                          size: 21,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            source.quality.isNotEmpty
                                ? source.quality
                                : tr(context, 'Original source', 'منبع اصلی'),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (source.type.isNotEmpty)
                          _badge(context, source.type.toUpperCase()),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 2,
                      runSpacing: 2,
                      children: [
                        IconButton.filledTonal(
                          onPressed: source.url.isEmpty
                              ? null
                              : () => _play(
                                  context,
                                  title,
                                  source,
                                  episode: episode,
                                  playlist: playlist,
                                  alternatives: visible,
                                ),
                          tooltip: tr(context, 'Play', 'پخش'),
                          icon: const Icon(Icons.play_arrow_rounded),
                        ),
                        IconButton(
                          onPressed: source.url.isEmpty
                              ? null
                              : () =>
                                    _download(context, title, source, episode),
                          tooltip: tr(context, 'Download', 'دانلود'),
                          icon: const Icon(Icons.download_outlined),
                        ),
                        IconButton(
                          onPressed: source.url.isEmpty
                              ? null
                              : () => _copy(context, source.url),
                          tooltip: tr(
                            context,
                            'Copy source URL',
                            'کپی پیوند منبع',
                          ),
                          icon: const Icon(Icons.copy_all_outlined),
                        ),
                        IconButton(
                          onPressed: source.url.isEmpty
                              ? null
                              : () => _share(context, source.url, title.title),
                          tooltip: tr(context, 'Share source', 'اشتراک منبع'),
                          icon: const Icon(Icons.share_outlined),
                        ),
                        IconButton(
                          onPressed: source.url.isEmpty
                              ? null
                              : () => _openWeb(context, source.url),
                          tooltip: tr(
                            context,
                            'Open externally',
                            'باز کردن بیرونی',
                          ),
                          icon: const Icon(Icons.open_in_new_rounded),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

Future<void> _play(
  BuildContext context,
  TitleRecord title,
  MediaSource source, {
  EpisodeRecord? episode,
  List<EpisodeRecord> playlist = const [],
  List<MediaSource> alternatives = const [],
}) async {
  if (!ContentPolicy.allowsTitleJson(title.toJson()) ||
      !ContentPolicy.allowsUrl(source.url)) {
    toast(
      context,
      tr(context, 'This source is unavailable.', 'این منبع در دسترس نیست.'),
    );
    return;
  }
  final type = source.type.toLowerCase();
  final uri = Uri.tryParse(source.url);
  if (type.contains('youtube') ||
      type.contains('embed') ||
      uri?.host == 'youtu.be' ||
      (uri?.host.endsWith('youtube.com') ?? false)) {
    try {
      if (MediaPlatform.supported) {
        if (await MediaPlatform.invoke<bool>('openEmbedded', {
              'url': source.url,
              'title': title.title,
            }) !=
            true) {
          throw StateError('Unavailable');
        }
      } else {
        await _openWeb(context, source.url);
      }
    } catch (_) {
      if (context.mounted) {
        toast(
          context,
          tr(
            context,
            'Could not open embedded video.',
            'باز کردن ویدیوی جاسازی‌شده ممکن نشد.',
          ),
        );
      }
    }
    return;
  }
  if (uri == null ||
      !{'http', 'https'}.contains(uri.scheme) ||
      uri.host.isEmpty) {
    toast(
      context,
      tr(
        context,
        'This source URL is unavailable.',
        'پیوند این منبع در دسترس نیست.',
      ),
    );
    return;
  }
  if (AppScope.read(context).prefs.externalPlayer) {
    try {
      if (MediaPlatform.supported) {
        final state = AppScope.read(context);
        final previous = state.history
            .where(
              (entry) =>
                  entry.title.libraryKey == title.libraryKey &&
                  entry.episodeId == episode?.id,
            )
            .firstOrNull;
        await MediaPlatform.openExternal(
          source.url,
          packageName: state.prefs.externalPlayerPackage,
          title: title.title,
          position: state.prefs.resumePlayback && previous != null
              ? Duration(
                  milliseconds: (previous.positionSeconds * 1000).round(),
                )
              : null,
        );
      } else {
        await _openWeb(context, source.url);
      }
    } catch (_) {
      if (context.mounted) {
        toast(
          context,
          tr(
            context,
            'No external player could open this source.',
            'پخش‌کننده خارجی نتوانست این منبع را باز کند.',
          ),
        );
      }
    }
    return;
  }
  _push(
    context,
    PlayerPage(
      title: title,
      source: source,
      episode: episode,
      playlist: playlist,
      alternatives: alternatives,
    ),
  );
}

Future<void> _download(
  BuildContext context,
  TitleRecord title,
  MediaSource source,
  EpisodeRecord? episode,
) async {
  if (!ContentPolicy.allowsTitleJson(title.toJson()) ||
      !ContentPolicy.allowsUrl(source.url)) {
    return;
  }
  if (RegExp('youtube|embed', caseSensitive: false).hasMatch(source.type)) {
    toast(
      context,
      tr(
        context,
        'Embedded sources cannot be downloaded. Open the source externally.',
        'منابع جاسازی‌شده قابل دانلود نیستند. منبع را بیرونی باز کنید.',
      ),
    );
    return;
  }
  try {
    await DownloadService.instance.enqueue(
      title: title,
      source: source,
      episode: episode,
    );
    if (context.mounted) {
      toast(
        context,
        tr(context, 'Download added to queue', 'دانلود به صف اضافه شد'),
      );
    }
  } catch (_) {
    if (context.mounted) {
      toast(
        context,
        tr(
          context,
          'Could not queue this download. Choose a direct video file and check download settings.',
          'افزودن دانلود ممکن نشد. فایل ویدیویی مستقیم انتخاب کنید و تنظیمات دانلود را بررسی کنید.',
        ),
      );
    }
  }
}

Future<void> _copy(BuildContext context, String text) async {
  if (!ContentPolicy.allowsText(text)) return;
  try {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      toast(context, tr(context, 'Copied to clipboard', 'در کلیپ‌بورد کپی شد'));
    }
  } catch (_) {
    if (context.mounted) {
      toast(
        context,
        tr(context, 'Could not copy this link', 'کپی پیوند ممکن نشد'),
      );
    }
  }
}

Future<void> _shareTitle(BuildContext context, TitleRecord title) =>
    _share(context, title.title, title.title);
Future<void> _share(BuildContext context, String text, String title) async {
  if (!ContentPolicy.allowsText(text) || !ContentPolicy.allowsText(title)) {
    return;
  }
  final box = context.findRenderObject();
  final origin = box is RenderBox && box.hasSize
      ? box.localToGlobal(Offset.zero) & box.size
      : null;
  try {
    await SharePlus.instance.share(
      ShareParams(
        text: text == title ? title : '$title\n$text',
        title: title,
        sharePositionOrigin: origin,
      ),
    );
  } catch (_) {
    if (context.mounted) {
      toast(
        context,
        tr(
          context,
          'Sharing is unavailable on this device.',
          'اشتراک‌گذاری در این دستگاه در دسترس نیست.',
        ),
      );
    }
  }
}

/// Optional sections load on demand, independently of the primary title request.
class _RemotePanel<T> extends StatefulWidget {
  const _RemotePanel({
    required this.title,
    required this.load,
    required this.builder,
    this.initiallyExpanded = false,
  });
  final String title;
  final Future<List<T>> Function() load;
  final Widget Function(List<T>) builder;
  final bool initiallyExpanded;
  @override
  State<_RemotePanel<T>> createState() => _RemotePanelState<T>();
}

class _RemotePanelState<T> extends State<_RemotePanel<T>> {
  Future<List<T>>? _future;
  @override
  void initState() {
    super.initState();
    if (widget.initiallyExpanded) _future = widget.load();
  }

  @override
  Widget build(BuildContext context) => ExpansionTile(
    initiallyExpanded: widget.initiallyExpanded,
    title: Text(
      widget.title,
      style: const TextStyle(fontWeight: FontWeight.w700),
    ),
    onExpansionChanged: (expanded) {
      if (expanded && _future == null) {
        setState(() {
          _future = widget.load();
        });
      }
    },
    children: [
      if (_future != null)
        AsyncResult<List<T>>(
          future: _future!,
          onRetry: () => setState(() {
            _future = widget.load();
          }),
          builder: (items) => items.isEmpty
              ? EmptyView(
                  title: tr(
                    context,
                    'Nothing available here',
                    'موردی در دسترس نیست',
                  ),
                )
              : widget.builder(items),
        ),
    ],
  );
}

class _SubtitleTile extends StatelessWidget {
  const _SubtitleTile({required this.item});
  final Map<String, dynamic> item;
  @override
  Widget build(BuildContext context) {
    final url = _text(item, ['url', 'link', 'file']);
    return ListTile(
      leading: const Icon(Icons.subtitles_outlined),
      title: Text(_text(item, ['title', 'language', 'name'])),
      subtitle: Text(
        tr(
          context,
          'Open or save with your browser',
          'باز کردن یا ذخیره با مرورگر',
        ),
      ),
      onTap: url.isEmpty ? null : () => _openWeb(context, url),
      trailing: IconButton(
        onPressed: url.isEmpty ? null : () => _copy(context, url),
        tooltip: tr(context, 'Copy subtitle URL', 'کپی پیوند زیرنویس'),
        icon: const Icon(Icons.copy),
      ),
    );
  }
}

String _commentBody(Map<String, dynamic> item) {
  final content = _text(item, ['content', 'comment', 'text', 'pasokh']);
  if (content.isEmpty) return '';
  try {
    return utf8.decode(base64.decode(content.replaceAll(RegExp(r'\s'), '')));
  } catch (_) {
    return content;
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.comment});
  final Map<String, dynamic> comment;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.person_outline, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _text(comment, ['user', 'name', 'username']),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  _text(comment, ['created', 'date']),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
            const SizedBox(height: 10),
            SelectableText(_commentBody(comment)),
            if (_id(comment, ['id']) > 0)
              _RemotePanel<Map<String, dynamic>>(
                title: tr(context, 'Replies', 'پاسخ‌ها'),
                load: () async => _maps(
                  await AppScope.read(context).api.get(
                    '${AppScope.read(context).api.hostRoot}/api-user/filmahang/star.php',
                    query: {
                      'key': ApiService.actorKey,
                      'action': 'pasokh',
                      'cid': _id(comment, ['id']),
                    },
                  ),
                ),
                builder: (items) => Column(
                  children: [
                    for (final reply in items)
                      ListTile(
                        title: Text(_text(reply, ['user', 'name', 'username'])),
                        subtitle: Text(_commentBody(reply)),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class _RecommendationRail extends StatefulWidget {
  const _RecommendationRail({
    super.key,
    required this.genre,
    this.excludeId = 0,
  });
  final int genre, excludeId;
  @override
  State<_RecommendationRail> createState() => _RecommendationRailState();
}

class _RecommendationRailState extends State<_RecommendationRail> {
  Future<List<TitleRecord>>? _future;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= AppScope.read(context).api.recommended(widget.genre);
  }

  @override
  Widget build(BuildContext context) => AsyncResult<List<TitleRecord>>(
    future: _future!,
    onRetry: () => setState(() {
      _future = AppScope.read(context).api.recommended(widget.genre);
    }),
    builder: (items) => items.where((e) => e.id != widget.excludeId).isEmpty
        ? const SizedBox.shrink()
        : PosterRail(
            title: widget.excludeId > 0
                ? tr(context, 'More like this', 'مشابه این عنوان')
                : tr(
                    context,
                    'Picked for your taste',
                    'پیشنهاد بر اساس سلیقه شما',
                  ),
            items: items.where((e) => e.id != widget.excludeId).toList(),
            onMore: () =>
                _push(context, RecommendationsPage(genre: widget.genre)),
          ),
  );
}

class RecommendationsPage extends StatelessWidget {
  const RecommendationsPage({super.key, this.genre = 0, this.byYear = false});
  final int genre;
  final bool byYear;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        genre > 0
            ? tr(context, 'Recommended', 'پیشنهادها')
            : byYear
            ? tr(context, 'Best by year', 'بهترین‌های هر سال')
            : tr(context, 'Surprise me', 'یک پیشنهاد تازه'),
      ),
    ),
    body: _PagedTitles(
      load: (page) => genre > 0
          ? AppScope.read(context).api.recommended(genre, page: page)
          : AppScope.read(context).api.bestRandom(byYear: byYear, page: page),
    ),
  );
}

part of 'catalog.dart';

/// Account-free discovery, using the observed routes rather than invented tags.
class DiscoveryDirectoryPage extends StatelessWidget {
  const DiscoveryDirectoryPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr(context, 'Explore more', 'کشف بیشتر'))),
    body: ListView(
      children: [
        for (final preset in <(String, String, String, int, String)>[
          ('Best titles', 'بهترین عنوان‌ها', 'mixed', 0, 'rating'),
          ('Newest titles', 'جدیدترین عنوان‌ها', 'mixed', 0, 'created'),
          ('Popular titles', 'عنوان‌های محبوب', 'mixed', 0, 'rating'),
          ('Top 250 movies', '۲۵۰ فیلم برتر', 'movie', 0, 'imdb'),
          ('Top 250 series', '۲۵۰ سریال برتر', 'serie', 0, 'imdb'),
          ('Korean series', 'سریال‌های کره‌ای', 'serie', 36, 'created'),
          (
            'Chinese / Japanese series',
            'سریال‌های چینی / ژاپنی',
            'serie',
            37,
            'created',
          ),
          ('Turkish series', 'سریال‌های ترکی', 'serie', 35, 'created'),
          ('Indian series', 'سریال‌های هندی', 'serie', 38, 'created'),
          ('Indian movies', 'فیلم‌های هندی', 'movie', 38, 'created'),
          (
            'Newest movies by year',
            'جدیدترین فیلم‌ها بر اساس سال',
            'movie',
            0,
            'year',
          ),
          (
            'Newest series by year',
            'جدیدترین سریال‌ها بر اساس سال',
            'serie',
            0,
            'year',
          ),
          ('Most-viewed movies', 'پربازدیدترین فیلم‌ها', 'movie', 0, 'views'),
          ('Most-viewed series', 'پربازدیدترین سریال‌ها', 'serie', 0, 'views'),
        ])
          ListTile(
            leading: const Icon(Icons.movie_filter_outlined),
            title: Text(tr(context, preset.$1, preset.$2)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _push(
              context,
              BrowsePage(
                initialKind: preset.$3,
                initialGenre: preset.$4,
                initialOrder: preset.$5,
                heading: tr(context, preset.$1, preset.$2),
              ),
            ),
          ),
        const Divider(),
        for (final entry in <(String, String, Widget)>[
          (
            'Miniseries',
            'مینی سریال',
            const SearchPage(initialQuery: 'مینی سریال'),
          ),
          ('Sitcoms', 'سیتکام', const SearchPage(initialQuery: 'سیتکام')),
          ('Actors', 'بازیگران', const ActorsPage()),
          ('Countries', 'کشورها', const CountriesPage()),
          (
            'Themes & subjects',
            'موضوع‌ها',
            const SubjectDirectoryPage(kind: DiscoveryDirectory.themes),
          ),
          (
            'Franchises',
            'فرنچایزها',
            const SubjectDirectoryPage(kind: DiscoveryDirectory.franchises),
          ),
          (
            'Most-shared titles',
            'عنوان‌های بیشتر اشتراک‌گذاشته‌شده',
            const SharedTitlesPage(),
          ),
          (
            'New discoveries',
            'تازه‌های کشف',
            const SharedTitlesPage(newest: true),
          ),
          ('Editor picks', 'پیشنهاد سردبیر', const CuratedPage()),
          (
            'Best collections',
            'مجموعه‌های برتر',
            const CuratedPage(best: true),
          ),
          (
            'Best by year',
            'بهترین‌های هر سال',
            const RecommendationsPage(byYear: true),
          ),
        ])
          ListTile(
            title: Text(tr(context, entry.$1, entry.$2)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _push(context, entry.$3),
          ),
      ],
    ),
  );
}

class _DiscoveryHomeShelves extends StatefulWidget {
  const _DiscoveryHomeShelves();
  @override
  State<_DiscoveryHomeShelves> createState() => _DiscoveryHomeShelvesState();
}

class _DiscoveryHomeShelvesState extends State<_DiscoveryHomeShelves> {
  Future<List<Map<String, dynamic>>>? _actors;
  Future<List<Tag>>? _countries;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final api = AppScope.read(context).api;
    _actors ??= api.actors();
    _countries ??= api.countries();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 12, 8),
        child: Row(
          children: [
            Expanded(
              child: _heading(
                context,
                tr(context, 'Popular actors', 'بازیگران محبوب'),
              ),
            ),
            TextButton(
              onPressed: () => _push(context, const ActorsPage()),
              child: Text(tr(context, 'View all', 'نمایش همه')),
            ),
          ],
        ),
      ),
      AsyncResult<List<Map<String, dynamic>>>(
        future: _actors!,
        onRetry: () => setState(() {
          _actors = AppScope.read(context).api.actors();
        }),
        builder: (items) => items.isEmpty
            ? const SizedBox.shrink()
            : SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: _PeopleGrid(items: items.take(12).toList()),
              ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 12, 8),
        child: Row(
          children: [
            Expanded(
              child: _heading(
                context,
                tr(context, 'Discover by country', 'کشف بر اساس کشور'),
              ),
            ),
            TextButton(
              onPressed: () => _push(context, const CountriesPage()),
              child: Text(tr(context, 'View all', 'نمایش همه')),
            ),
          ],
        ),
      ),
      AsyncResult<List<Tag>>(
        future: _countries!,
        onRetry: () => setState(() {
          _countries = AppScope.read(context).api.countries();
        }),
        builder: (items) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final country
                  in items
                      .where(
                        (tag) =>
                            tag.id > 0 && ContentPolicy.allowsText(tag.title),
                      )
                      .take(16))
                ActionChip(
                  label: Text(country.title),
                  avatar: const Icon(Icons.public, size: 16),
                  onPressed: () => _push(
                    context,
                    BrowsePage(
                      initialKind: 'mixed',
                      initialCountry: country.id,
                      heading: country.title,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ],
  );
}

class CountriesPage extends StatefulWidget {
  const CountriesPage({super.key});
  @override
  State<CountriesPage> createState() => _CountriesPageState();
}

class _CountriesPageState extends State<CountriesPage> {
  Future<List<Tag>>? _future;
  String _query = '';
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= AppScope.read(context).api.countries();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr(context, 'Countries', 'کشورها'))),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            onChanged: (value) =>
                setState(() => _query = value.trim().toLowerCase()),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: tr(context, 'Find a country', 'جستجوی کشور'),
            ),
          ),
        ),
        Expanded(
          child: AsyncResult<List<Tag>>(
            future: _future!,
            onRetry: () => setState(() {
              _future = AppScope.read(context).api.countries();
            }),
            builder: (items) {
              final visible = items
                  .where(
                    (tag) =>
                        tag.id > 0 &&
                        ContentPolicy.allowsText(tag.title) &&
                        tag.title.toLowerCase().contains(_query),
                  )
                  .toList();
              return visible.isEmpty
                  ? EmptyView(
                      title: tr(
                        context,
                        'No countries found',
                        'کشوری پیدا نشد',
                      ),
                    )
                  : ListView(
                      children: [
                        for (final country in visible)
                          ListTile(
                            leading: const Icon(Icons.public),
                            title: Text(country.title),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _push(
                              context,
                              BrowsePage(
                                initialKind: 'mixed',
                                initialCountry: country.id,
                                heading: country.title,
                              ),
                            ),
                          ),
                      ],
                    );
            },
          ),
        ),
      ],
    ),
  );
}

class ActorsPage extends StatefulWidget {
  const ActorsPage({super.key});
  @override
  State<ActorsPage> createState() => _ActorsPageState();
}

class _ActorsPageState extends State<ActorsPage> {
  String query = '';
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr(context, 'Actors', 'بازیگران'))),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: tr(context, 'Search actors', 'جستجوی بازیگران'),
            ),
            onSubmitted: (value) => setState(() => query = value.trim()),
          ),
        ),
        Expanded(
          child: _PagedObjects(
            key: ValueKey(query),
            load: (page) =>
                AppScope.read(context).api.actors(page: page, search: query),
            builder: (items) => _PeopleGrid(items: items),
          ),
        ),
      ],
    ),
  );
}

class _PeopleGrid extends StatelessWidget {
  const _PeopleGrid({required this.items});
  final List<Map<String, dynamic>> items;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 12,
    children: [
      for (final person
          in items
              .map(actorMetadata)
              .where((row) => ContentPolicy.allowsText('${row['name']}')))
        SizedBox(
          width: 125,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _push(context, ActorTitlesPage(person: person)),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  ClipOval(
                    child: SizedBox(
                      width: 80,
                      height: 80,
                      child: _text(person, ['image']).isEmpty
                          ? const ColoredBox(
                              color: Color(0xFF252733),
                              child: Icon(Icons.person_outline, size: 44),
                            )
                          : MediaArtwork(url: _text(person, ['image'])),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _text(person, ['name']),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                  if (_text(person, ['role']).isNotEmpty)
                    Text(
                      ContentPolicy.sanitizeText(_text(person, ['role'])),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                ],
              ),
            ),
          ),
        ),
    ],
  );
}

class ActorTitlesPage extends StatefulWidget {
  const ActorTitlesPage({super.key, required this.person});
  final Map<String, dynamic> person;
  @override
  State<ActorTitlesPage> createState() => _ActorTitlesPageState();
}

class _ActorTitlesPageState extends State<ActorTitlesPage> {
  ActorFilmography? _loader;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final person = actorMetadata(widget.person);
    _loader ??= ActorFilmography(
      CatalogDiscovery(AppScope.read(context).api),
      id: _id(person, ['id']),
      name: _text(person, ['name']),
    );
  }

  @override
  Widget build(BuildContext context) {
    final person = actorMetadata(widget.person);
    return Scaffold(
      appBar: AppBar(
        title: Text(ContentPolicy.sanitizeText(_text(person, ['name']))),
      ),
      body: _PagedTitles(
        load: _loader!.load,
        headerBuilder: () => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipOval(
                    child: SizedBox(
                      width: 86,
                      height: 86,
                      child: _text(person, ['image']).isEmpty
                          ? const Icon(Icons.person_outline, size: 60)
                          : MediaArtwork(url: _text(person, ['image'])),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final field in [
                          ('role', 'Role', 'نقش'),
                          ('born', 'Born', 'تولد'),
                          ('height', 'Height', 'قد'),
                        ])
                          if (_text(person, [field.$1]).isNotEmpty)
                            Text(
                              '${tr(context, field.$2, field.$3)}: ${ContentPolicy.sanitizeText(_text(person, [field.$1]))}',
                            ),
                      ],
                    ),
                  ),
                ],
              ),
              if (_text(person, ['bio']).isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: _Synopsis(
                    text: ContentPolicy.sanitizeText(_text(person, ['bio'])),
                  ),
                ),
              if (_loader!.usingNameFallback)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    tr(
                      context,
                      'Filmography unavailable. Showing title search by actor name.',
                      'فیلموگرافی موجود نیست. نتایج جستجوی نام بازیگر نمایش داده می‌شود.',
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class SubjectDirectoryPage extends StatelessWidget {
  const SubjectDirectoryPage({super.key, required this.kind});
  final DiscoveryDirectory kind;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        kind == DiscoveryDirectory.themes
            ? tr(context, 'Themes & subjects', 'موضوع‌ها')
            : tr(context, 'Franchises', 'فرنچایزها'),
      ),
    ),
    body: _PagedObjects(
      load: (page) =>
          CatalogDiscovery(AppScope.read(context).api)
              .directory(kind, page: page),
      builder: (items) => Column(
        children: [
          for (final item in items.where(
            (row) => ContentPolicy.allowsText(_text(row, ['title'])),
          ))
            ListTile(
              leading: Icon(
                kind == DiscoveryDirectory.themes
                    ? Icons.topic_outlined
                    : Icons.collections_bookmark_outlined,
              ),
              title: Text(_text(item, ['title'])),
              subtitle:
                  kind == DiscoveryDirectory.franchises &&
                      _text(item, ['img']).isNotEmpty
                  ? Text(ContentPolicy.sanitizeText(_text(item, ['img'])))
                  : null,
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _push(
                context,
                SearchPage(initialQuery: _text(item, ['title'])),
              ),
            ),
        ],
      ),
    ),
  );
}

class SharedTitlesPage extends StatelessWidget {
  const SharedTitlesPage({super.key, this.newest = false});
  final bool newest;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        newest
            ? tr(context, 'New discoveries', 'تازه‌های کشف')
            : tr(
                context,
                'Most-shared titles',
                'عنوان‌های بیشتر اشتراک‌گذاشته‌شده',
              ),
      ),
    ),
    body: _PagedTitles(
      load: (page) =>
          CatalogDiscovery(AppScope.read(context).api)
              .sharedTitles(page: page, newest: newest),
    ),
  );
}

class CuratedPage extends StatefulWidget {
  const CuratedPage({super.key, this.best = false});
  final bool best;
  @override
  State<CuratedPage> createState() => _CuratedPageState();
}

class _CuratedPageState extends State<CuratedPage> {
  Future<List<Map<String, dynamic>>>? future;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    future ??= AppScope.read(context).api.curatedLinks(best: widget.best);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.best
            ? tr(context, 'Best collections', 'مجموعه‌های برتر')
            : tr(context, 'Editor picks', 'پیشنهاد سردبیر'),
      ),
    ),
    body: AsyncResult<List<Map<String, dynamic>>>(
      future: future!,
      onRetry: () => setState(() {
        future = AppScope.read(context).api.curatedLinks(best: widget.best);
      }),
      builder: (items) {
        final visible = items
            .where(
              (row) =>
                  ContentPolicy.allowsText(_text(row, ['title'])) &&
                  ContentPolicy.allowsUrl(_text(row, ['link'])),
            )
            .toList();
        return visible.isEmpty
            ? EmptyView(
                title: tr(
                  context,
                  'No collections returned',
                  'مجموعه‌ای دریافت نشد',
                ),
              )
            : ListView(
                children: [
                  for (final item in visible)
                    ListTile(
                      leading: const Icon(Icons.auto_awesome_outlined),
                      title: Text(_text(item, ['title'])),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _push(
                        context,
                        _CuratedContents(
                          title: _text(item, ['title']),
                          link: _text(item, ['link']),
                        ),
                      ),
                    ),
                ],
              );
      },
    ),
  );
}

class _CuratedContents extends StatelessWidget {
  const _CuratedContents({required this.title, required this.link});
  final String title, link;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: _PagedTitles(
      load: (page) =>
          AppScope.read(context).api.curatedContent(link, page: page),
    ),
  );
}

class _PagedObjects extends StatefulWidget {
  const _PagedObjects({super.key, required this.load, required this.builder});
  final Future<List<Map<String, dynamic>>> Function(int) load;
  final Widget Function(List<Map<String, dynamic>>) builder;
  @override
  State<_PagedObjects> createState() => _PagedObjectsState();
}

class _PagedObjectsState extends State<_PagedObjects> {
  final items = <Map<String, dynamic>>[];
  final _scroll = ScrollController();
  int page = 1, _emptyPages = 0;
  bool busy = false, end = false;
  Object? error;
  @override
  void initState() {
    super.initState();
    _scroll.addListener(_nearEnd);
    load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _nearEnd() {
    if (_emptyPages < 4 &&
        error == null &&
        _scroll.hasClients &&
        _scroll.position.extentAfter < 350) {
      load();
    }
  }

  Future<void> load() async {
    if (busy || end) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.load(page);
      if (!mounted) return;
      final known = items.map(jsonEncode).toSet();
      final fresh = result.where((row) => known.add(jsonEncode(row))).toList();
      setState(() {
        items.addAll(fresh);
        end = result is DiscoveryObjectPage
            ? result.nextPage == null
            : result.isEmpty;
        page = result is DiscoveryObjectPage
            ? result.nextPage ?? page
            : page + 1;
        _emptyPages = fresh.isEmpty ? _emptyPages + 1 : 0;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => error = const ApiException('Could not load. Please retry.'),
        );
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _nearEnd();
        });
      }
    }
  }

  Future<void> _refresh() async {
    if (busy) return;
    setState(() {
      items.clear();
      page = 1;
      end = false;
      error = null;
      _emptyPages = 0;
    });
    await load();
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: _refresh,
    child: ListView(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          '${items.length} ${tr(context, 'items loaded', 'مورد بارگذاری شده')}',
        ),
        widget.builder(items),
        if (busy)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (error != null)
          EmptyView(
            title: tr(context, 'Could not load', 'بارگذاری ممکن نشد'),
            onRetry: load,
          ),
        if (!busy && error == null && end && items.isEmpty)
          EmptyView(
            title: tr(
              context,
              'Nothing returned by the service',
              'سرویس موردی برنگرداند',
            ),
            onRetry: _refresh,
          ),
        if (!busy && !end && error == null)
          OutlinedButton(
            onPressed: () {
              _emptyPages = 0;
              load();
            },
            child: Text(tr(context, 'Load more', 'نمایش بیشتر')),
          ),
      ],
    ),
  );
}

class _ContinueWatchingShelf extends StatelessWidget {
  const _ContinueWatchingShelf();
  @override
  Widget build(BuildContext context) {
    final known = <String>{};
    final entries = AppScope.of(context).history
        .where(
          (entry) =>
              entry.positionSeconds >= 5 &&
              !entry.title.isChannel &&
              ContentPolicy.allowsTitleJson(entry.title.toJson()) &&
              known.add(entry.title.libraryKey),
        )
        .take(6)
        .toList();
    if (entries.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(20),
          child: _heading(
            context,
            tr(context, 'Continue watching', 'ادامه تماشا'),
          ),
        ),
        for (final entry in entries)
          ListTile(
            leading: const Icon(Icons.play_circle_outline),
            title: Text(entry.title.title),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (entry.episodeTitle.isNotEmpty) Text(entry.episodeTitle),
                LinearProgressIndicator(value: entry.progress),
                Text('${(entry.progress * 100).round()}%'),
              ],
            ),
            onTap: () => _continueCurrentHistory(context, entry),
            trailing: IconButton(
              tooltip: tr(context, 'Title details', 'جزئیات عنوان'),
              icon: const Icon(Icons.info_outline),
              onPressed: () => goTitle(context, entry.title),
            ),
          ),
      ],
    );
  }
}

Future<void> _continueCurrentHistory(
  BuildContext context,
  WatchEntry entry,
) async {
  try {
    final api = AppScope.read(context).api;
    final title = await api.poster(entry.title.id);
    if (!ContentPolicy.allowsTitleJson(title.toJson())) {
      throw const ApiException('Unavailable');
    }
    EpisodeRecord? episode;
    var playlist = <EpisodeRecord>[];
    if (entry.episodeId != null) {
      playlist = (await api.seasons(title.id))
          .expand((season) => season.episodes)
          .toList();
      episode = playlist
          .where((item) => item.id == entry.episodeId)
          .firstOrNull;
      if (episode == null) throw const ApiException('Episode unavailable');
    }
    final sources = (episode?.sources ?? title.sources)
        .where((source) => ContentPolicy.allowsUrl(source.url))
        .toList();
    final source = currentHistorySource(sources, entry.sourceUrl);
    if (source == null) throw const ApiException('Source unavailable');
    if (context.mounted) {
      await _play(
        context,
        title,
        source,
        episode: episode,
        playlist: playlist,
        alternatives: sources,
      );
    }
  } catch (_) {
    if (context.mounted) {
      toast(
        context,
        tr(
          context,
          'Could not refresh the current playback source. Open title details and retry.',
          'به‌روزرسانی منبع پخش ممکن نشد. جزئیات عنوان را باز کنید و دوباره تلاش کنید.',
        ),
      );
    }
  }
}

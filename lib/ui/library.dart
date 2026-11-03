import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/cache_service.dart';
import '../data/content_policy.dart';

import '../data/models.dart';
import '../media/downloads_page.dart';
import '../media/player_page.dart';
import '../state/app_state.dart';
import 'catalog.dart';
import 'common.dart';

void _push(BuildContext context, Widget page) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

Future<void> choosePreferredGenres(BuildContext context) async {
  final state = AppScope.read(context);
  final selected = {...state.prefs.preferredGenres};
  final future = state.api.genres();
  final result = await showDialog<List<int>>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, update) => AlertDialog(
        title: Text(tr(context, 'Your taste', 'سلیقه شما')),
        content: SizedBox(
          width: 480,
          height: 350,
          child: AsyncResult<List<Tag>>(
            future: future,
            builder: (genres) => SingleChildScrollView(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: genres
                    .where((g) => g.id > 0 && ContentPolicy.allowsText(g.title))
                    .map(
                      (genre) => FilterChip(
                        label: Text(genre.title),
                        selected: selected.contains(genre.id),
                        onSelected: (value) => update(() {
                          value
                              ? selected.add(genre.id)
                              : selected.remove(genre.id);
                        }),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(tr(context, 'Cancel', 'انصراف')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, selected.toList()),
            child: Text(tr(context, 'Save', 'ذخیره')),
          ),
        ],
      ),
    ),
  );
  if (result != null) {
    await state.updateSettings(state.prefs.copyWith(preferredGenres: result));
  }
}

class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key});
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(tr(context, 'Your library', 'کتابخانه شما')),
          actions: [
            IconButton(
              tooltip: tr(context, 'Downloads', 'دانلودها'),
              onPressed: () => _push(context, const DownloadsPage()),
              icon: const Icon(Icons.download_for_offline_outlined),
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelPadding: const EdgeInsets.symmetric(horizontal: 12),
            tabs: [
              Tab(
                text:
                    '${tr(context, 'Watchlist', 'تماشای بعدی')} (${state.savedCount})',
              ),
              Tab(
                text:
                    '${tr(context, 'Continue', 'ادامه تماشا')} (${state.historyCount})',
              ),
              Tab(
                text:
                    '${tr(context, 'Collections', 'مجموعه‌ها')} (${state.collectionCount})',
              ),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            state.saved.isEmpty
                ? EmptyView(
                    title: tr(
                      context,
                      'A little inspiration, saved',
                      'فیلم‌های مورد علاقه را ذخیره کنید',
                    ),
                    message: tr(
                      context,
                      'Tap the bookmark on any title to keep it here.',
                      'برای ذخیره یک عنوان، نشانک آن را بزنید.',
                    ),
                    icon: Icons.bookmark_border_rounded,
                  )
                : SingleChildScrollView(child: PosterGrid(items: state.saved)),
            state.history.isEmpty
                ? EmptyView(
                    title: tr(
                      context,
                      'Pick up where you left off',
                      'تماشا را از جایی که بودید ادامه دهید',
                    ),
                    message: tr(
                      context,
                      'Your playback progress stays on this device.',
                      'سابقه پخش فقط در همین دستگاه ذخیره می‌شود.',
                    ),
                    icon: Icons.history_rounded,
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: state.history.length,
                    itemBuilder: (_, index) {
                      final item = state.history[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () => goTitle(context, item.title),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: SizedBox(
                                    width: 62,
                                    height: 88,
                                    child: MediaArtwork(url: item.title.image),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.title.title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      if (item.episodeTitle.isNotEmpty)
                                        Text(
                                          item.episodeTitle,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      const SizedBox(height: 8),
                                      LinearProgressIndicator(
                                        value: item.progress.clamp(0, 1),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        '${Duration(seconds: item.positionSeconds.round()).toString().split('.').first} / ${Duration(seconds: item.durationSeconds.round()).toString().split('.').first}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall,
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  children: [
                                    IconButton(
                                      tooltip: tr(context, 'Resume', 'ادامه'),
                                      icon: const Icon(
                                        Icons.play_circle_outline_rounded,
                                      ),
                                      onPressed: () async {
                                        try {
                                          final current = await state
                                              .resolveHistory(item);
                                          if (!context.mounted) return;
                                          _push(
                                            context,
                                            PlayerPage(
                                              title: current.title,
                                              source: current.source,
                                              episode: current.episode,
                                              playlist: current.playlist,
                                              alternatives:
                                                  current.alternatives,
                                            ),
                                          );
                                        } catch (_) {
                                          if (!context.mounted) return;
                                          toast(
                                            context,
                                            tr(
                                              context,
                                              'Could not refresh this source. Choose a current source on the title page.',
                                              'منبع تازه در دسترس نیست؛ از صفحه عنوان منبع دیگری انتخاب کنید.',
                                            ),
                                          );
                                          goTitle(context, item.title);
                                        }
                                      },
                                    ),
                                    IconButton(
                                      tooltip: tr(
                                        context,
                                        'Remove history',
                                        'حذف سابقه',
                                      ),
                                      icon: const Icon(Icons.close, size: 18),
                                      onPressed: () => state.removeHistory(
                                        item.title.id,
                                        kind: item.title.type,
                                        episodeId: item.episodeId,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: FilledButton.tonalIcon(
                      icon: const Icon(Icons.add),
                      label: Text(tr(context, 'New collection', 'مجموعه جدید')),
                      onPressed: () async {
                        final controller = TextEditingController();
                        final name = await showDialog<String>(
                          context: context,
                          builder: (dialogContext) => AlertDialog(
                            title: Text(
                              tr(context, 'Name your collection', 'نام مجموعه'),
                            ),
                            content: TextField(
                              controller: controller,
                              autofocus: true,
                              maxLength: 80,
                              decoration: InputDecoration(
                                labelText: tr(context, 'Name', 'نام'),
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(dialogContext),
                                child: Text(tr(context, 'Cancel', 'انصراف')),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(
                                  dialogContext,
                                  controller.text.trim(),
                                ),
                                child: Text(tr(context, 'Create', 'ایجاد')),
                              ),
                            ],
                          ),
                        );
                        controller.dispose();
                        if (name != null && name.isNotEmpty) {
                          try {
                            await state.createCollection(name);
                          } catch (error) {
                            if (context.mounted) {
                              toast(
                                context,
                                tr(
                                  context,
                                  'Operation could not be completed. Please try again.',
                                  'انجام عملیات ممکن نشد؛ دوباره تلاش کنید.',
                                ),
                              );
                            }
                          }
                        }
                      },
                    ),
                  ),
                ),
                Expanded(
                  child: state.collections.isEmpty
                      ? EmptyView(
                          title: tr(
                            context,
                            'Make it your own',
                            'مجموعه خودتان را بسازید',
                          ),
                          message: tr(
                            context,
                            'Organize titles into collections from their detail pages.',
                            'عنوان‌ها را در صفحه جزئیات به مجموعه اضافه کنید.',
                          ),
                          icon: Icons.collections_bookmark_outlined,
                        )
                      : ListView.builder(
                          itemCount: state.collections.length,
                          itemBuilder: (_, index) {
                            final collection = state.collections[index];
                            return ListTile(
                              leading: const Icon(Icons.video_library_outlined),
                              title: Text(collection.name),
                              subtitle: Text(
                                '${collection.titles.length} ${tr(context, 'titles', 'عنوان')}',
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline),
                                tooltip: tr(
                                  context,
                                  'Delete collection',
                                  'حذف مجموعه',
                                ),
                                onPressed: () async {
                                  if (await _confirm(
                                    context,
                                    tr(
                                      context,
                                      'Delete this collection?',
                                      'این مجموعه حذف شود؟',
                                    ),
                                  )) {
                                    await state.deleteCollection(collection.id);
                                  }
                                },
                              ),
                              onTap: () => _push(
                                context,
                                _CollectionPage(id: collection.id),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CollectionPage extends StatelessWidget {
  const _CollectionPage({required this.id});
  final String id;
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final matches = state.collections.where((c) => c.id == id);
    if (matches.isEmpty) {
      return Scaffold(
        appBar: AppBar(),
        body: EmptyView(
          title: tr(context, 'Collection removed', 'مجموعه حذف شده است'),
        ),
      );
    }
    final collection = matches.first;
    return Scaffold(
      appBar: AppBar(title: Text(collection.name)),
      body: collection.titles.isEmpty
          ? EmptyView(
              title: tr(context, 'No titles yet', 'هنوز عنوانی اضافه نشده'),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: collection.titles.length,
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 190,
                childAspectRatio: .56,
                mainAxisSpacing: 20,
                crossAxisSpacing: 14,
              ),
              itemBuilder: (_, index) {
                final title = collection.titles[index];
                return Stack(
                  children: [
                    Positioned.fill(child: PosterCard(title: title)),
                    PositionedDirectional(
                      top: 4,
                      end: 4,
                      child: IconButton.filledTonal(
                        tooltip: tr(
                          context,
                          'Remove from collection',
                          'حذف از مجموعه',
                        ),
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => state.toggleCollectionTitle(id, title),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}

Future<bool> _confirm(BuildContext context, String title) async =>
    await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(tr(context, 'Cancel', 'انصراف')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(tr(context, 'Confirm', 'تأیید')),
          ),
        ],
      ),
    ) ??
    false;

class MorePage extends StatelessWidget {
  const MorePage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(tr(context, 'Make yourself at home', 'اینجا خانه شماست')),
    ),
    body: ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Text(
            tr(
              context,
              'No accounts. Your library, your device.',
              'بدون حساب کاربری؛ کتابخانه شما روی دستگاه خودتان.',
            ),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        _link(
          context,
          Icons.download_rounded,
          'Downloads',
          'دانلودها',
          const DownloadsPage(),
        ),
        _link(
          context,
          Icons.animation_rounded,
          'Anime & animation',
          'انیمه و انیمیشن',
          const BrowsePage(initialKind: 'poster', initialGenre: 3),
        ),
        _link(
          context,
          Icons.people_outline_rounded,
          'Actors',
          'بازیگران',
          const ActorsPage(),
        ),
        _link(
          context,
          Icons.auto_awesome_outlined,
          'Curated recommendations',
          'پیشنهادهای سردبیر',
          const CuratedPage(),
        ),
        _link(
          context,
          Icons.workspace_premium_outlined,
          'Best collections',
          'مجموعه‌های برتر',
          const CuratedPage(best: true),
        ),
        ListTile(
          leading: const Icon(Icons.favorite_border),
          title: Text(
            tr(context, 'Tune your recommendations', 'سلیقه و پیشنهادها'),
          ),
          subtitle: Text(
            tr(
              context,
              'Choose genres you enjoy',
              'ژانرهای مورد علاقه را انتخاب کنید',
            ),
          ),
          onTap: () => choosePreferredGenres(context),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Divider(),
        ),
        _link(
          context,
          Icons.tune_rounded,
          'Settings',
          'تنظیمات',
          const SettingsPage(),
        ),
        _link(
          context,
          Icons.privacy_tip_outlined,
          'Privacy & your data',
          'حریم خصوصی و اطلاعات شما',
          const _PrivacyPage(),
        ),
        ListTile(
          key: const Key('share-reelbox'),
          leading: const Icon(Icons.share_outlined),
          title: Text(tr(context, 'Share Reelbox', 'اشتراک‌گذاری Reelbox')),
          subtitle: Text(
            tr(context, 'Share app information', 'اشتراک اطلاعات برنامه'),
          ),
          onTap: () => _shareApp(context),
        ),
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: Text(tr(context, 'About Reelbox', 'درباره ریل‌باکس')),
          onTap: () => _push(context, const _AboutReelboxPage()),
        ),
      ],
    ),
  );
  Future<void> _shareApp(BuildContext context) async {
    final box = context.findRenderObject();
    final origin = box is RenderBox && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    try {
      final result = await SharePlus.instance.share(
        ShareParams(
          title: 'Reelbox',
          text: tr(
            context,
            'Reelbox — an account-free film and series client with a private, device-local library',
            'Reelbox — فیلم و سریال، با کتابخانه خصوصی روی دستگاه و بدون نیاز به حساب کاربری',
          ),
          sharePositionOrigin: origin,
        ),
      );
      if (result.status == ShareResultStatus.unavailable) {
        throw const FormatException('Sharing unavailable');
      }
    } catch (_) {
      if (context.mounted) {
        toast(
          context,
          tr(
            context,
            'Sharing is unavailable on this device',
            'اشتراک‌گذاری در این دستگاه در دسترس نیست',
          ),
          kind: ToastKind.error,
        );
      }
    }
  }

  Widget _link(
    BuildContext context,
    IconData icon,
    String en,
    String fa,
    Widget page,
  ) => ListTile(
    leading: Icon(icon),
    title: Text(tr(context, en, fa)),
    trailing: const Icon(Icons.chevron_right),
    onTap: () => _push(context, page),
  );
}

/// Explains current client behavior, not an external service's privacy policy.
class _PrivacyPage extends StatelessWidget {
  const _PrivacyPage();

  @override
  Widget build(BuildContext context) {
    Widget section(String en, String fa, String bodyEn, String bodyFa) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr(context, en, fa),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(tr(context, bodyEn, bodyFa)),
            ],
          ),
        );
    return Scaffold(
      appBar: AppBar(
        title: Text(
          tr(context, 'Privacy & your data', 'حریم خصوصی و اطلاعات شما'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          section(
            'On this device',
            'روی این دستگاه',
            'Reelbox does not require an account. Watchlists, collections, viewing progress, recent searches and preferences are stored locally on this device. Downloaded media is stored separately.',
            'ریل‌باکس به حساب کاربری نیاز ندارد. تماشای بعدی، مجموعه‌ها، پیشرفت تماشا، جستجوهای اخیر و تنظیمات به‌صورت محلی روی این دستگاه ذخیره می‌شوند. فایل‌های دانلودشده جداگانه نگهداری می‌شوند.',
          ),
          section(
            'External API & media',
            'API و رسانه‌های خارجی',
            'Browsing and searching send requests to external catalog API servers. Artwork, playback and downloads contact media hosts. Those services can receive your IP address and requested searches or media. Their data handling is outside this client; this page is not their privacy policy.',
            'مرور و جستجو درخواست‌هایی به سرورهای خارجی API فهرست می‌فرستند. تصاویر، پخش و دانلود به میزبان‌های رسانه متصل می‌شوند. این سرویس‌ها می‌توانند نشانی IP و جستجوها یا رسانه‌های درخواستی شما را دریافت کنند. نحوه مدیریت اطلاعات آن‌ها خارج از کنترل این برنامه است؛ این صفحه سیاست حریم خصوصی آن‌ها نیست.',
          ),
          section(
            'Sharing & backups',
            'اشتراک‌گذاری و پشتیبان‌ها',
            'Sharing sends the selected link to the app you choose. Exported library backups include your local library, history, settings and stored source URLs, which may contain access tokens. Keep backups private; copies you share or export are outside Reelbox control.',
            'اشتراک‌گذاری پیوند انتخابی را به برنامه‌ای که انتخاب می‌کنید می‌فرستد. پشتیبان خروجی شامل کتابخانه محلی، سابقه، تنظیمات و نشانی‌های ذخیره‌شده منابع است که ممکن است حاوی توکن دسترسی باشند. پشتیبان‌ها را خصوصی نگه دارید؛ نسخه‌های خروجی یا اشتراک‌گذاشته‌شده خارج از کنترل ریل‌باکس هستند.',
          ),
          section(
            'Deleting local data',
            'حذف اطلاعات محلی',
            'Settings lets you clear disposable cache and reset subtitle styling without deleting your library or completed downloads. Manage downloaded files in Downloads and exported backups separately.',
            'در تنظیمات می‌توانید حافظه موقت را پاک و فقط ظاهر زیرنویس را بازنشانی کنید؛ کتابخانه و دانلودهای کامل حذف نمی‌شوند. فایل‌های دانلودشده و پشتیبان‌های خروجی را جداگانه مدیریت کنید.',
          ),
          section(
            'Unencrypted HTTP media',
            'رسانه HTTP بدون رمزنگاری',
            'Catalog API routing uses trusted HTTPS servers, but some artwork or media links may use unencrypted HTTP. Networks along the route can observe or modify that traffic. HTTPS media is preferable when available.',
            'مسیریابی API فهرست از سرورهای مورد اعتماد HTTPS استفاده می‌کند، اما برخی پیوندهای تصویر یا رسانه ممکن است HTTP بدون رمزنگاری باشند. شبکه‌های مسیر می‌توانند آن ترافیک را مشاهده یا تغییر دهند. در صورت دسترسی، رسانه HTTPS ترجیح دارد.',
          ),
        ],
      ),
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final p = state.prefs;
    void save(AppSettings settings) {
      state.updateSettings(settings).catchError((Object error) {
        if (context.mounted) {
          toast(
            context,
            tr(
              context,
              'Operation could not be completed. Please try again.',
              'انجام عملیات ممکن نشد؛ دوباره تلاش کنید.',
            ),
          );
        }
      });
    }

    Widget header(String en, String fa) => Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 28, 20, 8),
      child: Text(
        tr(context, en, fa),
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    Widget select<T>(
      String en,
      String fa,
      T value,
      Map<T, String> choices,
      void Function(T) changed,
    ) => ListTile(
      title: Text(tr(context, en, fa)),
      trailing: SizedBox(
        width: MediaQuery.sizeOf(context).width * .42,
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          underline: const SizedBox.shrink(),
          items:
              {
                    ...choices,
                    if (!choices.containsKey(value))
                      value: '${tr(context, 'Custom', 'سفارشی')}: $value',
                  }.entries
                  .map(
                    (e) => DropdownMenuItem<T>(
                      value: e.key,
                      child: Text(
                        e.value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
          onChanged: (v) {
            if (v != null) changed(v);
          },
        ),
      ),
    );
    Widget toggle(
      String en,
      String fa,
      bool value,
      void Function(bool) changed,
    ) => SwitchListTile(
      title: Text(tr(context, en, fa)),
      value: value,
      onChanged: changed,
    );
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'Settings', 'تنظیمات'))),
      body: ListView(
        children: [
          header('Appearance', 'ظاهر'),
          select('Language', 'زبان', p.locale, {
            'en': 'English',
            'fa': 'فارسی',
          }, (v) => save(p.copyWith(locale: v))),
          select('Theme', 'پوسته', p.theme, {
            'dark': tr(context, 'Dark', 'تیره'),
            'light': tr(context, 'Light', 'روشن'),
            'system': tr(context, 'System', 'سیستم'),
          }, (v) => save(p.copyWith(theme: v))),
          toggle(
            'Data saver artwork',
            'کاهش مصرف داده تصاویر',
            p.dataSaver,
            (v) => save(p.copyWith(dataSaver: v)),
          ),
          toggle(
            'Compact catalog',
            'فهرست فشرده',
            p.compactCatalog,
            (v) => save(p.copyWith(compactCatalog: v)),
          ),
          header('Playback', 'پخش'),
          select('Video fit', 'اندازه تصویر', p.videoFit, {
            'contain': tr(context, 'Fit', 'متناسب'),
            'cover': tr(context, 'Crop to fill', 'برش و پرکردن'),
            'fill': tr(context, 'Stretch', 'کشیده'),
          }, (v) => save(p.copyWith(videoFit: v))),
          toggle(
            'Audio only',
            'فقط صدا',
            p.audioOnly,
            (v) => save(p.copyWith(audioOnly: v)),
          ),
          toggle(
            'Background audio',
            'صدا در پس‌زمینه',
            p.backgroundAudio,
            (v) => save(p.copyWith(backgroundAudio: v)),
          ),
          toggle(
            'Close player on completion',
            'بستن پخش پس از پایان',
            p.closeOnCompletion,
            (v) => save(p.copyWith(closeOnCompletion: v)),
          ),
          select('Resume rewind', 'بازگشت هنگام ادامه', p.resumeRewindSeconds, {
            0: '0s',
            5: '5s',
            10: '10s',
            15: '15s',
            30: '30s',
            60: '60s',
            120: '120s',
          }, (v) => save(p.copyWith(resumeRewindSeconds: v))),
          toggle(
            'Remember volume',
            'ذخیره بلندی صدا',
            p.rememberVolume,
            (v) => save(p.copyWith(rememberVolume: v)),
          ),
          ListTile(
            title: Text(tr(context, 'Player volume', 'بلندی صدای پخش')),
            subtitle: Slider(
              value: p.playerVolume,
              min: 0,
              max: 1,
              label: '${(p.playerVolume * 100).round()}%',
              onChanged: (v) => save(p.copyWith(playerVolume: v)),
            ),
          ),
          toggle(
            'Resume from last position',
            'ادامه از آخرین موقعیت',
            p.resumePlayback,
            (v) => save(p.copyWith(resumePlayback: v)),
          ),
          toggle(
            'Automatically play next episode',
            'پخش خودکار قسمت بعد',
            p.autoNext,
            (v) => save(p.copyWith(autoNext: v)),
          ),
          toggle(
            'Autoplay selected source',
            'پخش خودکار منبع انتخاب‌شده',
            p.autoplay,
            (v) => save(p.copyWith(autoplay: v)),
          ),
          toggle(
            'Prefer an external player',
            'ترجیح پخش‌کننده خارجی',
            p.externalPlayer,
            (v) => save(p.copyWith(externalPlayer: v)),
          ),
          toggle(
            'Hide trailer sources',
            'پنهان کردن تیزرها',
            p.hideTrailers,
            (v) => save(p.copyWith(hideTrailers: v)),
          ),
          select('Default quality', 'کیفیت پیش‌فرض', p.defaultQuality, {
            'ask': tr(context, 'Ask each time', 'هر بار بپرس'),
            'auto': tr(context, 'Automatic', 'خودکار'),
            '720': '720p',
            '1080': '1080p',
          }, (v) => save(p.copyWith(defaultQuality: v))),
          select('Playback speed', 'سرعت پخش', p.playbackSpeed, {
            0.5: '0.5×',
            0.75: '0.75×',
            1.0: '1×',
            1.25: '1.25×',
            1.5: '1.5×',
            2.0: '2×',
          }, (v) => save(p.copyWith(playbackSpeed: v))),
          select('Seek step', 'مقدار جابه‌جایی', p.skipSeconds, {
            5: '5s',
            10: '10s',
            15: '15s',
            30: '30s',
          }, (v) => save(p.copyWith(skipSeconds: v))),
          select('Player orientation', 'جهت صفحه پخش', p.orientation, {
            'auto': tr(context, 'Automatic', 'خودکار'),
            'landscape': tr(context, 'Landscape', 'افقی'),
            'portrait': tr(context, 'Portrait', 'عمودی'),
          }, (v) => save(p.copyWith(orientation: v))),
          select(
            'External player app',
            'برنامه پخش خارجی',
            p.externalPlayerPackage,
            {
              'ask': tr(context, 'Ask each time', 'هر بار بپرس'),
              'org.videolan.vlc': 'VLC',
              'com.mxtech.videoplayer.ad': 'MX Player',
              'com.mxtech.videoplayer.pro': 'MX Player Pro',
              'com.brouken.player': 'Just Player',
            },
            (v) => save(p.copyWith(externalPlayerPackage: v)),
          ),
          header('Subtitles & audio', 'زیرنویس و صدا'),
          toggle(
            'Enable subtitles',
            'نمایش زیرنویس',
            p.subtitleEnabled,
            (v) => save(p.copyWith(subtitleEnabled: v)),
          ),
          select('Subtitle font', 'قلم زیرنویس', p.subtitleFontFamily, {
            'sans-serif': tr(context, 'System sans serif', 'قلم ساده سیستم'),
            'serif': tr(context, 'System serif', 'قلم سریف سیستم'),
            'monospace': tr(context, 'Monospace', 'قلم تک‌عرض'),
          }, (v) => save(p.copyWith(subtitleFontFamily: v))),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              tr(
                context,
                'Subtitle preview · The next chapter',
                'پیش‌نمایش زیرنویس · فصل بعدی',
              ),
              key: const Key('subtitle-preview'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: p.resolvedSubtitleFontFamily,
                fontFamilyFallback: p.subtitleFontFamilyFallback,
                fontSize: p.subtitleFontSize,
                color: Color(p.subtitleColor),
                backgroundColor: Color(p.subtitleBackground),
              ),
            ),
          ),
          ListTile(
            title: Text(tr(context, 'Subtitle size', 'اندازه زیرنویس')),
            subtitle: Slider(
              value: p.subtitleFontSize,
              min: 8,
              max: 96,
              divisions: 88,
              label: '${p.subtitleFontSize.round()}',
              onChanged: (v) => save(p.copyWith(subtitleFontSize: v)),
            ),
          ),
          select('Subtitle color', 'رنگ زیرنویس', p.subtitleColor, {
            0xFFFFFFFF: tr(context, 'White', 'سفید'),
            0xFFFFFF00: tr(context, 'Yellow', 'زرد'),
            0xFF00FFFF: tr(context, 'Cyan', 'فیروزه‌ای'),
          }, (v) => save(p.copyWith(subtitleColor: v))),
          select(
            'Subtitle background',
            'پس‌زمینه زیرنویس',
            p.subtitleBackground,
            {
              0x80000000: tr(context, 'Translucent', 'نیمه‌شفاف'),
              0x00000000: tr(context, 'None', 'بدون پس‌زمینه'),
              0xFF000000: tr(context, 'Black', 'مشکی'),
            },
            (v) => save(p.copyWith(subtitleBackground: v)),
          ),
          _ColorTile(
            label: tr(context, 'Custom subtitle color', 'رنگ سفارشی زیرنویس'),
            value: p.subtitleColor,
            onChanged: (v) => save(p.copyWith(subtitleColor: v)),
          ),
          _ColorTile(
            label: tr(
              context,
              'Custom background color',
              'رنگ سفارشی پس‌زمینه',
            ),
            value: p.subtitleBackground,
            onChanged: (v) => save(p.copyWith(subtitleBackground: v)),
          ),
          ListTile(
            key: const Key('reset-subtitle-style'),
            leading: const Icon(Icons.format_clear),
            title: Text(
              tr(
                context,
                'Reset subtitle style only',
                'بازنشانی فقط تنظیمات زیرنویس',
              ),
            ),
            onTap: () async {
              try {
                await state.resetSubtitleStyle();
              } catch (error) {
                if (context.mounted) {
                  toast(
                    context,
                    tr(
                      context,
                      'Operation could not be completed. Please try again.',
                      'انجام عملیات ممکن نشد؛ دوباره تلاش کنید.',
                    ),
                  );
                }
              }
            },
          ),
          _DelayTile(
            label: tr(
              context,
              'Subtitle delay (seconds)',
              'تأخیر زیرنویس (ثانیه)',
            ),
            value: p.subtitleDelay,
            onChanged: (v) => save(p.copyWith(subtitleDelay: v)),
          ),
          _DelayTile(
            label: tr(context, 'Audio delay (seconds)', 'تأخیر صدا (ثانیه)'),
            value: p.audioDelay,
            onChanged: (v) => save(p.copyWith(audioDelay: v)),
          ),
          header('Downloads', 'دانلودها'),
          select(
            'Parallel download segments',
            'بخش‌های همزمان دانلود',
            p.parallelDownloads,
            {for (var i = 1; i <= 8; i++) i: '$i'},
            (v) => save(p.copyWith(parallelDownloads: v)),
          ),
          toggle(
            'Download on Wi-Fi only',
            'دانلود فقط با وای‌فای',
            p.wifiOnlyDownloads,
            (v) => save(p.copyWith(wifiOnlyDownloads: v)),
          ),
          SwitchListTile(
            title: Text(
              tr(
                context,
                'Notifications for new downloads',
                'اعلان‌های دانلودهای جدید',
              ),
            ),
            subtitle: Text(
              tr(
                context,
                'Already-running Android jobs keep their original notification policy. OS-required foreground notifications may remain.',
                'کارهای در حال اجرای اندروید سیاست اعلان قبلی خود را حفظ می‌کنند. اعلان‌های الزامی سیستم‌عامل برای سرویس پیش‌زمینه ممکن است باقی بمانند.',
              ),
            ),
            value: p.downloadNotifications,
            onChanged: (v) => save(p.copyWith(downloadNotifications: v)),
          ),
          header('Your data', 'اطلاعات شما'),
          ListTile(
            leading: const Icon(Icons.upload_file_outlined),
            title: Text(
              tr(context, 'Export local library', 'خروجی کتابخانه محلی'),
            ),
            onTap: () async {
              try {
                final uri = await FilePicker.saveFile(
                  fileName: 'reelbox-library.json',
                  mimeType: 'application/json',
                  bytes: Uint8List.fromList(utf8.encode(state.exportLibrary())),
                );
                if (uri != null && context.mounted) {
                  toast(
                    context,
                    tr(context, 'Library exported', 'خروجی ذخیره شد'),
                  );
                }
              } catch (error) {
                if (context.mounted) {
                  toast(
                    context,
                    tr(
                      context,
                      'Operation could not be completed. Please try again.',
                      'انجام عملیات ممکن نشد؛ دوباره تلاش کنید.',
                    ),
                  );
                }
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.file_download_outlined),
            title: Text(
              tr(context, 'Import local library', 'ورود کتابخانه محلی'),
            ),
            onTap: () async {
              try {
                final file = await FilePicker.pickFile(
                  type: FileType.custom,
                  allowedExtensions: ['json'],
                );
                if (file == null) return;
                final size = await file.length();
                if (size == null || size > 8 * 1024 * 1024) {
                  throw const FormatException(
                    'Library file must be smaller than 8 MB.',
                  );
                }
                final text = utf8.decode(await file.readAsBytes());
                if (!context.mounted) return;
                if (await _confirm(
                  context,
                  tr(
                    context,
                    'Replace your local library with this backup?',
                    'کتابخانه محلی با این پشتیبان جایگزین شود؟',
                  ),
                )) {
                  await state.importLibrary(text);
                  if (context.mounted) {
                    toast(
                      context,
                      tr(context, 'Library imported', 'کتابخانه وارد شد'),
                    );
                  }
                }
              } catch (error) {
                if (context.mounted) {
                  toast(
                    context,
                    tr(
                      context,
                      'Operation could not be completed. Please try again.',
                      'انجام عملیات ممکن نشد؛ دوباره تلاش کنید.',
                    ),
                  );
                }
              }
            },
          ),
          const _CatalogConnectionTile(),
          const _CacheTile(),
          const SizedBox(height: 30),
        ],
      ),
    );
  }
}

class _CatalogConnectionTile extends StatefulWidget {
  const _CatalogConnectionTile();
  @override
  State<_CatalogConnectionTile> createState() => _CatalogConnectionTileState();
}

class _CatalogConnectionTileState extends State<_CatalogConnectionTile> {
  bool _busy = false;
  Future<void> _refresh() async {
    final api = AppScope.read(context).api;
    setState(() => _busy = true);
    try {
      await api.initialize();
      if (!mounted) return;
      toast(
        context,
        tr(
          context,
          'Discovery check finished. The current trusted server is retained unless a verified replacement is accepted; success was not verified.',
          'بررسی اتصال پایان یافت. سرور مورد اعتماد فعلی تا پذیرش جایگزین معتبر حفظ می‌شود؛ موفقیت اتصال تأیید نشده است.',
        ),
      );
    } catch (_) {
      if (mounted) {
        toast(
          context,
          tr(
            context,
            'Could not check the catalog connection. Your library is unchanged.',
            'بررسی اتصال فهرست ممکن نشد. کتابخانه شما تغییری نکرده است.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListTile(
    leading: _busy
        ? const SizedBox.square(
            dimension: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.refresh),
    title: Text(tr(context, 'Refresh API server', 'بررسی اتصال فهرست')),
    subtitle: Text(
      tr(
        context,
        'Recheck trusted catalog configuration',
        'بررسی دوباره تنظیمات مورد اعتماد اتصال',
      ),
    ),
    onTap: _busy ? null : _refresh,
  );
}

/// A network-free introduction. The root app switches to its shell when the
/// persisted introCompleted preference changes; this widget does not push routes.
class FirstRunIntroPage extends StatefulWidget {
  const FirstRunIntroPage({super.key});
  @override
  State<FirstRunIntroPage> createState() => _FirstRunIntroPageState();
}

class _FirstRunIntroPageState extends State<FirstRunIntroPage> {
  bool _busy = false;
  Future<void> _finish() async {
    if (_busy) return;
    setState(() => _busy = true);
    final state = AppScope.read(context);
    try {
      await state.updateSettings(state.prefs.copyWith(introCompleted: true));
    } catch (_) {
      if (mounted) {
        toast(
          context,
          tr(
            context,
            'Could not save preferences. Try again.',
            'ذخیره تنظیمات انجام نشد؛ دوباره تلاش کنید.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reelbox'),
        actions: [
          TextButton(
            key: const Key('intro-skip'),
            onPressed: _busy ? null : _finish,
            child: Text(tr(context, 'Skip', 'رد شدن')),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Icon(Icons.movie_filter_outlined, size: 80),
            const SizedBox(height: 24),
            Text(
              tr(
                context,
                'Your library, your device',
                'کتابخانه شما، دستگاه شما',
              ),
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 16),
            Text(
              tr(
                context,
                'Save films and series in private collections. Continue episodes where you left off and keep downloaded media for offline viewing.',
                'فیلم‌ها و سریال‌ها را در مجموعه‌های خصوصی ذخیره کنید؛ قسمت‌ها را از آخرین موقعیت ادامه دهید و رسانه‌های دانلودشده را آفلاین ببینید.',
              ),
            ),
            const SizedBox(height: 16),
            Text(
              tr(
                context,
                'No account is needed. Your watchlist, history and settings stay on this device. Browsing and streaming contact external catalog and media hosts.',
                'نیازی به حساب کاربری نیست. فهرست، سابقه و تنظیمات روی همین دستگاه می‌مانند. مرور و پخش به میزبان‌های خارجی فهرست و رسانه متصل می‌شوند.',
              ),
            ),
            const SizedBox(height: 24),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'en', label: Text('English')),
                ButtonSegment(value: 'fa', label: Text('فارسی')),
              ],
              selected: {state.locale},
              onSelectionChanged: _busy
                  ? null
                  : (values) async {
                      try {
                        await state.updateSettings(
                          state.prefs.copyWith(locale: values.single),
                        );
                      } catch (_) {
                        if (context.mounted) {
                          toast(
                            context,
                            tr(
                              context,
                              'Could not save language',
                              'ذخیره زبان انجام نشد',
                            ),
                          );
                        }
                      }
                    },
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              key: const Key('intro-complete'),
              onPressed: _busy ? null : _finish,
              icon: const Icon(Icons.arrow_forward),
              label: Text(tr(context, 'Start watching', 'شروع تماشا')),
            ),
          ],
        ),
      ),
    );
  }
}

class _AboutReelboxPage extends StatefulWidget {
  const _AboutReelboxPage();
  @override
  State<_AboutReelboxPage> createState() => _AboutReelboxPageState();
}

class _AboutReelboxPageState extends State<_AboutReelboxPage> {
  late final Future<PackageInfo> _package = PackageInfo.fromPlatform();
  @override
  Widget build(BuildContext context) {
    final display = MediaQuery.of(context);
    Widget info(String en, String fa, String value) => ListTile(
      title: Text(tr(context, en, fa)),
      subtitle: SelectableText(value),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'About Reelbox', 'درباره ریل‌باکس')),
      ),
      body: ListView(
        children: [
          FutureBuilder<PackageInfo>(
            future: _package,
            builder: (context, snapshot) {
              final package = snapshot.data;
              if (package == null) {
                return ListTile(
                  title: const Text('Reelbox'),
                  subtitle: Text(
                    snapshot.hasError
                        ? tr(
                            context,
                            'Package information unavailable',
                            'اطلاعات بسته در دسترس نیست',
                          )
                        : tr(context, 'Loading version…', 'دریافت نسخه…'),
                  ),
                );
              }
              return info(
                'Application',
                'برنامه',
                '${package.appName}\n${package.version} (${package.buildNumber})\n${package.packageName}',
              );
            },
          ),
          info(
            'Device platform',
            'پلتفرم دستگاه',
            kIsWeb
                ? 'Web'
                : '${Platform.operatingSystem}\n${Platform.operatingSystemVersion}',
          ),
          info(
            'Display',
            'نمایشگر',
            '${display.size.width.round()} × ${display.size.height.round()} logical pixels · ${display.devicePixelRatio.toStringAsFixed(2)}×',
          ),
          info(
            'Dart runtime',
            'زمان اجرای دارت',
            kIsWeb
                ? tr(context, 'Browser runtime', 'زمان اجرای مرورگر')
                : Platform.version,
          ),
          info(
            'Flutter framework',
            'چارچوب فلاتر',
            const String.fromEnvironment(
              'FLUTTER_VERSION',
              defaultValue: 'Not exposed by this build',
            ),
          ),
          info(
            'Flutter engine revision',
            'شناسه موتور فلاتر',
            const String.fromEnvironment(
              'FLUTTER_ENGINE_REVISION',
              defaultValue: 'Not exposed by this build',
            ),
          ),
          info(
            'Playback engine',
            'موتور پخش',
            kIsWeb
                ? 'media_kit / browser media'
                : 'media_kit / libmpv\n${tr(context, 'Engine version is not exposed by the plugin.', 'نسخه موتور از طریق افزونه در دسترس نیست.')}',
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              tr(
                context,
                'Independent, account-free client. Media availability depends on external providers. Private collections and viewing history are stored on this device.',
                'یک برنامه مستقل و بدون حساب کاربری؛ دسترسی رسانه به ارائه‌دهندگان خارجی بستگی دارد. مجموعه‌های خصوصی و سابقه تماشا روی همین دستگاه ذخیره می‌شوند.',
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: Text(tr(context, 'Open-source licenses', 'مجوزهای متن‌باز')),
            onTap: () =>
                showLicensePage(context: context, applicationName: 'Reelbox'),
          ),
        ],
      ),
    );
  }
}

class _CacheTile extends StatefulWidget {
  const _CacheTile();
  @override
  State<_CacheTile> createState() => _CacheTileState();
}

class _CacheTileState extends State<_CacheTile> {
  final CacheService _service = CacheService();
  late Future<CacheSnapshot> _size = _service.measure();
  bool _busy = false;
  @override
  Widget build(BuildContext context) => FutureBuilder<CacheSnapshot>(
    future: _size,
    builder: (context, snapshot) => ListTile(
      leading: const Icon(Icons.cleaning_services_outlined),
      title: Text(tr(context, 'Clear disposable cache', 'پاک کردن حافظه موقت')),
      subtitle: Text(
        snapshot.hasData
            ? '${(snapshot.data!.totalBytes / (1024 * 1024)).toStringAsFixed(2)} MB · ${tr(context, 'Cached artwork + disposable files only. Completed downloads and library are kept.', 'فقط تصاویر و فایل‌های موقت؛ دانلودهای کامل و کتابخانه حفظ می‌شوند.')}'
            : snapshot.hasError
            ? tr(
                context,
                'Cache size unavailable',
                'اندازه حافظه موقت در دسترس نیست',
              )
            : tr(context, 'Measuring cache…', 'محاسبه حافظه موقت…'),
      ),
      enabled: !_busy,
      onTap: () async {
        setState(() => _busy = true);
        try {
          await _service.clear();
          if (!context.mounted) return;
          toast(
            context,
            tr(
              context,
              'Disposable cache cleared. Library and downloads kept.',
              'حافظه موقت پاک شد؛ کتابخانه و دانلودها حفظ شدند.',
            ),
          );
        } catch (_) {
          if (context.mounted) {
            toast(
              context,
              tr(
                context,
                'Some cache files could not be cleared.',
                'پاک کردن بعضی فایل‌های موقت انجام نشد.',
              ),
            );
          }
        } finally {
          if (mounted) {
            setState(() {
              _busy = false;
              _size = _service.measure();
            });
          }
        }
      },
    ),
  );
}

class _ColorTile extends StatelessWidget {
  const _ColorTile({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(label),
    subtitle: Text('#${value.toRadixString(16).padLeft(8, '0').toUpperCase()}'),
    trailing: Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: Color(value),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
        borderRadius: BorderRadius.circular(8),
      ),
    ),
    onTap: () async {
      final chosen = await showDialog<int>(
        context: context,
        builder: (_) => _ColorDialog(label: label, value: value),
      );
      if (chosen != null) onChanged(chosen);
    },
  );
}

class _ColorDialog extends StatefulWidget {
  const _ColorDialog({required this.label, required this.value});
  final String label;
  final int value;
  @override
  State<_ColorDialog> createState() => _ColorDialogState();
}

class _ColorDialogState extends State<_ColorDialog> {
  late int _value = widget.value;
  late final TextEditingController _text = TextEditingController(
    text: _hex(_value),
  );
  bool _valid = true;
  String _hex(int value) =>
      value.toRadixString(16).padLeft(8, '0').toUpperCase();
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.label),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(height: 48, width: double.infinity, color: Color(_value)),
          const SizedBox(height: 16),
          TextField(
            key: const Key('custom-color-hex'),
            controller: _text,
            decoration: InputDecoration(
              labelText: 'AARRGGBB / RRGGBB',
              prefixText: '#',
              errorText: _valid
                  ? null
                  : tr(
                      context,
                      'Enter 6 or 8 hex digits',
                      '۶ یا ۸ رقم هگز وارد کنید',
                    ),
            ),
            maxLength: 8,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F]')),
            ],
            onChanged: (text) => setState(() {
              _valid = text.length == 6 || text.length == 8;
              if (_valid) {
                _value =
                    int.parse(text, radix: 16) |
                    (text.length == 6 ? 0xFF000000 : 0);
              }
            }),
          ),
          Text(
            '${tr(context, 'Opacity', 'شفافیت')}: ${((_value >> 24 & 255) / 255 * 100).round()}%',
          ),
          Slider(
            key: const Key('custom-color-opacity'),
            value: (_value >> 24 & 255) / 255,
            min: 0,
            max: 1,
            onChanged: (value) => setState(() {
              _value = ((value * 255).round() << 24) | (_value & 0xFFFFFF);
              _text.text = _hex(_value);
              _valid = true;
            }),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(tr(context, 'Cancel', 'انصراف')),
      ),
      FilledButton(
        onPressed: _valid ? () => Navigator.pop(context, _value) : null,
        child: Text(tr(context, 'Save', 'ذخیره')),
      ),
    ],
  );
}

class _DelayTile extends StatelessWidget {
  const _DelayTile({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(label),
    trailing: SizedBox(
      width: 90,
      child: TextFormField(
        key: ValueKey('$label:$value'),
        initialValue: value.toStringAsFixed(1),
        textAlign: TextAlign.center,
        keyboardType: const TextInputType.numberWithOptions(
          decimal: true,
          signed: true,
        ),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
        ],
        onFieldSubmitted: (text) {
          final parsed = double.tryParse(text);
          if (parsed != null && parsed.isFinite) {
            onChanged(parsed.clamp(-60, 60));
          }
        },
      ),
    ),
  );
}

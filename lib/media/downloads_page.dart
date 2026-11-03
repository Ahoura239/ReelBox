import 'dart:async';

import 'package:flutter/material.dart';

import '../data/models.dart';
import '../state/app_state.dart';
import 'download_service.dart';
import 'player_page.dart';

class DownloadsPage extends StatefulWidget {
  const DownloadsPage({super.key});
  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage> {
  final service = DownloadService.instance;
  Future<void>? startup;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    service.bindSettings(AppScope.read(context));
    startup ??= service.initialize();
  }

  Future<void> action(Future<void> operation) async {
    try {
      await operation;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr(context, 'Downloads', 'دانلودها'))),
    body: !service.supported
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                tr(
                  context,
                  'Background downloads and offline playback are available in the Android app.',
                  'دانلود پس‌زمینه و پخش آفلاین در برنامه اندروید در دسترس است.',
                ),
                textAlign: TextAlign.center,
              ),
            ),
          )
        : FutureBuilder<void>(
            future: startup,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          service.initializationError ??
                              'Download initialization failed.',
                        ),
                      ),
                      FilledButton(
                        onPressed: () => setState(() {
                          startup = service.initialize();
                        }),
                        child: Text(tr(context, 'Retry', 'تلاش دوباره')),
                      ),
                    ],
                  ),
                );
              }
              return AnimatedBuilder(
                animation: service,
                builder: (context, _) {
                  final items = service.items;
                  if (items.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.download_for_offline_outlined,
                              size: 52,
                            ),
                            const SizedBox(height: 18),
                            Text(
                              tr(
                                context,
                                'Your offline library starts here',
                                'کتابخانه آفلاین شما از اینجا شروع می‌شود',
                              ),
                              style: Theme.of(context).textTheme.titleLarge,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              tr(
                                context,
                                'Choose a quality on a movie or episode and tap Download.',
                                'در صفحه فیلم یا قسمت، کیفیت را انتخاب کنید و دانلود را بزنید.',
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: () => action(service.refresh()),
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: items.length,
                      itemBuilder: (_, i) {
                        final entry = items[i];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 14),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  entry.title,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                                if (entry.episodeTitle.isNotEmpty)
                                  Text(entry.episodeTitle),
                                const SizedBox(height: 6),
                                Text('${entry.quality} · ${entry.status}'),
                                if (entry.isSegmented)
                                  Text(
                                    tr(
                                      context,
                                      'Offline package · interrupted packaging resumes from verified segments after reopening. Export includes all media files.',
                                      'بسته آفلاین · پس از باز کردن دوباره، از قطعه‌های تأییدشده ادامه می‌یابد. خروجی شامل همه فایل‌ها است.',
                                    ),
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                const SizedBox(height: 10),
                                LinearProgressIndicator(
                                  value:
                                      entry.isSegmented ||
                                          entry.totalBytes > 0 ||
                                          entry.isComplete
                                      ? entry.progress
                                      : null,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '${(entry.progress * 100).round()}% · ${_bytes(entry.receivedBytes)} / ${entry.totalBytes > 0 ? _bytes(entry.totalBytes) : '—'}${entry.speed > 0 ? ' · ${_bytes(entry.speed.round())}/s' : ''}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                if (entry.error.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(
                                      entry.error,
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .error,
                                      ),
                                    ),
                                  ),
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    if (entry.canPause)
                                      IconButton(
                                        tooltip: tr(context, 'Pause', 'توقف'),
                                        icon: const Icon(Icons.pause),
                                        onPressed: () =>
                                            action(service.pause(entry)),
                                      ),
                                    if (entry.canResume)
                                      IconButton(
                                        tooltip: tr(context, 'Resume', 'ادامه'),
                                        icon: const Icon(Icons.play_arrow),
                                        onPressed: () =>
                                            action(service.resume(entry)),
                                      ),
                                    if (entry.isActive)
                                      IconButton(
                                        tooltip: tr(context, 'Cancel', 'لغو'),
                                        icon: const Icon(Icons.cancel_outlined),
                                        onPressed: () =>
                                            action(service.cancel(entry)),
                                      ),
                                    if (entry.isComplete) ...[
                                      FilledButton.tonalIcon(
                                        icon: const Icon(Icons.play_arrow),
                                        label: Text(
                                          tr(
                                            context,
                                            'Play offline',
                                            'پخش آفلاین',
                                          ),
                                        ),
                                        onPressed: () =>
                                            action(playOffline(entry)),
                                      ),
                                      IconButton(
                                        tooltip: tr(
                                          context,
                                          'Open file externally',
                                          'باز کردن فایل بیرونی',
                                        ),
                                        icon: const Icon(Icons.open_in_new),
                                        onPressed: () =>
                                            action(service.open(entry)),
                                      ),
                                      IconButton(
                                        tooltip: tr(
                                          context,
                                          'Reveal / export offline media',
                                          'نمایش / خروجی رسانه آفلاین',
                                        ),
                                        icon: const Icon(Icons.ios_share),
                                        onPressed: () =>
                                            action(service.reveal(entry)),
                                      ),
                                    ],
                                    if (!entry.isSegmented)
                                      PopupMenuButton<String>(
                                        tooltip: tr(
                                          context,
                                          'External downloader',
                                          'دانلودر بیرونی',
                                        ),
                                        icon: const Icon(
                                          Icons.download_for_offline_outlined,
                                        ),
                                        onSelected: (package) => action(
                                          service.externalDownloader(
                                            entry,
                                            packageName: package,
                                          ),
                                        ),
                                        itemBuilder: (_) => [
                                          PopupMenuItem(
                                            value: 'ask',
                                            child: Text(
                                              tr(
                                                context,
                                                'Choose downloader…',
                                                'انتخاب دانلودر…',
                                              ),
                                            ),
                                          ),
                                          const PopupMenuItem(
                                            value: 'ADM',
                                            child: Text('ADM'),
                                          ),
                                          const PopupMenuItem(
                                            value: 'IDM',
                                            child: Text('IDM'),
                                          ),
                                        ],
                                      ),
                                    if (!entry.isActive &&
                                        !entry.canResume &&
                                        !entry.isComplete)
                                      IconButton(
                                        tooltip: tr(
                                          context,
                                          'Retry',
                                          'تلاش دوباره',
                                        ),
                                        icon: const Icon(Icons.refresh),
                                        onPressed: () =>
                                            action(service.retry(entry)),
                                      ),
                                    IconButton(
                                      tooltip: tr(
                                        context,
                                        'Delete file and record',
                                        'حذف فایل و سابقه',
                                      ),
                                      icon: const Icon(Icons.delete_outline),
                                      onPressed: () async {
                                        final confirmed =
                                            await showDialog<bool>(
                                              context: context,
                                              builder: (dialogContext) =>
                                                  AlertDialog(
                                                    title: Text(
                                                      tr(
                                                        context,
                                                        'Delete this download?',
                                                        'این دانلود حذف شود؟',
                                                      ),
                                                    ),
                                                    content: Text(entry.title),
                                                    actions: [
                                                      TextButton(
                                                        onPressed: () =>
                                                            Navigator.pop(
                                                              dialogContext,
                                                              false,
                                                            ),
                                                        child: Text(
                                                          tr(
                                                            context,
                                                            'Cancel',
                                                            'انصراف',
                                                          ),
                                                        ),
                                                      ),
                                                      FilledButton(
                                                        onPressed: () =>
                                                            Navigator.pop(
                                                              dialogContext,
                                                              true,
                                                            ),
                                                        child: Text(
                                                          tr(
                                                            context,
                                                            'Delete',
                                                            'حذف',
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                            );
                                        if (confirmed == true) {
                                          await action(service.remove(entry));
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              );
            },
          ),
  );
  Future<void> playOffline(DownloadEntry entry) async {
    final path = await service.offlinePath(entry);
    if (!mounted) return;
    final title = entry.restoredTitle;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayerPage(
          title: title,
          source: MediaSource(
            url: entry.url,
            quality: entry.quality,
            type: entry.sourceType,
          ),
          localFile: path,
          episode: entry.episodeId == null
              ? null
              : EpisodeRecord(id: entry.episodeId!, title: entry.episodeTitle),
        ),
      ),
    );
  }

  String _bytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/content_policy.dart';
import '../state/app_state.dart';
import 'catalog.dart';

enum ToastKind { info, success, error }

void toast(
  BuildContext context,
  String message, {
  ToastKind kind = ToastKind.info,
}) {
  if (!context.mounted) return;
  final colors = Theme.of(context).colorScheme;
  final text = ContentPolicy.sanitizeText(message);
  final background = switch (kind) {
    ToastKind.error => colors.errorContainer,
    ToastKind.success => colors.tertiaryContainer,
    ToastKind.info => colors.inverseSurface,
  };
  final foreground = switch (kind) {
    ToastKind.error => colors.onErrorContainer,
    ToastKind.success => colors.onTertiaryContainer,
    ToastKind.info => colors.onInverseSurface,
  };
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      backgroundColor: background,
      showCloseIcon: true,
      closeIconColor: foreground,
      content: Row(
        children: [
          Icon(
            switch (kind) {
              ToastKind.error => Icons.error_outline,
              ToastKind.success => Icons.check_circle_outline,
              ToastKind.info => Icons.info_outline,
            },
            color: foreground,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text.isEmpty
                  ? tr(
                      context,
                      'This content is not available',
                      'این محتوا در دسترس نیست',
                    )
                  : text,
              style: TextStyle(color: foreground),
            ),
          ),
        ],
      ),
    ),
  );
}

void goTitle(BuildContext context, TitleRecord title) {
  if (!ContentPolicy.allowsTitleJson(title.toJson()) ||
      title.id <= 0 ||
      title.title.isEmpty) {
    toast(
      context,
      tr(context, 'This content is not available', 'این محتوا در دسترس نیست'),
    );
    return;
  }
  Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => TitlePage(title: title)));
}

class EmptyView extends StatelessWidget {
  const EmptyView({
    super.key,
    required this.title,
    this.message,
    this.icon = Icons.movie_outlined,
    this.onRetry,
  });
  final String title;
  final String? message;
  final IconData icon;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 44, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 18),
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          if (message != null) ...[
            const SizedBox(height: 10),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (onRetry != null) ...[
            const SizedBox(height: 20),
            FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(tr(context, 'Try again', 'تلاش دوباره')),
            ),
          ],
        ],
      ),
    ),
  );
}

class AsyncResult<T> extends StatelessWidget {
  const AsyncResult({
    super.key,
    required this.future,
    required this.builder,
    this.onRetry,
  });
  final Future<T> future;
  final Widget Function(T) builder;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(48),
            child: CircularProgressIndicator(),
          ),
        );
      }
      if (snapshot.hasError) {
        return EmptyView(
          title: tr(
            context,
            'Could not load this page',
            'بارگذاری صفحه ممکن نشد',
          ),
          message: snapshot.error.toString(),
          icon: Icons.wifi_off_rounded,
          onRetry: onRetry,
        );
      }
      if (!snapshot.hasData) {
        return EmptyView(
          title: tr(context, 'Nothing here yet', 'هنوز محتوایی وجود ندارد'),
        );
      }
      return builder(snapshot.data as T);
    },
  );
}

class MediaArtwork extends StatelessWidget {
  const MediaArtwork({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
  });
  final String url;
  final BoxFit fit;
  final double? width, height;
  @override
  Widget build(BuildContext context) {
    Widget fallback() => ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.local_movies_outlined,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          size: 32,
        ),
      ),
    );
    final dataSaver =
        context
            .dependOnInheritedWidgetOfExactType<AppScope>()
            ?.notifier
            ?.prefs
            .dataSaver ??
        false;
    if (url.isEmpty || dataSaver || !ContentPolicy.allowsUrl(url)) {
      return SizedBox(width: width, height: height, child: fallback());
    }
    return Image.network(
      url,
      fit: fit,
      width: width,
      height: height,
      cacheWidth: width == null
          ? 480
          : (width! * MediaQuery.devicePixelRatioOf(context)).round().clamp(
              1,
              1200,
            ),
      errorBuilder: (_, _, _) =>
          SizedBox(width: width, height: height, child: fallback()),
      loadingBuilder: (_, child, progress) =>
          progress == null ? child : fallback(),
    );
  }
}

class PosterCard extends StatelessWidget {
  const PosterCard({super.key, required this.title, this.width = 132});
  final TitleRecord title;
  final double width;
  @override
  Widget build(BuildContext context) {
    if (!ContentPolicy.allowsTitleJson(title.toJson()) ||
        title.id <= 0 ||
        title.title.isEmpty) {
      return const SizedBox.shrink();
    }
    final state = AppScope.of(context);
    return SizedBox(
      width: width,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => goTitle(context, title),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    MediaArtwork(url: title.image, width: width),
                    if (title.imdb > 0)
                      PositionedDirectional(
                        top: 8,
                        start: 8,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: .78),
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 4,
                            ),
                            child: Text(
                              '★ ${title.imdb.toStringAsFixed(1)}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFFFFD777),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    PositionedDirectional(
                      bottom: 6,
                      end: 6,
                      child: IconButton.filledTonal(
                        constraints: const BoxConstraints.tightFor(
                          width: 32,
                          height: 32,
                        ),
                        padding: EdgeInsets.zero,
                        iconSize: 18,
                        tooltip: tr(context, 'Watchlist', 'تماشای بعدی'),
                        onPressed: () async {
                          try {
                            await state.toggleSaved(title);
                          } catch (error) {
                            if (context.mounted) {
                              toast(
                                context,
                                error.toString(),
                                kind: ToastKind.error,
                              );
                            }
                          }
                        },
                        icon: Icon(
                          state.hasSaved(title.id, kind: title.type)
                              ? Icons.bookmark_rounded
                              : Icons.bookmark_border_rounded,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 9),
            Text(
              title.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 3),
            Text(
              [
                if (title.year > 0) '${title.year}',
                title.isSeries
                    ? tr(context, 'Series', 'سریال')
                    : tr(context, 'Movie', 'فیلم'),
              ].join(' · '),
              maxLines: 1,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PosterRail extends StatelessWidget {
  const PosterRail({
    super.key,
    required this.title,
    required this.items,
    this.onMore,
  });
  final String title;
  final List<TitleRecord> items;
  final VoidCallback? onMore;
  @override
  Widget build(BuildContext context) {
    final visible = items
        .where(
          (item) =>
              item.id > 0 &&
              item.title.isNotEmpty &&
              ContentPolicy.allowsTitleJson(item.toJson()),
        )
        .toList();
    if (visible.isEmpty || !ContentPolicy.allowsText(title)) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (onMore != null)
                  TextButton(
                    onPressed: onMore,
                    child: Text(tr(context, 'See all', 'نمایش همه')),
                  ),
              ],
            ),
          ),
          SizedBox(
            height: 244,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              scrollDirection: Axis.horizontal,
              itemCount: visible.length,
              separatorBuilder: (_, _) => const SizedBox(width: 13),
              itemBuilder: (_, index) => PosterCard(title: visible[index]),
            ),
          ),
        ],
      ),
    );
  }
}

class PosterGrid extends StatelessWidget {
  const PosterGrid({super.key, required this.items});
  final List<TitleRecord> items;
  @override
  Widget build(BuildContext context) {
    final visible = items
        .where(
          (item) =>
              item.id > 0 &&
              item.title.isNotEmpty &&
              ContentPolicy.allowsTitleJson(item.toJson()),
        )
        .toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    final state = AppScope.of(context);
    if (state.prefs.compactCatalog) {
      return ListView.separated(
        padding: const EdgeInsets.all(16),
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: visible.length,
        separatorBuilder: (_, _) => const Divider(height: 8),
        itemBuilder: (context, index) {
          final title = visible[index];
          return ListTile(
            key: ValueKey('compact-title-row:${title.libraryKey}'),
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            minTileHeight: 96,
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: MediaArtwork(url: title.image, width: 56, height: 80),
            ),
            title: Text(
              title.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              [
                if (title.year > 0) '${title.year}',
                title.isSeries
                    ? tr(context, 'Series', 'سریال')
                    : tr(context, 'Movie', 'فیلم'),
                if (title.imdb > 0) 'IMDb ${title.imdb.toStringAsFixed(1)}',
              ].join(' · '),
            ),
            onTap: () => goTitle(context, title),
            trailing: IconButton(
              tooltip: tr(context, 'Watchlist', 'تماشای بعدی'),
              icon: Icon(
                state.hasSaved(title.id, kind: title.type)
                    ? Icons.bookmark
                    : Icons.bookmark_outline,
              ),
              onPressed: () async {
                try {
                  await state.toggleSaved(title);
                } catch (error) {
                  if (context.mounted) {
                    toast(context, error.toString(), kind: ToastKind.error);
                  }
                }
              },
            ),
          );
        },
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 190,
        childAspectRatio: .56,
        mainAxisSpacing: 20,
        crossAxisSpacing: 14,
      ),
      itemCount: visible.length,
      itemBuilder: (_, index) => PosterCard(title: visible[index]),
    );
  }
}

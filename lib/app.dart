import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'data/api_service.dart';
import 'state/app_state.dart';
import 'ui/catalog.dart';
import 'ui/library.dart';

class MyApp extends StatefulWidget {
  const MyApp({super.key, this.state});
  final AppState? state;
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final AppState state = widget.state ?? AppState(api: ApiService());
  @override
  void dispose() {
    if (widget.state == null) state.dispose();
    super.dispose();
  }

  ThemeData theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final colors = ColorScheme.fromSeed(
      seedColor: const Color(0xFFFF675C),
      brightness: brightness,
      primary: dark ? const Color(0xFFFF8276) : const Color(0xFFBC3D34),
      surface: dark ? const Color(0xFF0B0D12) : const Color(0xFFFAF8F5),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colors,
      scaffoldBackgroundColor: colors.surface,
      visualDensity: VisualDensity.standard,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: colors.surface,
        titleTextStyle: TextStyle(
          fontFamily: 'Roboto',
          color: colors.onSurface,
          fontSize: 23,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: colors.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceContainer,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide.none,
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      dividerTheme: DividerThemeData(
        color: colors.outlineVariant.withValues(alpha: .45),
        space: 1,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 74,
        backgroundColor: colors.surfaceContainerLow,
        indicatorColor: colors.primary.withValues(alpha: .17),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AppScope(
    notifier: state,
    child: AnimatedBuilder(
      animation: state,
      builder: (_, _) => MaterialApp(
        title: 'Reelbox',
        debugShowCheckedModeBanner: false,
        theme: theme(Brightness.light),
        darkTheme: theme(Brightness.dark),
        themeMode: switch (state.prefs.theme) {
          'light' => ThemeMode.light,
          'system' => ThemeMode.system,
          _ => ThemeMode.dark,
        },
        locale: Locale(state.locale),
        supportedLocales: const [Locale('en'), Locale('fa')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: state.prefs.introCompleted
            ? const _AppShell()
            : const FirstRunIntroPage(),
      ),
    ),
  );
}

class _AppShell extends StatefulWidget {
  const _AppShell();
  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> {
  int selected = 0;
  final List<Widget?> pages = [const DiscoverPage(), null, null, null, null];
  Widget page(int index) => switch (index) {
    0 => const DiscoverPage(),
    1 => const BrowsePage(),
    2 => const SearchPage(),
    3 => const LibraryPage(),
    _ => const MorePage(),
  };
  @override
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(
      index: selected,
      children: [for (final p in pages) p ?? const SizedBox.shrink()],
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: selected,
      onDestinationSelected: (index) => setState(() {
        selected = index;
        pages[index] ??= page(index);
      }),
      destinations: [
        NavigationDestination(
          icon: const Icon(Icons.explore_outlined),
          selectedIcon: const Icon(Icons.explore),
          label: tr(context, 'Discover', 'کشف'),
        ),
        NavigationDestination(
          icon: const Icon(Icons.grid_view_outlined),
          selectedIcon: const Icon(Icons.grid_view_rounded),
          label: tr(context, 'Browse', 'مرور'),
        ),
        NavigationDestination(
          icon: const Icon(Icons.search_rounded),
          label: tr(context, 'Search', 'جستجو'),
        ),
        NavigationDestination(
          icon: const Icon(Icons.video_library_outlined),
          selectedIcon: const Icon(Icons.video_library_rounded),
          label: tr(context, 'Library', 'کتابخانه'),
        ),
        NavigationDestination(
          icon: const Icon(Icons.tune_rounded),
          label: tr(context, 'More', 'بیشتر'),
        ),
      ],
    ),
  );
}

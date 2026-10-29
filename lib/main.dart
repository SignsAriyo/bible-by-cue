import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/app_services.dart';
import 'core/bible_repository.dart';
import 'core/reference.dart';
import 'core/user_store.dart';
import 'ui/bible_page.dart';
import 'ui/common.dart';
import 'ui/home_page.dart';
import 'ui/notes_page.dart';
import 'ui/saved_page.dart';
import 'ui/settings_page.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const BibleByCueApp());
}

class BibleByCueApp extends StatefulWidget {
  const BibleByCueApp({super.key});
  @override
  State<BibleByCueApp> createState() => _BibleByCueAppState();
}

class _BibleByCueAppState extends State<BibleByCueApp> {
  Services? _services;
  double _progress = 0;
  bool _firstSetup = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  /// Opens both databases exactly once. The Bible database is built on first launch only.
  Future<void> _start() async {
    setState(() => _error = null);
    try {
      final store = await UserStore.open(const LooseVersification());
      final settings = AppSettings(store, await store.loadPrefs());
      final installed = await store.installedTranslations();
      var translation = installed.firstWhere((t) => t.code == settings.translation, orElse: () => webTranslation);
      if (!await BibleRepository.isInstalled(translation) && !translation.builtIn) translation = webTranslation;
      _firstSetup = !await BibleRepository.isInstalled(translation);
      if (_firstSetup) setState(() {});
      final bible = await BibleRepository.open(translation, onProgress: (p) {
        if (mounted && _firstSetup) setState(() => _progress = p);
      });
      store.versification = bible;
      Services.I = Services(bible, store, settings);
      if (mounted) setState(() => _services = Services.I);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _services;
    return ListenableBuilder(
      listenable: s?.settings ?? ValueNotifier(0),
      builder: (context, _) => MaterialApp(
        title: 'Bible by Cue',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: s?.settings.themeMode ?? ThemeMode.system,
        home: s == null
            ? _Preparing(progress: _progress, firstSetup: _firstSetup, error: _error, onRetry: _start)
            : (s.settings.onboarded ? const AppShell() : const WelcomePage()),
      ),
    );
  }
}

class _Preparing extends StatelessWidget {
  final double progress;
  final bool firstSetup;
  final Object? error;
  final VoidCallback onRetry;
  const _Preparing({required this.progress, required this.firstSetup, required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const AppMark(size: 76),
              const SizedBox(height: 20),
              Text('Bible by Cue', style: context.text.headlineSmall),
              const SizedBox(height: 28),
              if (error != null) ...[
                Text('The Bible could not be prepared.', style: context.text.titleMedium),
                const SizedBox(height: 8),
                Text('$error', textAlign: TextAlign.center, style: TextStyle(color: context.muted)),
                const SizedBox(height: 8),
                Text('Make sure your device has some free storage, then try again.', textAlign: TextAlign.center, style: TextStyle(color: context.muted)),
                const SizedBox(height: 16),
                FilledButton(onPressed: onRetry, child: const Text('Try again')),
              ] else if (firstSetup) ...[
                SizedBox(
                  width: 220,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(value: progress, minHeight: 6, semanticsLabel: 'Preparing the Bible'),
                  ),
                ),
                const SizedBox(height: 14),
                Text('Preparing your Bible for offline reading…', style: TextStyle(color: context.muted)),
                const SizedBox(height: 4),
                Text('This happens only once.', style: context.text.bodySmall?.copyWith(color: context.muted)),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final points = [
      (Icons.wifi_off, 'Complete and offline', 'The full World English Bible, searchable and ready without internet.'),
      (Icons.edit_note, 'Sermon notes that know Scripture', 'Type John 3:16 in a note and tap it — the passage opens instantly.'),
      (Icons.lock_outline, 'Private by design', 'No account. Your notes and highlights never leave this device.'),
    ];
    return Scaffold(
      body: SafeArea(
        child: ReadableWidth(
          max: 560,
          child: ListView(padding: const EdgeInsets.fromLTRB(28, 48, 28, 28), children: [
            const Align(alignment: Alignment.centerLeft, child: AppMark(size: 64)),
            const SizedBox(height: 24),
            Text('Bible by Cue', style: context.text.displaySmall),
            const SizedBox(height: 4),
            Text('Created by Cue', style: context.text.titleMedium?.copyWith(color: context.colors.secondary)),
            const SizedBox(height: 32),
            for (final (icon, title, body) in points)
              Padding(
                padding: const EdgeInsets.only(bottom: 22),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: context.colors.primaryContainer, borderRadius: BorderRadius.circular(14)),
                    child: Icon(icon, color: context.colors.onPrimaryContainer),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(body, style: TextStyle(color: context.muted, height: 1.45)),
                    ]),
                  ),
                ]),
              ),
            const SizedBox(height: 20),
            FilledButton(
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              onPressed: () => services.settings.onboarded = true,
              child: const Text('Begin'),
            ),
          ]),
        ),
      ),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  final _visited = <int>{0};

  static const _destinations = [
    (Icons.home_outlined, Icons.home, 'Home'),
    (Icons.menu_book_outlined, Icons.menu_book, 'Bible'),
    (Icons.sticky_note_2_outlined, Icons.sticky_note_2, 'Notes'),
    (Icons.bookmark_border, Icons.bookmark, 'Saved'),
    (Icons.settings_outlined, Icons.settings, 'Settings'),
  ];

  void _go(int i) => setState(() {
        _index = i;
        _visited.add(i);
      });

  Widget _page(int i) => switch (i) {
        0 => HomePage(onNavigate: _go),
        1 => const BiblePage(),
        2 => const NotesPage(),
        3 => const SavedPage(),
        _ => const SettingsPage(),
      };

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    // Tablets and landscape phones use a side rail; on short screens the rail drops its labels
    // and logo so all destinations always fit.
    final wide = size.width >= 840 || (size.width > size.height && size.width >= 640);
    final compactRail = size.height < 560;
    // Pages are created lazily the first time they are opened, then kept alive.
    final body = IndexedStack(
      index: _index,
      children: [for (var i = 0; i < 5; i++) _visited.contains(i) ? _page(i) : const SizedBox.shrink()],
    );
    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _go(0);
      },
      child: wide
          ? Scaffold(
              body: Row(children: [
                SafeArea(
                  right: false,
                  child: NavigationRail(
                    selectedIndex: _index,
                    onDestinationSelected: _go,
                    labelType: compactRail ? NavigationRailLabelType.none : NavigationRailLabelType.all,
                    leading: compactRail ? null : const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: AppMark(size: 40)),
                    destinations: [
                      for (final (icon, sel, label) in _destinations)
                        NavigationRailDestination(
                          icon: compactRail ? Tooltip(message: label, child: Icon(icon)) : Icon(icon),
                          selectedIcon: compactRail ? Tooltip(message: label, child: Icon(sel)) : Icon(sel),
                          label: Text(label),
                        ),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: body),
              ]),
            )
          : Scaffold(
              body: body,
              bottomNavigationBar: NavigationBar(
                selectedIndex: _index,
                onDestinationSelected: _go,
                destinations: [
                  for (final (icon, sel, label) in _destinations)
                    NavigationDestination(icon: Icon(icon), selectedIcon: Icon(sel), label: label),
                ],
              ),
            ),
    );
  }
}

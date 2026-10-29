import 'package:flutter/material.dart';

import '../core/bible_repository.dart';
import '../core/books.dart';
import '../core/content.dart';
import '../core/reference.dart';
import '../core/user_store.dart';
import 'bible_page.dart';
import 'common.dart';
import 'note_editor.dart';
import 'notes_page.dart';
import 'plans_page.dart';
import 'search_page.dart';
import 'share_card.dart';
import 'theme.dart';

/// Everything shown on Home depends on these; each section listens itself because const
/// children are not rebuilt when a parent rebuilds.
final Listenable _homeChanges = Listenable.merge([services.store, services.bibleChanged, services.settings]);

class HomePage extends StatelessWidget {
  final ValueChanged<int> onNavigate;
  const HomePage({super.key, required this.onNavigate});

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 5) return 'Peace be with you';
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Builder(
          builder: (context) => ListView(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 32),
            children: [
              ReadableWidth(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(longDate(DateTime.now()).toUpperCase(),
                              style: context.text.labelSmall?.copyWith(letterSpacing: 1.4, color: context.muted)),
                          const SizedBox(height: 4),
                          Text(_greeting(), style: context.text.headlineMedium),
                        ]),
                      ),
                      IconButton.filledTonal(
                        tooltip: 'Search',
                        icon: const Icon(Icons.search),
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchPage())),
                      ),
                    ]),
                    const SizedBox(height: 20),
                    const _VerseOfTheDay(),
                    const SizedBox(height: 14),
                    const _ContinueAndPlans(),
                    const SectionHeader('Quick actions'),
                    _QuickActions(onNavigate: onNavigate),
                    const _RecentNotes(),
                    const _RecentPassages(),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VerseOfTheDay extends StatelessWidget {
  const _VerseOfTheDay();

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: _homeChanges, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final ref = verseOfTheDay(DateTime.now(), services.bible);
    return FutureBuilder<List<Verse>>(
      future: services.bible.passage(ref),
      builder: (context, snap) {
        final verses = snap.data;
        final text = verses == null ? '' : passagePlain(verses);
        final colors = context.colors;
        return Container(
          decoration: BoxDecoration(
            color: context.isDark ? Palette.sageDeep : Palette.forest,
            borderRadius: BorderRadius.circular(24),
          ),
          padding: const EdgeInsets.fromLTRB(22, 20, 12, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('VERSE OF THE DAY',
                style: context.text.labelSmall?.copyWith(letterSpacing: 1.6, color: Colors.white.withValues(alpha: 0.75))),
            const SizedBox(height: 12),
            AnimatedOpacity(
              opacity: verses == null ? 0 : 1,
              duration: const Duration(milliseconds: 250),
              child: Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Text('“$text”',
                    style: const TextStyle(fontFamily: readingFont, fontSize: 19, height: 1.55, color: Colors.white)),
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: Text('${ref.label} · ${services.bible.translation.abbreviation}',
                    style: context.text.titleSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
              ),
              IconButton(
                tooltip: 'Share as image',
                color: Colors.white,
                icon: const Icon(Icons.image_outlined),
                onPressed: verses == null ? null : () => showShareCard(context, ref, text),
              ),
              IconButton(
                tooltip: 'Copy',
                color: Colors.white,
                icon: const Icon(Icons.copy_rounded),
                onPressed: verses == null
                    ? null
                    : () => copyToClipboard(context, passageForSharing(verses, ref, services.bible.translation.abbreviation)),
              ),
              IconButton(
                tooltip: 'Read in context',
                color: colors.onPrimary,
                icon: const Icon(Icons.arrow_forward, color: Colors.white),
                onPressed: () => openReader(context, ref),
              ),
            ]),
          ]),
        );
      },
    );
  }
}

class _ContinueAndPlans extends StatelessWidget {
  const _ContinueAndPlans();

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: _homeChanges, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final last = services.settings.lastPosition;
    final plans = services.settings.activePlans.map(ReadingPlan.byId).whereType<ReadingPlan>().toList();
    return Column(children: [
      if (last != null)
        Card(
          child: ListTile(
            contentPadding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
            leading: CircleAvatar(backgroundColor: context.colors.primaryContainer, child: Icon(Icons.auto_stories_outlined, color: context.colors.primary)),
            title: const Text('Continue reading'),
            subtitle: Text('${bookByNumber(bookOf(last)).name} ${chapterOf(last)}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => openReader(context, Reference(bookOf(last), chapterOf(last), verseOf(last) > 1 ? verseOf(last) : null)),
          ),
        )
      else
        Card(
          child: ListTile(
            contentPadding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
            leading: CircleAvatar(backgroundColor: context.colors.primaryContainer, child: Icon(Icons.auto_stories_outlined, color: context.colors.primary)),
            title: const Text('Start reading'),
            subtitle: const Text('Begin with the Gospel of John'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => openReader(context, const Reference(43, 1)),
          ),
        ),
      for (final p in plans) ...[
        const SizedBox(height: 10),
        FutureBuilder<Set<int>>(
          future: services.store.planDaysDone(p.id),
          builder: (context, snap) {
            final done = snap.data ?? const <int>{};
            var next = 0;
            while (next < p.days && done.contains(next)) {
              next++;
            }
            final finished = next >= p.days;
            return Card(
              child: ListTile(
                contentPadding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
                leading: CircleAvatar(
                    backgroundColor: context.colors.secondaryContainer, child: Icon(Icons.event_available_outlined, color: context.colors.secondary)),
                title: Text(p.title),
                subtitle: Text(finished ? 'Plan complete — well done!' : 'Day ${next + 1}: ${describeChapters(p.chaptersForDay(next))}',
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: Text('${(done.length * 100 / p.days).round()}%',
                    style: context.text.labelLarge?.copyWith(color: context.colors.secondary, fontWeight: FontWeight.w700)),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PlanDetailPage(plan: p))),
              ),
            );
          },
        ),
      ],
    ]);
  }
}

class _QuickActions extends StatelessWidget {
  final ValueChanged<int> onNavigate;
  const _QuickActions({required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    final actions = [
      (Icons.church_outlined, 'Sermon note', () => createAndOpenNote(context, sermonTemplate: true)),
      (Icons.travel_explore, 'Go to passage', () async {
        final r = await showPassagePicker(context);
        if (r != null && context.mounted) openReader(context, r);
      }),
      (Icons.event_note_outlined, 'Reading plans', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PlansPage()))),
      (Icons.bookmark_border, 'Saved', () => onNavigate(3)),
    ];
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth > 520 ? 4 : 2;
      final w = (c.maxWidth - (cols - 1) * 10) / cols;
      return Wrap(spacing: 10, runSpacing: 10, children: [
        for (final (icon, label, onTap) in actions)
          SizedBox(
            width: w,
            child: Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    Icon(icon, color: context.colors.primary),
                    const SizedBox(width: 12),
                    Expanded(child: Text(label, style: context.text.titleSmall)),
                  ]),
                ),
              ),
            ),
          ),
      ]);
    });
  }
}

class _RecentNotes extends StatelessWidget {
  const _RecentNotes();

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: _homeChanges, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    return FutureBuilder<List<Note>>(
      future: services.store.notes(limit: 3),
      builder: (context, snap) {
        final notes = snap.data ?? const <Note>[];
        if (notes.isEmpty) return const SizedBox.shrink();
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SectionHeader('Recent notes'),
          for (final n in notes) ...[
            NoteCard(note: n, onTap: () => openNote(context, n.id)),
            const SizedBox(height: 10),
          ],
        ]);
      },
    );
  }
}

class _RecentPassages extends StatelessWidget {
  const _RecentPassages();

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: _homeChanges, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    return FutureBuilder(
      future: services.store.history(limit: 6),
      builder: (context, snap) {
        final list = snap.data ?? const [];
        if (list.isEmpty) return const SizedBox.shrink();
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SectionHeader('Recently read'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final h in list)
              ActionChip(
                avatar: const Icon(Icons.history, size: 16),
                label: Text('${bookByNumber(h.book).name} ${h.chapter}'),
                onPressed: () => openReader(context, Reference(h.book, h.chapter)),
              ),
          ]),
        ]);
      },
    );
  }
}

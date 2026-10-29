import 'package:flutter/material.dart';

import '../core/books.dart';
import '../core/reference.dart';
import '../core/user_store.dart';
import 'common.dart';
import 'reader_page.dart';
import 'theme.dart';

class SavedPage extends StatefulWidget {
  const SavedPage({super.key});
  @override
  State<SavedPage> createState() => _SavedPageState();
}

class _HighlightGroup {
  final int start, end, color;
  _HighlightGroup(this.start, this.end, this.color);
  Reference get reference => Reference.fromIds(start, end);
}

class _SavedPageState extends State<SavedPage> {
  int _tab = 0;
  String _query = '';
  List<Bookmark>? _bookmarks;
  List<_HighlightGroup>? _highlights;
  List<HistoryEntry>? _history;
  int? _colorFilter;
  final Map<String, String> _texts = {};

  @override
  void initState() {
    super.initState();
    services.store.addListener(_load);
    services.bibleChanged.addListener(_reloadTexts);
    _load();
  }

  @override
  void dispose() {
    services.store.removeListener(_load);
    services.bibleChanged.removeListener(_reloadTexts);
    super.dispose();
  }

  void _reloadTexts() {
    _texts.clear();
    _load();
  }

  Future<void> _load() async {
    final s = services.store;
    final bookmarks = await s.bookmarks(query: _query);
    final hl = await s.highlights();
    final history = await s.history();
    // Merge adjacent verses with the same colour into one passage.
    final sorted = [...hl]..sort((a, b) => a.verseId.compareTo(b.verseId));
    final groups = <_HighlightGroup>[];
    for (final h in sorted) {
      if (groups.isNotEmpty && groups.last.color == h.color && groups.last.end + 1 == h.verseId) {
        groups[groups.length - 1] = _HighlightGroup(groups.last.start, h.verseId, h.color);
      } else {
        groups.add(_HighlightGroup(h.verseId, h.verseId, h.color));
      }
    }
    final created = {for (final h in hl) h.verseId: h.createdAt};
    groups.sort((a, b) => (created[b.start] ?? 0).compareTo(created[a.start] ?? 0));
    if (!mounted) return;
    setState(() {
      _bookmarks = bookmarks;
      _highlights = groups;
      _history = history;
    });
  }

  Future<String> _text(int start, int end) async {
    final key = '$start-$end';
    final cached = _texts[key];
    if (cached != null) return cached;
    final vs = await services.bible.range(start, end < start + 5 ? end : start + 5);
    final t = passagePlain(vs) + (end > start + 5 ? ' …' : '');
    return _texts[key] = t;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Saved')),
      body: ReadableWidth(
        max: 840,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 0, label: SegmentLabel('Bookmarks'), icon: Icon(Icons.bookmark_border)),
                ButtonSegment(value: 1, label: SegmentLabel('Highlights'), icon: Icon(Icons.border_color_outlined)),
                ButtonSegment(value: 2, label: SegmentLabel('History'), icon: Icon(Icons.history)),
              ],
              selected: {_tab},
              onSelectionChanged: (s) => setState(() => _tab = s.first),
            ),
          ),
          if (_tab != 2)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: _tab == 0 ? 'Search references and comments' : 'Search highlighted references',
                ),
                onChanged: (q) {
                  setState(() => _query = q);
                  _load();
                },
              ),
            ),
          Expanded(child: switch (_tab) { 0 => _bookmarkList(context), 1 => _highlightList(context), _ => _historyList(context) }),
        ]),
      ),
    );
  }

  Widget _passageCard(BuildContext context, {required Reference ref, required int start, required int end, Color? swatch, String? comment, required List<PopupMenuEntry<VoidCallback>> menu}) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => openReader(context, ref),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (swatch != null)
              Container(width: 6, height: 52, margin: const EdgeInsets.only(right: 12, top: 2), decoration: BoxDecoration(color: swatch, borderRadius: BorderRadius.circular(3))),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(ref.label, style: context.text.titleSmall?.copyWith(color: context.colors.primary, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                FutureBuilder(
                  future: _text(start, end),
                  builder: (context, snap) => Text(snap.data ?? '',
                      maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: readingFont, height: 1.45, fontSize: 15)),
                ),
                if (comment != null && comment.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: context.colors.surfaceContainerHigh, borderRadius: BorderRadius.circular(10)),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(Icons.chat_bubble_outline, size: 16, color: context.muted),
                      const SizedBox(width: 8),
                      Expanded(child: Text(comment, style: context.text.bodyMedium)),
                    ]),
                  ),
                ],
              ]),
            ),
            PopupMenuButton<VoidCallback>(tooltip: 'Options', onSelected: (f) => f(), itemBuilder: (_) => menu),
          ]),
        ),
      ),
    );
  }

  Widget _bookmarkList(BuildContext context) {
    final list = _bookmarks;
    if (list == null) return const SizedBox.shrink();
    if (list.isEmpty) {
      return EmptyState(
        icon: Icons.bookmark_border,
        title: _query.isEmpty ? 'No bookmarks yet' : 'No matching bookmarks',
        message: _query.isEmpty ? 'Tap verses in the Bible and choose Bookmark to keep them here, with your own comments.' : 'Try another word.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: list.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final b = list[i];
        return _passageCard(context, ref: b.reference, start: b.startId, end: b.endId, comment: b.comment, menu: [
          PopupMenuItem(value: () => editBookmarkComment(context, b), child: Text(b.comment.isEmpty ? 'Add comment' : 'Edit comment')),
          PopupMenuItem(value: () => _copy(b.reference, b.startId, b.endId), child: const Text('Copy')),
          PopupMenuItem(value: () => services.store.deleteBookmark(b.id), child: const Text('Remove bookmark')),
        ]);
      },
    );
  }

  Future<void> _copy(Reference r, int start, int end) async {
    final vs = await services.bible.range(start, end);
    if (mounted) await copyToClipboard(context, passageForSharing(vs, r, services.bible.translation.abbreviation));
  }

  Widget _highlightList(BuildContext context) {
    var list = _highlights;
    if (list == null) return const SizedBox.shrink();
    final q = _query.trim().toLowerCase();
    list = list.where((g) => (_colorFilter == null || g.color == _colorFilter) && (q.isEmpty || g.reference.label.toLowerCase().contains(q))).toList();
    return Column(children: [
      SizedBox(
        height: 48,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
          ChoiceChip(label: const Text('All colours'), selected: _colorFilter == null, onSelected: (_) => setState(() => _colorFilter = null)),
          for (var i = 0; i < highlightColors.length; i++) ...[
            const SizedBox(width: 8),
            ChoiceChip(
              avatar: CircleAvatar(backgroundColor: highlightColors[i].of(context), radius: 8),
              label: Text(highlightColors[i].name),
              selected: _colorFilter == i,
              onSelected: (_) => setState(() => _colorFilter = _colorFilter == i ? null : i),
            ),
          ],
        ]),
      ),
      Expanded(
        child: list.isEmpty
            ? const EmptyState(
                icon: Icons.border_color_outlined,
                title: 'No highlights',
                message: 'Select verses while reading and pick a colour to highlight them.',
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final g = list![i];
                  return _passageCard(context, ref: g.reference, start: g.start, end: g.end, swatch: highlightColor(g.color).of(context), menu: [
                    for (var c = 0; c < highlightColors.length; c++)
                      if (c != g.color)
                        PopupMenuItem(
                          value: () => services.store.setHighlight([for (var id = g.start; id <= g.end; id++) id], c),
                          child: Text('Change to ${highlightColors[c].name}'),
                        ),
                    PopupMenuItem(value: () => _copy(g.reference, g.start, g.end), child: const Text('Copy')),
                    PopupMenuItem(
                      value: () => services.store.setHighlight([for (var id = g.start; id <= g.end; id++) id], null),
                      child: const Text('Remove highlight'),
                    ),
                  ]);
                },
              ),
      ),
    ]);
  }

  Widget _historyList(BuildContext context) {
    final list = _history;
    if (list == null) return const SizedBox.shrink();
    if (list.isEmpty) {
      return const EmptyState(icon: Icons.history, title: 'No reading history', message: 'Chapters you read will appear here.');
    }
    return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
      Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.only(right: 12),
          child: TextButton(onPressed: () => services.store.clearHistory(), child: const Text('Clear history')),
        ),
      ),
      for (final h in list)
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          leading: const Icon(Icons.menu_book_outlined),
          title: Text('${bookByNumber(h.book).name} ${h.chapter}'),
          subtitle: Text(relativeTime(h.openedAt)),
          onTap: () => openReader(context, Reference(h.book, h.chapter, h.verse > 1 ? h.verse : null)),
        ),
    ]);
  }
}

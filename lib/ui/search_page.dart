import 'dart:async';

import 'package:flutter/material.dart';

import '../core/bible_repository.dart';
import '../core/books.dart';
import '../core/reference.dart';
import '../core/user_store.dart';
import 'common.dart';
import 'note_editor.dart';
import 'theme.dart';

enum SearchScope { bible, notes, saved }

class SearchPage extends StatefulWidget {
  final int? initialBook;
  final SearchScope scope;
  const SearchPage({super.key, this.initialBook, this.scope = SearchScope.bible});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _ctl = TextEditingController();
  late SearchScope _scope = widget.scope;
  bool _exact = false;
  int _testament = 0; // 0 all, 1 OT, 2 NT
  int? _book;
  Timer? _debounce;
  bool _busy = false;
  SearchResults? _bible;
  List<Note>? _notes;
  List<Bookmark>? _bookmarks;
  QueryParse _ref = const QueryParse();
  int _token = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctl.dispose();
    super.dispose();
  }

  void _changed(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), _run);
    setState(() => _ref = parseQuery(_ctl.text, services.bible));
  }

  Future<void> _run() async {
    final q = _ctl.text.trim();
    final token = ++_token;
    if (q.isEmpty) {
      setState(() {
        _bible = null;
        _notes = null;
        _bookmarks = null;
        _busy = false;
      });
      return;
    }
    setState(() => _busy = true);
    try {
      switch (_scope) {
        case SearchScope.bible:
          final r = await services.bible.search(q, exactPhrase: _exact, book: _book, testament: _book == null && _testament > 0 ? _testament : null);
          if (token == _token && mounted) setState(() => _bible = r);
        case SearchScope.notes:
          final r = await services.store.notes(query: q);
          if (token == _token && mounted) setState(() => _notes = r);
        case SearchScope.saved:
          final r = await services.store.bookmarks(query: q);
          if (token == _token && mounted) setState(() => _bookmarks = r);
      }
    } catch (e) {
      if (mounted) toast(context, 'Search could not run: $e');
    } finally {
      if (token == _token && mounted) setState(() => _busy = false);
    }
  }

  List<String> get _terms => searchNormalize(_ctl.text).split(' ').where((t) => t.length > 1).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _ctl,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: _changed,
          onSubmitted: (_) => _run(),
          decoration: InputDecoration(
            hintText: switch (_scope) {
              SearchScope.bible => 'Search words, phrases or a reference',
              SearchScope.notes => 'Search your notes',
              SearchScope.saved => 'Search bookmarks and comments',
            },
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
          ),
        ),
        actions: [
          if (_ctl.text.isNotEmpty)
            IconButton(
              tooltip: 'Clear',
              icon: const Icon(Icons.close),
              onPressed: () {
                _ctl.clear();
                _changed('');
              },
            ),
        ],
      ),
      body: ReadableWidth(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: SegmentedButton<SearchScope>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: SearchScope.bible, label: SegmentLabel('Bible'), icon: Icon(Icons.menu_book_outlined)),
                ButtonSegment(value: SearchScope.notes, label: SegmentLabel('Notes'), icon: Icon(Icons.sticky_note_2_outlined)),
                ButtonSegment(value: SearchScope.saved, label: SegmentLabel('Saved'), icon: Icon(Icons.bookmark_border)),
              ],
              selected: {_scope},
              onSelectionChanged: (s) {
                setState(() => _scope = s.first);
                _run();
              },
            ),
          ),
          if (_scope == SearchScope.bible) _filters(context),
          if (_busy) const LinearProgressIndicator(minHeight: 2) else const SizedBox(height: 2),
          Expanded(child: _results(context)),
        ]),
      ),
    );
  }

  Widget _filters(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
        FilterChip(
          label: const Text('Exact phrase'),
          selected: _exact,
          onSelected: (v) {
            setState(() => _exact = v);
            _run();
          },
        ),
        const SizedBox(width: 8),
        for (final (i, label) in [(0, 'Whole Bible'), (1, 'Old Testament'), (2, 'New Testament')]) ...[
          ChoiceChip(
            label: Text(label),
            selected: _book == null && _testament == i,
            onSelected: (_) {
              setState(() {
                _testament = i;
                _book = null;
              });
              _run();
            },
          ),
          const SizedBox(width: 8),
        ],
        ActionChip(
          avatar: const Icon(Icons.filter_list, size: 18),
          label: Text(_book == null ? 'Book…' : bookByNumber(_book!).name),
          backgroundColor: _book != null ? context.colors.primaryContainer : null,
          onPressed: () async {
            final b = await showModalBottomSheet<int>(
              context: context,
              isScrollControlled: true,
              builder: (context) => DraggableScrollableSheet(
                expand: false,
                initialChildSize: 0.7,
                builder: (context, c) => ListView(controller: c, children: [
                  ListTile(title: const Text('Any book'), onTap: () => Navigator.pop(context, 0)),
                  for (final b in books)
                    if (services.bible.hasBook(b.number))
                      ListTile(title: Text(b.name), onTap: () => Navigator.pop(context, b.number)),
                ]),
              ),
            );
            if (b == null) return;
            setState(() => _book = b == 0 ? null : b);
            _run();
          },
        ),
      ]),
    );
  }

  Widget _results(BuildContext context) {
    final q = _ctl.text.trim();
    if (q.isEmpty) {
      return EmptyState(
        icon: Icons.search,
        title: 'Search offline',
        message: switch (_scope) {
          SearchScope.bible =>
            'Find any word or phrase in the ${services.bible.translation.name}, or type a reference like Romans 8:28.',
          SearchScope.notes => 'Search the titles and contents of your notes.',
          SearchScope.saved => 'Search bookmarked references and your comments.',
        },
      );
    }
    final children = <Widget>[];
    final ref = _ref.reference;
    if (_scope == SearchScope.bible && ref != null) {
      children.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Card(
          color: context.colors.primaryContainer,
          child: ListTile(
            leading: const Icon(Icons.arrow_forward),
            title: Text('Open ${ref.label}', style: const TextStyle(fontWeight: FontWeight.w600)),
            onTap: () => openReader(context, ref),
          ),
        ),
      ));
    }
    switch (_scope) {
      case SearchScope.bible:
        final r = _bible;
        if (r == null) return ListView(children: children);
        final shown = r.verses.length;
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Text(
            r.total == 0
                ? 'No verses found'
                : '${r.total} ${r.total == 1 ? 'verse' : 'verses'}${r.total > shown ? ' · showing the first $shown' : ''}',
            style: context.text.labelLarge?.copyWith(color: context.muted),
          ),
        ));
        if (r.total == 0 && ref == null) {
          children.add(Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
                [
                  _exact ? 'Try turning off “Exact phrase” or searching fewer words.' : 'Check the spelling or try fewer words.',
                  if (services.bible.translation.code == 'web' && RegExp(r'\blord\b', caseSensitive: false).hasMatch(q))
                    'The World English Bible usually renders the divine name as “Yahweh” — for example, “Yahweh is my shepherd”.',
                ].join('\n\n'),
                style: TextStyle(color: context.muted, height: 1.45)),
          ));
        }
        final terms = _terms;
        return ListView.builder(
          itemCount: children.length + r.verses.length,
          itemBuilder: (context, i) {
            if (i < children.length) return children[i];
            final v = r.verses[i - children.length];
            return _VerseResult(verse: v, terms: terms);
          },
        );
      case SearchScope.notes:
        final notes = _notes;
        if (notes == null) return ListView(children: children);
        if (notes.isEmpty) return const EmptyState(icon: Icons.sticky_note_2_outlined, title: 'No matching notes', message: 'Try a different word.');
        return ListView.builder(
          itemCount: notes.length,
          itemBuilder: (context, i) {
            final n = notes[i];
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              title: Text(n.displayTitle, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: _Highlighted(text: _snippet(n.plainBody, q), terms: _terms, maxLines: 3),
              onTap: () => openNote(context, n.id),
            );
          },
        );
      case SearchScope.saved:
        final list = _bookmarks;
        if (list == null) return ListView(children: children);
        if (list.isEmpty) return const EmptyState(icon: Icons.bookmark_border, title: 'Nothing found', message: 'No bookmarks or comments match.');
        return ListView.builder(
          itemCount: list.length,
          itemBuilder: (context, i) {
            final b = list[i];
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              leading: Icon(Icons.bookmark, color: context.colors.secondary),
              title: Text(b.reference.label, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: b.comment.isEmpty ? null : _Highlighted(text: b.comment, terms: _terms, maxLines: 3),
              onTap: () => openReader(context, b.reference),
            );
          },
        );
    }
  }

  String _snippet(String text, String q) {
    final i = text.toLowerCase().indexOf(q.toLowerCase());
    if (i < 0) return text.length > 200 ? text.substring(0, 200) : text;
    final start = (i - 60).clamp(0, text.length);
    final end = (i + q.length + 140).clamp(0, text.length);
    return '${start > 0 ? '…' : ''}${text.substring(start, end).replaceAll('\n', ' ')}${end < text.length ? '…' : ''}';
  }
}

class _VerseResult extends StatelessWidget {
  final Verse verse;
  final List<String> terms;
  const _VerseResult({required this.verse, required this.terms});

  @override
  Widget build(BuildContext context) {
    final ref = Reference.fromIds(verse.id, verse.id);
    return InkWell(
      onTap: () => openReader(context, ref),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(ref.label, style: context.text.labelLarge?.copyWith(color: context.colors.primary, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          _Highlighted(text: verse.text, terms: terms, serif: true),
        ]),
      ),
    );
  }
}

/// Text with every whole-word match of [terms] emphasised.
class _Highlighted extends StatelessWidget {
  final String text;
  final List<String> terms;
  final bool serif;
  final int? maxLines;
  const _Highlighted({required this.text, required this.terms, this.serif = false, this.maxLines});

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(fontFamily: serif ? readingFont : null, height: 1.5, fontSize: serif ? 16 : 14, color: context.colors.onSurface);
    if (terms.isEmpty) return Text(text, style: base, maxLines: maxLines, overflow: maxLines == null ? null : TextOverflow.ellipsis);
    final pattern = RegExp('\\b(${terms.map(RegExp.escape).join('|')})\\b', caseSensitive: false);
    final spans = <TextSpan>[];
    var last = 0;
    for (final m in pattern.allMatches(text)) {
      if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
      spans.add(TextSpan(
        text: m[0],
        style: TextStyle(fontWeight: FontWeight.w700, backgroundColor: highlightColors[0].of(context)),
      ));
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return Text.rich(TextSpan(children: spans, style: base),
        maxLines: maxLines, overflow: maxLines == null ? null : TextOverflow.ellipsis);
  }
}

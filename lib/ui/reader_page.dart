import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/bible_repository.dart';
import '../core/books.dart';
import '../core/reference.dart';
import '../core/user_store.dart';
import 'bible_page.dart';
import 'common.dart';
import 'note_editor.dart';
import 'search_page.dart';
import 'share_card.dart';
import 'theme.dart';

class ReaderPage extends StatefulWidget {
  final int book;
  final int chapter;
  final int? focusStart;
  final int? focusEnd;
  const ReaderPage({super.key, required this.book, required this.chapter, this.focusStart, this.focusEnd});

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  late int _book = widget.book;
  late int _chapter = widget.chapter;
  int? _focusStart, _focusEnd;
  List<Verse>? _verses;
  Map<int, int> _highlights = {};
  Set<int> _bookmarked = {};
  Set<int> _linked = {};
  final Set<int> _selected = {};
  final Map<int, GlobalKey> _keys = {};
  final _scroll = ScrollController();
  bool _immersive = false;
  String? _error;
  Timer? _positionTimer;
  int _loadToken = 0;

  @override
  void initState() {
    super.initState();
    _focusStart = widget.focusStart;
    _focusEnd = widget.focusEnd ?? widget.focusStart;
    services.store.addListener(_refreshMarks);
    services.bibleChanged.addListener(_load);
    services.settings.addListener(_rebuild);
    _load();
  }

  @override
  void dispose() {
    services.store.removeListener(_refreshMarks);
    services.bibleChanged.removeListener(_load);
    services.settings.removeListener(_rebuild);
    _positionTimer?.cancel();
    _scroll.dispose();
    if (_immersive) SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _rebuild() => setState(() {});

  Future<void> _load() async {
    final token = ++_loadToken;
    final bible = services.bible;
    if (!bible.hasBook(_book)) {
      setState(() {
        _verses = const [];
        _error = '${bookByNumber(_book).name} is not included in ${bible.translation.name}.';
      });
      return;
    }
    final max = bible.chapterCount(_book);
    if (_chapter > max) _chapter = max;
    final verses = await bible.chapter(_book, _chapter);
    if (!mounted || token != _loadToken) return;
    _keys.clear();
    setState(() {
      _verses = verses;
      _error = null;
    });
    await _refreshMarks();
    final focusVerse = _focusStart != null ? verseOf(_focusStart!) : 1;
    services.store.recordReading(_book, _chapter, focusVerse);
    services.settings.lastPosition = verseId(_book, _chapter, focusVerse);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToFocus());
  }

  Future<void> _refreshMarks() async {
    final lo = verseId(_book, _chapter, 0), hi = verseId(_book, _chapter, 999);
    final store = services.store;
    final results = await Future.wait([store.highlightsIn(lo, hi), store.bookmarksIn(lo, hi), store.linkedVerses(lo, hi)]);
    if (!mounted) return;
    final bookmarks = results[1] as List<Bookmark>;
    setState(() {
      _highlights = results[0] as Map<int, int>;
      _bookmarked = {
        for (final b in bookmarks)
          for (var id = b.startId < lo ? lo : b.startId; id <= b.endId && id <= hi; id++) id
      };
      _linked = results[2] as Set<int>;
    });
  }

  void _scrollToFocus() {
    if (_focusStart == null) {
      if (_scroll.hasClients) _scroll.jumpTo(0);
      return;
    }
    final ctx = _keys[_focusStart]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx, alignment: 0.08, duration: const Duration(milliseconds: 250), curve: Curves.easeOutCubic);
    }
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _focusStart = _focusEnd = null);
    });
  }

  void _goTo(int book, int chapter, {int? verse}) {
    setState(() {
      _book = book;
      _chapter = chapter;
      _selected.clear();
      _focusStart = verse == null ? null : verseId(book, chapter, verse);
      _focusEnd = _focusStart;
      _verses = null;
    });
    _load();
  }

  (int, int)? get _prev {
    if (_chapter > 1) return (_book, _chapter - 1);
    for (var b = _book - 1; b >= 1; b--) {
      if (services.bible.hasBook(b)) return (b, services.bible.chapterCount(b));
    }
    return null;
  }

  (int, int)? get _next {
    if (_chapter < services.bible.chapterCount(_book)) return (_book, _chapter + 1);
    for (var b = _book + 1; b <= 66; b++) {
      if (services.bible.hasBook(b)) return (b, 1);
    }
    return null;
  }

  void _onScrollEnd() {
    _positionTimer?.cancel();
    _positionTimer = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      final top = MediaQuery.paddingOf(context).top + kToolbarHeight;
      for (final e in _keys.entries) {
        final box = e.value.currentContext?.findRenderObject() as RenderBox?;
        if (box == null || !box.attached) continue;
        final y = box.localToGlobal(Offset.zero).dy;
        if (y + box.size.height > top + 8) {
          services.settings.lastPosition = e.key;
          services.store.recordReading(_book, _chapter, verseOf(e.key));
          break;
        }
      }
    });
  }

  void _toggleImmersive() {
    setState(() => _immersive = !_immersive);
    SystemChrome.setEnabledSystemUIMode(_immersive ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
  }

  Reference get _selectionRef {
    final ids = _selected.toList()..sort();
    return Reference.fromIds(ids.first, ids.last);
  }

  List<Verse> get _selectedVerses => [for (final v in _verses ?? const <Verse>[]) if (_selected.contains(v.id)) v];

  String get _selectionText {
    final runs = contiguousRuns(_selected);
    final abbr = services.bible.translation.abbreviation;
    final vs = _selectedVerses;
    return runs.map((r) {
      final part = vs.where((v) => v.id >= r.$1 && v.id <= r.$2).toList();
      return passageForSharing(part, Reference.fromIds(r.$1, r.$2), abbr);
    }).join('\n\n');
  }

  Future<void> _highlight(int? color) async {
    await services.store.setHighlight(_selected, color);
    setState(_selected.clear);
  }

  Future<void> _bookmark() async {
    final runs = contiguousRuns(_selected);
    final allMarked = _selected.every(_bookmarked.contains);
    if (allMarked) {
      final lo = verseId(_book, _chapter, 0), hi = verseId(_book, _chapter, 999);
      for (final b in await services.store.bookmarksIn(lo, hi)) {
        if (_selected.any((id) => id >= b.startId && id <= b.endId)) await services.store.deleteBookmark(b.id);
      }
      if (mounted) toast(context, 'Bookmark removed');
    } else {
      Bookmark? last;
      for (final r in runs) {
        last = await services.store.addBookmark(r.$1, r.$2);
      }
      if (mounted && last != null) {
        final b = last;
        toast(context, 'Bookmarked ${b.reference.label}',
            action: SnackBarAction(label: 'Add comment', onPressed: () => editBookmarkComment(context, b)));
      }
    }
    setState(_selected.clear);
  }

  Future<void> _addToNote() async {
    final ref = _selectionRef;
    final text = passagePlain(_selectedVerses);
    setState(_selected.clear);
    await addPassageToNote(context, ref, text);
  }

  Future<void> _showCrossRefs(int id) async {
    final refs = await services.bible.crossReferences(id);
    if (!mounted) return;
    setState(_selected.clear);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => CrossReferenceSheet(source: Reference.fromIds(id, id), refs: refs),
    );
  }

  Future<void> _showLinkedNotes(int id) async {
    final notes = await services.store.notesForRange(id, id);
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: ScrollColumn(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text('Notes on ${Reference.fromIds(id, id).label}', style: context.text.titleLarge),
          ),
          for (final n in notes)
            ListTile(
              leading: const Icon(Icons.sticky_note_2_outlined),
              title: Text(n.displayTitle),
              subtitle: Text('${n.kind.label} · edited ${relativeTime(n.updatedAt)}'),
              onTap: () {
                Navigator.pop(context);
                openNote(context, n.id);
              },
            ),
          const SizedBox(height: 12),
        ]),
      ),
    );
  }

  Future<void> _pickPassage() async {
    final r = await showPassagePicker(context, initialBook: _book);
    if (r != null) _goTo(r.book, r.chapter, verse: r.verse);
  }

  @override
  Widget build(BuildContext context) {
    final book = bookByNumber(_book);
    final settings = services.settings;
    final selecting = _selected.isNotEmpty;
    return PopScope(
      canPop: !selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && selecting) setState(_selected.clear);
      },
      child: Scaffold(
        appBar: _immersive
            ? null
            : AppBar(
                titleSpacing: 0,
                title: Semantics(
                  button: true,
                  label: 'Choose book and chapter. Current: ${book.name} $_chapter',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: _pickPassage,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Flexible(child: Text(Reference(_book, _chapter).label, overflow: TextOverflow.ellipsis)),
                        const Icon(Icons.expand_more, size: 22),
                      ]),
                    ),
                  ),
                ),
                actions: [
                  const TranslationChip(),
                  IconButton(
                    tooltip: 'Search the Bible',
                    icon: const Icon(Icons.search),
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SearchPage(initialBook: _book))),
                  ),
                  IconButton(
                    tooltip: 'Text settings',
                    icon: const Icon(Icons.text_fields),
                    onPressed: () => showReadingSettings(context),
                  ),
                  IconButton(tooltip: 'Focus mode', icon: const Icon(Icons.fullscreen), onPressed: _toggleImmersive),
                ],
              ),
        body: Stack(children: [
          GestureDetector(
            onHorizontalDragEnd: (d) {
              final v = d.primaryVelocity ?? 0;
              if (v < -500 && _next != null) _goTo(_next!.$1, _next!.$2);
              if (v > 500 && _prev != null) _goTo(_prev!.$1, _prev!.$2);
            },
            child: _buildBody(context, settings.fontSize, settings.lineHeight),
          ),
          if (_immersive)
            Positioned(
              top: MediaQuery.paddingOf(context).top + 8,
              right: 8,
              child: IconButton.filledTonal(
                tooltip: 'Exit focus mode',
                icon: const Icon(Icons.fullscreen_exit),
                onPressed: _toggleImmersive,
              ),
            ),
        ]),
        bottomNavigationBar: selecting ? _selectionBar(context) : (_immersive ? null : _chapterBar(context)),
      ),
    );
  }

  Widget _buildBody(BuildContext context, double fontSize, double lineHeight) {
    final verses = _verses;
    if (verses == null) return const SizedBox.shrink();
    if (_error != null) return EmptyState(icon: Icons.menu_book_outlined, title: 'Not available', message: _error!);
    final book = bookByNumber(_book);
    final showNumbers = services.settings.verseNumbers;
    return NotificationListener<ScrollEndNotification>(
      onNotification: (_) {
        _onScrollEnd();
        return false;
      },
      child: Scrollbar(
        controller: _scroll,
        child: SingleChildScrollView(
          controller: _scroll,
          padding: EdgeInsets.fromLTRB(0, _immersive ? MediaQuery.paddingOf(context).top + 24 : 8, 0, 48),
          child: ReadableWidth(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const SizedBox(height: 12),
                Semantics(
                  header: true,
                  child: Column(children: [
                    Text(book.name.toUpperCase(),
                        textAlign: TextAlign.center,
                        style: context.text.labelMedium?.copyWith(letterSpacing: 2.4, color: context.muted)),
                    const SizedBox(height: 4),
                    Text('$_chapter',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontFamily: readingFont, fontSize: 44, fontWeight: FontWeight.w500, color: context.colors.primary)),
                  ]),
                ),
                const SizedBox(height: 16),
                for (final v in verses) _verseTile(context, v, fontSize, lineHeight, showNumbers),
                const SizedBox(height: 24),
                Text('${services.bible.translation.name} (${services.bible.translation.abbreviation})',
                    textAlign: TextAlign.center, style: context.text.labelSmall?.copyWith(color: context.muted)),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _verseTile(BuildContext context, Verse v, double fontSize, double lineHeight, bool showNumbers) {
    final key = _keys.putIfAbsent(v.id, GlobalKey.new);
    final hl = _highlights[v.id];
    final selected = _selected.contains(v.id);
    final focused = _focusStart != null && v.id >= _focusStart! && v.id <= (_focusEnd ?? _focusStart!);
    final colors = context.colors;
    Color? bg;
    if (hl != null) bg = highlightColor(hl).of(context);
    if (focused && hl == null) bg = colors.primaryContainer.withValues(alpha: 0.55);
    final textColor = colors.onSurface;
    return Semantics(
      key: key,
      selected: selected,
      button: true,
      label: 'Verse ${v.number}${hl != null ? ', highlighted' : ''}${_bookmarked.contains(v.id) ? ', bookmarked' : ''}',
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => setState(() => selected ? _selected.remove(v.id) : _selected.add(v.id)),
        onLongPress: () => setState(() => _selected.add(v.id)),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
            border: Border(bottom: BorderSide(color: selected ? colors.primary : Colors.transparent, width: 2)),
          ),
          child: Text.rich(
            TextSpan(children: [
              if (showNumbers)
                TextSpan(
                  text: '${v.number}  ',
                  style: TextStyle(fontSize: fontSize * 0.62, fontWeight: FontWeight.w700, color: colors.primary, fontFamily: null),
                ),
              TextSpan(text: v.text),
              if (_bookmarked.contains(v.id))
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Icon(Icons.bookmark, size: fontSize * 0.85, color: colors.secondary, semanticLabel: 'Bookmarked'),
                  ),
                ),
              if (_linked.contains(v.id))
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: InkWell(
                    onTap: () => _showLinkedNotes(v.id),
                    customBorder: const CircleBorder(),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(6, 2, 2, 2),
                      child: Icon(Icons.sticky_note_2_outlined, size: fontSize * 0.85, color: colors.primary, semanticLabel: 'Open linked notes'),
                    ),
                  ),
                ),
            ]),
            style: TextStyle(fontFamily: readingFont, fontSize: fontSize, height: lineHeight, color: textColor),
          ),
        ),
      ),
    );
  }

  Widget _chapterBar(BuildContext context) {
    final prev = _prev, next = _next;
    String label((int, int) c) => '${bookByNumber(c.$1).short} ${c.$2}';
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(border: Border(top: BorderSide(color: context.colors.outlineVariant))),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(children: [
          TextButton.icon(
            onPressed: prev == null ? null : () => _goTo(prev.$1, prev.$2),
            icon: const Icon(Icons.chevron_left),
            label: Text(prev == null ? 'Previous' : label(prev)),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: next == null ? null : () => _goTo(next.$1, next.$2),
            iconAlignment: IconAlignment.end,
            icon: const Icon(Icons.chevron_right),
            label: Text(next == null ? 'Next' : label(next)),
          ),
        ]),
      ),
    );
  }

  Widget _selectionBar(BuildContext context) {
    final ref = _selectionRef;
    final single = _selected.length == 1;
    final colors = context.colors;
    Widget action(IconData icon, String label, VoidCallback onTap) => Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 22),
                const SizedBox(height: 4),
                Text(label, style: context.text.labelSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
          ),
        );
    final allMarked = _selected.every(_bookmarked.contains);
    return SafeArea(
      top: false,
      child: Material(
        color: colors.surfaceContainerHigh,
        elevation: 8,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Expanded(
                child: Text(contiguousRuns(_selected).length > 1 ? '${_selected.length} verses selected' : ref.label,
                    style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              ),
              for (var i = 0; i < highlightColors.length; i++)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Semantics(
                    button: true,
                    label: 'Highlight ${highlightColors[i].name}',
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => _highlight(i),
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: highlightColors[i].of(context),
                          shape: BoxShape.circle,
                          border: Border.all(color: colors.outline.withValues(alpha: 0.4)),
                        ),
                      ),
                    ),
                  ),
                ),
              if (_selected.any(_highlights.containsKey))
                IconButton(
                  tooltip: 'Remove highlight',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.format_color_reset_outlined),
                  onPressed: () => _highlight(null),
                ),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              action(allMarked ? Icons.bookmark_remove_outlined : Icons.bookmark_add_outlined, allMarked ? 'Unmark' : 'Bookmark', _bookmark),
              action(Icons.copy_rounded, 'Copy', () {
                copyToClipboard(context, _selectionText);
                setState(_selected.clear);
              }),
              action(Icons.ios_share, 'Share', () {
                shareText(context, _selectionText);
                setState(_selected.clear);
              }),
              action(Icons.note_add_outlined, 'To note', _addToNote),
              if (single) action(Icons.alt_route, 'Related', () => _showCrossRefs(_selected.first)),
              if (single)
                action(Icons.image_outlined, 'Image', () {
                  final v = _selectedVerses.first;
                  setState(_selected.clear);
                  showShareCard(context, Reference.fromIds(v.id, v.id), v.text);
                }),
              action(Icons.close, 'Clear', () => setState(_selected.clear)),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// Lets the user attach a passage to an existing note or a new one.
Future<void> addPassageToNote(BuildContext context, Reference ref, String text) async {
  final notes = await services.store.notes(limit: 30);
  if (!context.mounted) return;
  final choice = await showModalBottomSheet<Object>(
    context: context,
    isScrollControlled: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (context, controller) => ListView(controller: controller, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
          child: Text('Add ${ref.label} to a note', style: context.text.titleLarge),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
          child: Text('The reference and its text are added at the end of the note.',
              style: context.text.bodySmall?.copyWith(color: context.muted)),
        ),
        ListTile(
          leading: CircleAvatar(backgroundColor: context.colors.primaryContainer, child: const Icon(Icons.add)),
          title: const Text('New note'),
          onTap: () => Navigator.pop(context, 'new'),
        ),
        for (final n in notes)
          ListTile(
            leading: const Icon(Icons.sticky_note_2_outlined),
            title: Text(n.displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${n.kind.label} · ${relativeTime(n.updatedAt)}'),
            onTap: () => Navigator.pop(context, n),
          ),
      ]),
    ),
  );
  if (choice == null || !context.mounted) return;
  final block = '${ref.label}\n> $text';
  Note note;
  if (choice is Note) {
    final fresh = await services.store.note(choice.id) ?? choice;
    final body = fresh.body.trimRight();
    await services.store.saveNote(fresh.id, title: fresh.title, subtitle: fresh.subtitle, body: body.isEmpty ? block : '$body\n\n$block\n');
    note = fresh;
  } else {
    note = await services.store.createNote(title: ref.label, body: '$block\n\n', kind: NoteKind.study);
  }
  if (context.mounted) {
    toast(context, 'Added to “${choice is Note ? note.displayTitle : ref.label}”',
        action: SnackBarAction(label: 'Open', onPressed: () => openNote(context, note.id)));
  }
}

Future<void> editBookmarkComment(BuildContext context, Bookmark b) async {
  final ctl = TextEditingController(text: b.comment);
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(b.reference.label),
      content: TextField(
        controller: ctl,
        autofocus: true,
        maxLines: 4,
        minLines: 2,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(hintText: 'Add a personal comment'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, ctl.text.trim()), child: const Text('Save')),
      ],
    ),
  );
  if (result != null) await services.store.updateBookmarkComment(b.id, result);
}

class CrossReferenceSheet extends StatefulWidget {
  final Reference source;
  final List<CrossReference> refs;
  const CrossReferenceSheet({super.key, required this.source, required this.refs});

  @override
  State<CrossReferenceSheet> createState() => _CrossReferenceSheetState();
}

class _CrossReferenceSheetState extends State<CrossReferenceSheet> {
  final Map<int, String> _texts = {};

  @override
  void initState() {
    super.initState();
    _loadTexts();
  }

  Future<void> _loadTexts() async {
    for (final r in widget.refs) {
      final vs = await services.bible.range(r.start, r.end);
      if (!mounted) return;
      setState(() => _texts[r.start * 7 + r.end] = passagePlain(vs));
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.65,
      maxChildSize: 0.92,
      builder: (context, controller) => ListView(controller: controller, padding: const EdgeInsets.only(bottom: 24), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
          child: Text('Related to ${widget.source.label}', style: context.text.titleLarge),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
          child: Text('Cross references from OpenBible.info (CC BY), most supported first.',
              style: context.text.bodySmall?.copyWith(color: context.muted)),
        ),
        if (widget.refs.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('No cross references are available for this verse.'),
          ),
        for (final r in widget.refs)
          ListTile(
            title: Text(r.reference.label, style: TextStyle(fontWeight: FontWeight.w700, color: context.colors.primary)),
            subtitle: Text(_texts[r.start * 7 + r.end] ?? '',
                maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: readingFont, height: 1.45)),
            onTap: () {
              Navigator.pop(context);
              openReader(context, r.reference);
            },
          ),
      ]),
    );
  }
}

Future<void> showReadingSettings(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    builder: (context) => ListenableBuilder(
      listenable: services.settings,
      builder: (context, _) {
        final s = services.settings;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: ScrollColumn(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Reading', style: context.text.titleLarge),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: context.colors.surface, borderRadius: BorderRadius.circular(14)),
                child: Text('In the beginning, God created the heavens and the earth.',
                    style: TextStyle(fontFamily: readingFont, fontSize: s.fontSize, height: s.lineHeight)),
              ),
              const SizedBox(height: 8),
              Row(children: [
                const Icon(Icons.text_decrease, size: 20),
                Expanded(
                  child: Slider(
                    value: s.fontSize,
                    min: 14,
                    max: 32,
                    divisions: 18,
                    label: '${s.fontSize.round()}',
                    semanticFormatterCallback: (v) => 'Text size ${v.round()}',
                    onChanged: (v) => s.fontSize = v,
                  ),
                ),
                const Icon(Icons.text_increase, size: 20),
              ]),
              Row(children: [
                const Icon(Icons.density_small, size: 20),
                Expanded(
                  child: Slider(
                    value: s.lineHeight,
                    min: 1.2,
                    max: 2.2,
                    divisions: 10,
                    label: s.lineHeight.toStringAsFixed(1),
                    semanticFormatterCallback: (v) => 'Line spacing ${v.toStringAsFixed(1)}',
                    onChanged: (v) => s.lineHeight = v,
                  ),
                ),
                const Icon(Icons.density_large, size: 20),
              ]),
              const SizedBox(height: 8),
              SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(value: ThemeMode.light, label: SegmentLabel('Light'), icon: Icon(Icons.light_mode_outlined)),
                  ButtonSegment(value: ThemeMode.dark, label: SegmentLabel('Dark'), icon: Icon(Icons.dark_mode_outlined)),
                  ButtonSegment(value: ThemeMode.system, label: SegmentLabel('Auto'), icon: Icon(Icons.brightness_auto_outlined)),
                ],
                selected: {s.themeMode},
                onSelectionChanged: (v) => s.themeMode = v.first,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Verse numbers'),
                value: s.verseNumbers,
                onChanged: (v) => s.verseNumbers = v,
              ),
            ]),
          ),
        );
      },
    ),
  );
}

import 'package:flutter/material.dart';

import '../core/books.dart';
import '../core/reference.dart';
import 'common.dart';
import 'search_page.dart';
import 'theme.dart';

class BiblePage extends StatelessWidget {
  const BiblePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bible'),
        actions: [
          const TranslationChip(),
          IconButton(
            tooltip: 'Search the Bible',
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchPage())),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ReadableWidth(
        child: BookChapterBrowser(
          header: const Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(padding: EdgeInsets.fromLTRB(16, 4, 16, 0), child: GoToField()),
            _ContinueCard(),
          ]),
          onChapter: (b, c) => openReader(context, Reference(b, c)),
        ),
      ),
    );
  }
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: services.store,
      builder: (context, _) {
        final last = services.settings.lastPosition;
        if (last == null) return const SizedBox(height: 8);
        final ref = Reference(bookOf(last), chapterOf(last), verseOf(last));
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: Icon(Icons.auto_stories_outlined, color: context.colors.primary),
              title: const Text('Continue reading'),
              subtitle: Text(ref.label),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => openReader(context, ref),
            ),
          ),
        );
      },
    );
  }
}

/// A "go to" box that understands typed references such as "jn 3:16" or "1 cor 13".
class GoToField extends StatefulWidget {
  final ValueChanged<Reference>? onOpen;
  final bool autofocus;
  const GoToField({super.key, this.onOpen, this.autofocus = false});

  @override
  State<GoToField> createState() => _GoToFieldState();
}

class _GoToFieldState extends State<GoToField> {
  final _ctl = TextEditingController();
  QueryParse _parse = const QueryParse();

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _open(Reference r) {
    FocusScope.of(context).unfocus();
    _ctl.clear();
    setState(() => _parse = const QueryParse());
    if (widget.onOpen != null) {
      widget.onOpen!(r);
    } else {
      openReader(context, r);
    }
  }

  void _submit() {
    final p = _parse;
    if (p.reference != null) {
      _open(p.reference!);
    } else if (p.book != null && p.error == null) {
      _open(Reference(p.book!.number, 1));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _parse;
    final suggestions = p.reference == null && p.book == null ? suggestBooks(_ctl.text).take(6).toList() : const [];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        controller: _ctl,
        autofocus: widget.autofocus,
        textInputAction: TextInputAction.go,
        decoration: InputDecoration(
          hintText: 'Go to a passage, e.g. John 3:16',
          prefixIcon: const Icon(Icons.travel_explore),
          suffixIcon: _ctl.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear',
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() {
                    _ctl.clear();
                    _parse = const QueryParse();
                  }),
                ),
        ),
        onChanged: (s) => setState(() => _parse = parseQuery(s, services.bible)),
        onSubmitted: (_) => _submit(),
      ),
      if (p.reference != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: FilledButton.tonalIcon(
            style: FilledButton.styleFrom(alignment: Alignment.centerLeft, padding: const EdgeInsets.all(14)),
            onPressed: () => _open(p.reference!),
            icon: const Icon(Icons.arrow_forward),
            label: Text('Open ${p.reference!.label}'),
          ),
        )
      else if (p.error != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
          child: Text(p.error!, style: TextStyle(color: context.colors.error)),
        )
      else if (p.book != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: FilledButton.tonalIcon(
            style: FilledButton.styleFrom(alignment: Alignment.centerLeft, padding: const EdgeInsets.all(14)),
            onPressed: () => _open(Reference(p.book!.number, 1)),
            icon: const Icon(Icons.arrow_forward),
            label: Text('Open ${p.book!.name} 1'),
          ),
        )
      else if (suggestions.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Wrap(spacing: 8, runSpacing: 4, children: [
            for (final b in suggestions)
              ActionChip(
                label: Text(b.name),
                onPressed: () {
                  _ctl.text = '${b.name} ';
                  _ctl.selection = TextSelection.collapsed(offset: _ctl.text.length);
                  setState(() => _parse = parseQuery(_ctl.text, services.bible));
                },
              ),
          ]),
        ),
    ]);
  }
}

/// Testament switcher with books that expand into chapter grids.
class BookChapterBrowser extends StatefulWidget {
  final void Function(int book, int chapter) onChapter;
  final Widget? header;
  final int? initialBook;
  final ScrollController? controller;
  const BookChapterBrowser({super.key, required this.onChapter, this.header, this.initialBook, this.controller});

  @override
  State<BookChapterBrowser> createState() => _BookChapterBrowserState();
}

class _BookChapterBrowserState extends State<BookChapterBrowser> {
  late bool _newTestament = (widget.initialBook ?? 1) >= 40;
  late int? _expanded = widget.initialBook;

  @override
  Widget build(BuildContext context) {
    final list = books.where((b) => b.isOldTestament != _newTestament && services.bible.hasBook(b.number)).toList();
    return ListView.builder(
      controller: widget.controller,
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: list.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ?widget.header,
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: SegmentLabel('Old Testament')),
                  ButtonSegment(value: true, label: SegmentLabel('New Testament')),
                ],
                selected: {_newTestament},
                showSelectedIcon: false,
                onSelectionChanged: (v) => setState(() {
                  _newTestament = v.first;
                  _expanded = null;
                }),
              ),
            ),
          ]);
        }
        final b = list[i - 1];
        final open = _expanded == b.number;
        final chapters = services.bible.chapterCount(b.number);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 24),
            title: Text(b.name,
                style: TextStyle(fontFamily: readingFont, fontSize: 18, fontWeight: open ? FontWeight.w700 : FontWeight.w500)),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Text('$chapters', style: context.text.bodySmall?.copyWith(color: context.muted)),
              const SizedBox(width: 6),
              AnimatedRotation(turns: open ? 0.5 : 0, duration: const Duration(milliseconds: 200), child: const Icon(Icons.expand_more)),
            ]),
            onTap: () {
              if (chapters == 1) {
                widget.onChapter(b.number, 1);
              } else {
                setState(() => _expanded = open ? null : b.number);
              }
            },
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            child: open
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: LayoutBuilder(builder: (context, c) {
                      final cols = (c.maxWidth / 56).floor().clamp(5, 12);
                      final size = (c.maxWidth - (cols - 1) * 8) / cols;
                      return Wrap(spacing: 8, runSpacing: 8, children: [
                        for (var ch = 1; ch <= chapters; ch++)
                          Semantics(
                            button: true,
                            label: '${b.name} chapter $ch',
                            excludeSemantics: true,
                            child: SizedBox(
                              width: size,
                              height: 44,
                              child: Material(
                                color: context.colors.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(10),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(10),
                                  onTap: () => widget.onChapter(b.number, ch),
                                  child: Center(child: Text('$ch', style: context.text.titleSmall)),
                                ),
                              ),
                            ),
                          ),
                      ]);
                    }),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ]);
      },
    );
  }
}

/// Bottom-sheet picker for book → chapter → (optional) verse.
Future<Reference?> showPassagePicker(BuildContext context, {int? initialBook}) {
  return showModalBottomSheet<Reference>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, controller) => _PickerBody(controller: controller, initialBook: initialBook),
    ),
  );
}

class _PickerBody extends StatefulWidget {
  final ScrollController controller;
  final int? initialBook;
  const _PickerBody({required this.controller, this.initialBook});

  @override
  State<_PickerBody> createState() => _PickerBodyState();
}

class _PickerBodyState extends State<_PickerBody> {
  (int, int)? _chapter;
  bool _pickVerse = false;

  @override
  Widget build(BuildContext context) {
    final ch = _chapter;
    if (ch != null) {
      final count = services.bible.maxVerse(ch.$1, ch.$2) ?? 0;
      return ListView(controller: widget.controller, padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), children: [
        Row(children: [
          IconButton(tooltip: 'Back to chapters', icon: const Icon(Icons.arrow_back), onPressed: () => setState(() => _chapter = null)),
          Expanded(child: Text('${bookByNumber(ch.$1).name} ${ch.$2}', style: context.text.titleLarge)),
          TextButton(
            onPressed: () => Navigator.pop(context, Reference(ch.$1, ch.$2)),
            child: const Text('Whole chapter'),
          ),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (var v = 1; v <= count; v++)
            if (services.bible.maxVerse(ch.$1, ch.$2) != null)
              SizedBox(
                width: 52,
                height: 44,
                child: Material(
                  color: context.colors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => Navigator.pop(context, Reference(ch.$1, ch.$2, v)),
                    child: Center(child: Text('$v', semanticsLabel: 'Verse $v')),
                  ),
                ),
              ),
        ]),
      ]);
    }
    return BookChapterBrowser(
      controller: widget.controller,
      initialBook: widget.initialBook,
      header: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          GoToField(onOpen: (r) => Navigator.pop(context, r)),
          SwitchListTile(
            contentPadding: const EdgeInsets.only(left: 4, right: 8),
            dense: true,
            title: const Text('Choose a verse after the chapter'),
            value: _pickVerse,
            onChanged: (v) => setState(() => _pickVerse = v),
          ),
        ]),
      ),
      onChapter: (b, c) {
        if (_pickVerse) {
          setState(() => _chapter = (b, c));
        } else {
          Navigator.pop(context, Reference(b, c));
        }
      },
    );
  }
}

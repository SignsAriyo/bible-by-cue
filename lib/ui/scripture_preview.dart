import 'package:flutter/material.dart';

import '../core/bible_repository.dart';
import '../core/books.dart';
import '../core/reference.dart';
import 'common.dart';
import 'theme.dart';

/// A large reading panel anchored to the top of the screen. The tapped reference and its
/// text are always the first content; the panel never opens before the text is loaded.
class ScripturePreviewSheet extends StatefulWidget {
  final Reference reference;
  final List<Verse> verses;
  final int index;
  final int count;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onEditReference;
  final VoidCallback onClosed;

  const ScripturePreviewSheet({
    super.key,
    required this.reference,
    required this.verses,
    required this.onClosed,
    this.index = 0,
    this.count = 1,
    this.onPrevious,
    this.onNext,
    this.onEditReference,
  });

  @override
  State<ScripturePreviewSheet> createState() => ScripturePreviewSheetState();
}

class ScripturePreviewSheetState extends State<ScripturePreviewSheet> with SingleTickerProviderStateMixin {
  late final AnimationController _show =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 260), reverseDuration: const Duration(milliseconds: 200))
        ..forward();
  double _drag = 0;
  bool _closing = false;
  bool _bookmarked = false;
  bool _pickColor = false;
  List<Verse>? _context;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadBookmark();
  }

  @override
  void didUpdateWidget(ScripturePreviewSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reference != widget.reference) {
      _context = null;
      _pickColor = false;
      if (_scroll.hasClients) _scroll.jumpTo(0);
      _loadBookmark();
    }
  }

  @override
  void dispose() {
    _show.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadBookmark() async {
    final r = widget.reference;
    final list = await services.store.bookmarksIn(r.startId, r.endId);
    final ids = widget.verses.map((v) => v.id).toList();
    if (!mounted || ids.isEmpty) return;
    setState(() => _bookmarked = list.any((b) => b.startId == ids.first && b.endId == ids.last));
  }

  /// Animates the sheet away, then reports that it closed.
  Future<void> dismiss() async {
    if (_closing) return;
    _closing = true;
    await _show.reverse();
    widget.onClosed();
  }

  String get _shareText => passageForSharing(widget.verses, widget.reference, services.bible.translation.abbreviation);

  Future<void> _toggleBookmark() async {
    final ids = widget.verses.map((v) => v.id).toList();
    if (ids.isEmpty) return;
    if (_bookmarked) {
      for (final b in await services.store.bookmarksIn(ids.first, ids.last)) {
        if (b.startId == ids.first && b.endId == ids.last) await services.store.deleteBookmark(b.id);
      }
    } else {
      await services.store.addBookmark(ids.first, ids.last);
    }
    setState(() => _bookmarked = !_bookmarked);
    if (mounted) toast(context, _bookmarked ? 'Bookmarked ${widget.reference.label}' : 'Bookmark removed');
  }

  Future<void> _highlight(int? color) async {
    await services.store.setHighlight(widget.verses.map((v) => v.id), color);
    setState(() => _pickColor = false);
    if (mounted) toast(context, color == null ? 'Highlight removed' : 'Highlighted ${widget.reference.label}');
  }

  Future<void> _showContext() async {
    final r = widget.reference;
    final last = widget.verses.isEmpty ? r.endId : widget.verses.last.id;
    final rest = await services.bible.range(last + 1, verseId(bookOf(last), chapterOf(last), 999));
    if (mounted) setState(() => _context = rest);
  }

  void _dragUpdate(DragUpdateDetails d) => setState(() => _drag = (_drag + d.delta.dy).clamp(-2000.0, 0.0));

  void _dragEnd(DragEndDetails d, double height) {
    if (_drag < -height * 0.18 || (d.primaryVelocity ?? 0) < -700) {
      dismiss();
    } else {
      setState(() => _drag = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final available = mq.size.height - mq.padding.top - mq.viewInsets.bottom;
    // About 72% of the usable height, adapting to small displays while leaving the note visible.
    final height = (available * 0.72).clamp(available < 520 ? available * 0.6 : 300.0, available - 88).toDouble();
    final colors = context.colors;
    final curved = CurvedAnimation(parent: _show, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, -1.05), end: Offset.zero).animate(curved),
        child: AnimatedContainer(
          duration: _drag == 0 ? const Duration(milliseconds: 180) : Duration.zero,
          transform: Matrix4.translationValues(0, _drag, 0),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Semantics(
                container: true,
                namesRoute: true,
                explicitChildNodes: true,
                label: 'Scripture preview',
                child: Material(
                  color: colors.surfaceContainerLow,
                  elevation: 14,
                  shadowColor: Colors.black54,
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: EdgeInsets.only(top: mq.padding.top),
                    child: SizedBox(
                      height: height,
                      child: Column(children: [
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onVerticalDragUpdate: _dragUpdate,
                          onVerticalDragEnd: (d) => _dragEnd(d, height),
                          child: _header(context),
                        ),
                        Expanded(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 160),
                            child: KeyedSubtree(key: ValueKey(widget.reference), child: _body(context)),
                          ),
                        ),
                        _actions(context),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onVerticalDragUpdate: _dragUpdate,
                          onVerticalDragEnd: (d) => _dragEnd(d, height),
                          child: Semantics(
                            label: 'Swipe up to close',
                            child: SizedBox(
                              height: 22,
                              width: double.infinity,
                              child: Center(
                                child: Container(
                                  width: 40,
                                  height: 4,
                                  decoration: BoxDecoration(color: colors.outline.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(2)),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final t = services.bible.translation;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 6, 0),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            child: Column(
              key: ValueKey(widget.reference),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(widget.reference.label,
                      style: context.text.titleLarge?.copyWith(color: context.colors.primary, fontSize: 22)),
                ),
                Text(t.name, style: context.text.labelSmall?.copyWith(color: context.muted, letterSpacing: 0.4)),
              ],
            ),
          ),
        ),
        if (widget.count > 1) ...[
          IconButton(
            tooltip: 'Previous reference in this note',
            visualDensity: VisualDensity.compact,
            onPressed: widget.onPrevious,
            icon: const Icon(Icons.chevron_left),
          ),
          Text('${widget.index + 1}/${widget.count}', style: context.text.labelMedium?.copyWith(color: context.muted)),
          IconButton(
            tooltip: 'Next reference in this note',
            visualDensity: VisualDensity.compact,
            onPressed: widget.onNext,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
        IconButton(tooltip: 'Close preview', icon: const Icon(Icons.close), onPressed: dismiss),
      ]),
    );
  }

  Widget _body(BuildContext context) {
    final s = services.settings;
    final style = TextStyle(fontFamily: readingFont, fontSize: s.fontSize + 1, height: s.lineHeight, color: context.colors.onSurface);
    final numbered = widget.verses.length > 1;
    TextSpan verseSpan(Verse v, bool withNumber, {Color? color}) => TextSpan(children: [
          if (withNumber)
            TextSpan(
              text: '${v.number} ',
              style: TextStyle(fontSize: style.fontSize! * 0.62, fontWeight: FontWeight.w700, color: context.colors.primary, fontFamily: null),
            ),
          TextSpan(text: '${v.text} ', style: color == null ? null : TextStyle(color: color)),
        ]);
    return Scrollbar(
      controller: _scroll,
      child: ListView(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
        children: [
          SelectableText.rich(
            TextSpan(style: style, children: [for (final v in widget.verses) verseSpan(v, numbered)]),
          ),
          if (_context == null && !widget.reference.isWholeChapter)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _showContext,
                icon: const Icon(Icons.unfold_more),
                label: const Text('Continue reading this chapter'),
              ),
            ),
          if (_context != null && _context!.isNotEmpty) ...[
            const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Divider()),
            Text.rich(TextSpan(style: style, children: [for (final v in _context!) verseSpan(v, true, color: context.muted)])),
          ],
          if (widget.onEditReference != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: widget.onEditReference,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit this reference in the note'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _actions(BuildContext context) {
    final colors = context.colors;
    if (_pickColor) {
      return SizedBox(
        height: 64,
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 0; i < highlightColors.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Semantics(
                button: true,
                label: 'Highlight ${highlightColors[i].name}',
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => _highlight(i),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                        color: highlightColors[i].of(context), shape: BoxShape.circle, border: Border.all(color: colors.outlineVariant)),
                  ),
                ),
              ),
            ),
          IconButton(tooltip: 'Remove highlight', icon: const Icon(Icons.format_color_reset_outlined), onPressed: () => _highlight(null)),
          IconButton(tooltip: 'Back', icon: const Icon(Icons.close), onPressed: () => setState(() => _pickColor = false)),
        ]),
      );
    }
    Widget action(IconData icon, String label, VoidCallback onTap, {bool active = false}) => Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 22, color: active ? colors.secondary : colors.onSurface),
                const SizedBox(height: 3),
                Text(label, style: context.text.labelSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
          ),
        );
    return Container(
      decoration: BoxDecoration(border: Border(top: BorderSide(color: colors.outlineVariant))),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Row(children: [
        action(Icons.copy_rounded, 'Copy', () => copyToClipboard(context, _shareText)),
        action(Icons.ios_share, 'Share', () => shareText(context, _shareText)),
        action(_bookmarked ? Icons.bookmark : Icons.bookmark_border, _bookmarked ? 'Saved' : 'Bookmark', _toggleBookmark,
            active: _bookmarked),
        action(Icons.border_color_outlined, 'Highlight', () => setState(() => _pickColor = true)),
        action(Icons.menu_book_outlined, 'Open', () => openReader(context, widget.reference)),
      ]),
    );
  }
}

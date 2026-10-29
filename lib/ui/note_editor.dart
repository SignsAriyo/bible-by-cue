import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/bible_repository.dart';
import '../core/platform.dart';
import '../core/reference.dart';
import '../core/user_store.dart';
import 'common.dart';
import 'insert_scripture.dart';
import 'note_text.dart';
import 'scripture_preview.dart';
import 'theme.dart';

Future<void> openNote(BuildContext context, int id) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => NoteEditorPage(noteId: id)));

/// Creates a note and opens it, optionally pre-filled with the sermon template.
Future<void> createAndOpenNote(BuildContext context, {NoteKind kind = NoteKind.general, bool sermonTemplate = false, int? folderId}) async {
  final note = await services.store.createNote(
    kind: sermonTemplate ? NoteKind.sermon : kind,
    body: sermonTemplate ? sermonTemplateBody() : '',
    folderId: folderId,
  );
  if (context.mounted) {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => NoteEditorPage(noteId: note.id, isNew: true)));
  }
}

String sermonTemplateBody() => '''**Preacher:**
**Church or event:**
**Date:** ${longDate(DateTime.now())}
**Main Scripture:**
**Theme:**

## Introduction


## Main points
1.

## Supporting Scriptures
-

## Personal reflections


## Practical application
- [ ]

## Prayer points
- [ ]

## Conclusion
''';

String noteAsMarkdown(Note n, {String? title, String? subtitle, String? body}) {
  final t = (title ?? n.title).trim();
  final s = (subtitle ?? n.subtitle).trim();
  return '# ${t.isEmpty ? 'Untitled note' : t}\n${s.isEmpty ? '' : '\n*$s*\n'}\n${body ?? n.body}\n';
}

String noteAsText(Note n, {String? title, String? subtitle, String? body}) {
  final t = (title ?? n.title).trim();
  final s = (subtitle ?? n.subtitle).trim();
  return '${t.isEmpty ? 'Untitled note' : t}\n${s.isEmpty ? '' : '$s\n'}\n${plainText(body ?? n.body)}\n';
}

String safeFileName(String s) {
  final cleaned = s.replaceAll(RegExp(r'[^\w\- ]+'), '').trim().replaceAll(RegExp(r'\s+'), '-');
  return cleaned.isEmpty ? 'note' : (cleaned.length > 60 ? cleaned.substring(0, 60) : cleaned);
}

enum _SaveState { saved, editing, saving, failed }

class NoteEditorPage extends StatefulWidget {
  final int noteId;
  final bool isNew;
  const NoteEditorPage({super.key, required this.noteId, this.isNew = false});

  @override
  State<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends State<NoteEditorPage> with WidgetsBindingObserver {
  Note? _note;
  final _title = TextEditingController();
  final _subtitle = TextEditingController();
  late final _body = NoteTextController(versification: () => services.bible);
  final _undo = UndoHistoryController();
  final _bodyFocus = FocusNode(debugLabel: 'note body');
  final _titleFocus = FocusNode(debugLabel: 'note title');
  final _scroll = ScrollController();

  _SaveState _saveState = _SaveState.saved;
  Future<void> _saveChain = Future.value();
  Timer? _saveTimer, _prefetchTimer, _autoTimer;
  String _savedTitle = '', _savedSubtitle = '', _savedBody = '';
  String _lastBodyText = '';

  TextSelection _lastSel = const TextSelection.collapsed(offset: -1);
  TextSelection? _prevSel;
  bool _focusedAtPointerDown = false;

  final _sheetKey = GlobalKey<ScripturePreviewSheetState>();
  Reference? _preview;
  List<Verse> _previewVerses = const [];
  bool _refocusAfterPreview = false;
  Reference? _lastAutoPreview;
  final Map<Reference, List<Verse>> _cache = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    services.bibleChanged.addListener(_translationChanged);
    _load();
  }

  Future<void> _load() async {
    final n = await services.store.note(widget.noteId);
    if (!mounted) return;
    if (n == null) {
      Navigator.of(context).maybePop();
      return;
    }
    _title.text = _savedTitle = n.title;
    _subtitle.text = _savedSubtitle = n.subtitle;
    _body.value = TextEditingValue(text: n.body, selection: TextSelection.collapsed(offset: n.body.length));
    _savedBody = _lastBodyText = n.body;
    _lastSel = _body.selection;
    _title.addListener(_changed);
    _subtitle.addListener(_changed);
    _body.addListener(_bodyChanged);
    setState(() => _note = n);
    _prefetch();
    if (widget.isNew) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _titleFocus.requestFocus());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    services.bibleChanged.removeListener(_translationChanged);
    _saveTimer?.cancel();
    _prefetchTimer?.cancel();
    _autoTimer?.cancel();
    if (_note != null && _isDirty) _save();
    _title.dispose();
    _subtitle.dispose();
    _body.dispose();
    _undo.dispose();
    _bodyFocus.dispose();
    _titleFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Save immediately whenever the app may be closed or killed.
    if (state != AppLifecycleState.resumed && _isDirty) _save();
  }

  void _translationChanged() {
    _cache.clear();
    _body.invalidateReferences();
  }

  bool get _isDirty => _title.text != _savedTitle || _subtitle.text != _savedSubtitle || _body.text != _savedBody;

  void _bodyChanged() {
    final sel = _body.selection;
    if (sel != _lastSel) {
      _prevSel = _lastSel;
      _lastSel = sel;
    }
    if (_body.text != _lastBodyText) {
      _lastBodyText = _body.text;
      _changed();
      _schedulePrefetch();
      _scheduleAutoPreview();
    }
  }

  void _changed() {
    if (!_isDirty) return;
    if (_saveState != _SaveState.editing) setState(() => _saveState = _SaveState.editing);
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 700), _save);
  }

  /// Saves are serialised so that a slow write can never be overtaken by an older one.
  Future<void> _save() {
    _saveTimer?.cancel();
    final title = _title.text, subtitle = _subtitle.text, body = _body.text;
    if (mounted) setState(() => _saveState = _SaveState.saving);
    return _saveChain = _saveChain.then((_) async {
      try {
        await services.store.saveNote(widget.noteId, title: title, subtitle: subtitle, body: body);
        _savedTitle = title;
        _savedSubtitle = subtitle;
        _savedBody = body;
        if (mounted) setState(() => _saveState = _isDirty ? _SaveState.editing : _SaveState.saved);
      } catch (_) {
        if (mounted) setState(() => _saveState = _SaveState.failed);
      }
    });
  }

  void _schedulePrefetch() {
    _prefetchTimer?.cancel();
    _prefetchTimer = Timer(const Duration(milliseconds: 500), _prefetch);
  }

  /// Loads the text of every reference in the note ahead of time so previews open instantly.
  Future<void> _prefetch() async {
    for (final m in _body.references) {
      final r = m.reference;
      if (r == null || _cache.containsKey(r)) continue;
      _cache[r] = await services.bible.passage(r);
    }
  }

  void _scheduleAutoPreview() {
    _autoTimer?.cancel();
    if (!services.settings.autoPreview) return;
    _autoTimer = Timer(const Duration(milliseconds: 1200), () {
      if (!mounted || _preview != null) return;
      final off = _body.selection.baseOffset;
      for (final m in _body.references) {
        if (m.isValid && m.end <= off && off - m.end <= 1 && m.reference != _lastAutoPreview) {
          _lastAutoPreview = m.reference;
          _openPreview(m.reference!, keepFocus: true);
          return;
        }
      }
    });
  }

  void _onBodyTap() {
    final sel = _body.selection;
    if (!sel.isCollapsed || sel.baseOffset < 0) return;
    final off = sel.baseOffset;
    final box = _body.checkboxAt(off);
    if (box != null) {
      if (_prevSel != null && _prevSel!.isValid) _body.selection = _prevSel!;
      _body.toggleCheckbox(box);
      if (!_focusedAtPointerDown) _bodyFocus.unfocus();
      return;
    }
    final m = _body.referenceAt(off);
    if (m == null) return;
    // Treat the tap as "open this reference", not as moving the cursor.
    final restore = _prevSel;
    if (restore != null && restore.isValid && restore.end <= _body.text.length) {
      _body.selection = restore;
    }
    if (m.isValid) {
      _openPreview(m.reference!, focusedBefore: _focusedAtPointerDown);
    } else {
      if (!_focusedAtPointerDown) _bodyFocus.unfocus();
      toast(context, '${_body.text.substring(m.start, m.end)}: ${m.error}');
    }
  }

  Future<void> _openPreview(Reference r, {bool keepFocus = false, bool? focusedBefore}) async {
    final verses = _cache[r] ?? await services.bible.passage(r);
    _cache[r] = verses;
    if (!mounted) return;
    if (verses.isEmpty) {
      toast(context, '${r.label} is not in ${services.bible.translation.name}.');
      return;
    }
    if (_preview == null) _refocusAfterPreview = focusedBefore ?? _bodyFocus.hasFocus;
    if (!keepFocus) FocusManager.instance.primaryFocus?.unfocus();
    HapticFeedback.selectionClick();
    setState(() {
      _preview = r;
      _previewVerses = verses;
    });
  }

  void _closePreview() => _sheetKey.currentState?.dismiss();

  void _previewClosed() {
    setState(() => _preview = null);
    if (_refocusAfterPreview) {
      _bodyFocus.requestFocus();
    }
  }

  List<Reference> get _validRefs {
    final seen = <Reference>{};
    return [for (final m in _body.references) if (m.isValid && seen.add(m.reference!)) m.reference!];
  }

  void _stepPreview(int delta) {
    final refs = _validRefs;
    final i = refs.indexOf(_preview!);
    final next = (i + delta) % refs.length;
    _openPreview(refs[next < 0 ? next + refs.length : next]);
  }

  void _editPreviewedReference() {
    final r = _preview;
    final m = _body.references.where((m) => m.reference == r).firstOrNull;
    _refocusAfterPreview = false;
    _closePreview();
    if (m != null) {
      _body.selection = TextSelection.collapsed(offset: m.end);
      _bodyFocus.requestFocus();
    }
  }

  // ------------------------------------------------------------------ toolbar actions

  void _ensureBodySelection() {
    if (!_body.selection.isValid) _body.selection = TextSelection.collapsed(offset: _body.text.length);
  }

  void _format(void Function() op) {
    _ensureBodySelection();
    op();
    if (!_bodyFocus.hasFocus) _bodyFocus.requestFocus();
  }

  Future<void> _insertScripture() async {
    final choice = await showInsertScripture(context);
    if (choice == null || !mounted) return;
    _ensureBodySelection();
    final sel = _body.selection;
    final atLineStart = sel.start == 0 || _body.text[sel.start - 1] == '\n';
    String insert;
    if (choice.withText) {
      insert = '${atLineStart ? '' : '\n'}${choice.reference.label}\n> ${choice.text}\n';
    } else {
      final needsSpace = !atLineStart && _body.text[sel.start - 1] != ' ';
      insert = '${needsSpace ? ' ' : ''}${choice.reference.label} ';
    }
    _body.replaceSelection(insert);
    _bodyFocus.requestFocus();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final t = data?.text;
    if (t == null || t.isEmpty) {
      if (mounted) toast(context, 'The clipboard is empty');
      return;
    }
    _format(() => _body.replaceSelection(t));
  }

  void _copy() {
    final sel = _body.selection;
    final t = sel.isValid && !sel.isCollapsed ? sel.textInside(_body.text) : _body.text;
    copyToClipboard(context, t, message: sel.isValid && !sel.isCollapsed ? 'Selection copied' : 'Whole note copied');
  }

  // ------------------------------------------------------------------ menu actions

  Note get _current => Note(
        id: _note!.id, uid: _note!.uid, title: _title.text, subtitle: _subtitle.text, body: _body.text, kind: _note!.kind,
        folderId: _note!.folderId, pinned: _note!.pinned, archived: _note!.archived, deletedAt: _note!.deletedAt,
        createdAt: _note!.createdAt, updatedAt: _note!.updatedAt,
      );

  Future<void> _reloadMeta() async {
    final n = await services.store.note(widget.noteId);
    if (n != null && mounted) setState(() => _note = n);
  }

  Future<void> _menu(String action) async {
    final n = _current;
    switch (action) {
      case 'template':
        _format(() => _body.replaceSelection(
            '${_body.selection.start > 0 && _body.text[_body.selection.start - 1] != '\n' ? '\n' : ''}${sermonTemplateBody()}'));
        if (_note!.kind == NoteKind.general) {
          await services.store.updateNoteMeta(n.id, kind: NoteKind.sermon);
          await _reloadMeta();
        }
      case 'export_md':
        await _export(noteAsMarkdown(n), '${safeFileName(n.displayTitle)}.md', 'text/markdown');
      case 'export_txt':
        await _export(noteAsText(n), '${safeFileName(n.displayTitle)}.txt', 'text/plain');
      case 'share':
        await shareText(context, noteAsText(n), subject: n.displayTitle);
      case 'duplicate':
        await _save();
        final copy = await services.store.duplicateNote(n);
        if (mounted) {
          toast(context, 'Duplicated as “${copy.displayTitle}”',
              action: SnackBarAction(label: 'Open', onPressed: () => openNote(context, copy.id)));
        }
      case 'archive':
        await _save();
        await services.store.updateNoteMeta(n.id, archived: !n.archived);
        if (mounted) {
          toast(context, n.archived ? 'Note restored from archive' : 'Note archived');
          if (!n.archived) Navigator.pop(context);
        }
      case 'trash':
        await _save();
        await services.store.trashNote(n.id);
        if (mounted) {
          Navigator.pop(context);
          toast(context, 'Moved to trash — you can restore it for 30 days',
              action: SnackBarAction(label: 'Undo', onPressed: () => services.store.restoreNote(n.id)));
        }
    }
  }

  Future<void> _export(String content, String name, String mime) async {
    try {
      final saved = await PlatformBridge.saveDocument(name, mime, utf8.encode(content));
      if (saved != null && mounted) toast(context, 'Saved as $saved');
    } catch (e) {
      if (mounted) toast(context, 'Could not export: $e');
    }
  }

  Future<void> _chooseKind() async {
    final k = await showModalBottomSheet<NoteKind>(
      context: context,
      builder: (context) => SafeArea(
        child: ScrollColumn(mainAxisSize: MainAxisSize.min, children: [
          for (final k in NoteKind.values)
            ListTile(
              leading: Icon(noteKindIcon(k)),
              title: Text(k.label),
              trailing: k == _note!.kind ? Icon(Icons.check, color: context.colors.primary) : null,
              onTap: () => Navigator.pop(context, k),
            ),
        ]),
      ),
    );
    if (k != null) {
      await services.store.updateNoteMeta(widget.noteId, kind: k);
      await _reloadMeta();
    }
  }

  Future<void> _chooseFolder() async {
    final id = await pickFolder(context, current: _note!.folderId);
    if (id == null) return;
    await services.store.updateNoteMeta(widget.noteId, folderId: id == 0 ? null : id);
    await _reloadMeta();
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final note = _note;
    return PopScope(
      canPop: _preview == null,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) {
          _closePreview();
          return;
        }
        if (note != null && _title.text.trim().isEmpty && _subtitle.text.trim().isEmpty && _body.text.trim().isEmpty) {
          _saveTimer?.cancel();
          _savedTitle = _title.text;
          _savedSubtitle = _subtitle.text;
          _savedBody = _body.text;
          await services.store.deleteNoteForever(note.id);
        }
      },
      child: Stack(children: [
        Scaffold(
          appBar: AppBar(
            actions: note == null
                ? null
                : [
                    _SaveIndicator(state: _saveState, onRetry: _save),
                    IconButton(
                      tooltip: note.pinned ? 'Unpin' : 'Pin',
                      icon: Icon(note.pinned ? Icons.push_pin : Icons.push_pin_outlined),
                      onPressed: () async {
                        await services.store.updateNoteMeta(note.id, pinned: !note.pinned);
                        await _reloadMeta();
                      },
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'More',
                      onSelected: _menu,
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'template', child: ListTile(leading: Icon(Icons.article_outlined), title: Text('Insert sermon template'))),
                        const PopupMenuItem(value: 'share', child: ListTile(leading: Icon(Icons.ios_share), title: Text('Share'))),
                        const PopupMenuItem(value: 'export_md', child: ListTile(leading: Icon(Icons.download_outlined), title: Text('Export as Markdown'))),
                        const PopupMenuItem(value: 'export_txt', child: ListTile(leading: Icon(Icons.text_snippet_outlined), title: Text('Export as plain text'))),
                        const PopupMenuItem(value: 'duplicate', child: ListTile(leading: Icon(Icons.copy_all_outlined), title: Text('Duplicate'))),
                        PopupMenuItem(
                            value: 'archive',
                            child: ListTile(
                                leading: const Icon(Icons.archive_outlined), title: Text(note.archived ? 'Unarchive' : 'Archive'))),
                        const PopupMenuItem(value: 'trash', child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Move to trash'))),
                      ],
                    ),
                  ],
          ),
          body: note == null
              ? const SizedBox.shrink()
              : Column(children: [
                  Expanded(child: _editor(context, note)),
                  _Toolbar(
                    undo: _undo,
                    onAction: (a) {
                      switch (a) {
                        case 'h1':
                          _format(() => _body.toggleBlock('# '));
                        case 'h2':
                          _format(() => _body.toggleBlock('## '));
                        case 'bold':
                          _format(() => _body.toggleInline('**'));
                        case 'italic':
                          _format(() => _body.toggleInline('*'));
                        case 'bullet':
                          _format(() => _body.toggleBlock('- '));
                        case 'number':
                          _format(() => _body.toggleBlock('', numbered: true));
                        case 'check':
                          _format(() => _body.toggleBlock('- [ ] '));
                        case 'quote':
                          _format(() => _body.toggleBlock('> '));
                        case 'para':
                          _format(() => _body.replaceSelection('\n\n'));
                        case 'scripture':
                          _insertScripture();
                        case 'date':
                          _format(() => _body.replaceSelection(longDate(DateTime.now())));
                        case 'copy':
                          _copy();
                        case 'paste':
                          _paste();
                        case 'all':
                          _bodyFocus.requestFocus();
                          _body.selection = TextSelection(baseOffset: 0, extentOffset: _body.text.length);
                      }
                    },
                  ),
                ]),
        ),
        if (_preview != null)
          ScripturePreviewSheet(
            key: _sheetKey,
            reference: _preview!,
            verses: _previewVerses,
            index: _validRefs.indexOf(_preview!).clamp(0, 1 << 20),
            count: _validRefs.length,
            onPrevious: _validRefs.length > 1 ? () => _stepPreview(-1) : null,
            onNext: _validRefs.length > 1 ? () => _stepPreview(1) : null,
            onEditReference: _editPreviewedReference,
            onClosed: _previewClosed,
          ),
      ]),
    );
  }

  Widget _editor(BuildContext context, Note note) {
    final settings = services.settings;
    final bodyStyle = TextStyle(
      fontFamily: readingFont,
      fontSize: (settings.fontSize - 2).clamp(15, 28).toDouble(),
      height: 1.6,
      color: context.colors.onSurface,
    );
    return Scrollbar(
      controller: _scroll,
      child: SingleChildScrollView(
        controller: _scroll,
        padding: const EdgeInsets.only(bottom: 120),
        child: ReadableWidth(
          max: 760,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(
                controller: _title,
                focusNode: _titleFocus,
                maxLines: null,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => _bodyFocus.requestFocus(),
                style: context.text.headlineSmall?.copyWith(fontSize: 26),
                decoration: InputDecoration(
                  hintText: note.kind == NoteKind.sermon ? 'Sermon title' : 'Title',
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.only(top: 4, bottom: 2),
                ),
              ),
              TextField(
                controller: _subtitle,
                maxLines: null,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => _bodyFocus.requestFocus(),
                style: context.text.titleMedium?.copyWith(color: context.muted),
                decoration: const InputDecoration(
                  hintText: 'Subtitle (optional)',
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 4),
                ),
              ),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                ActionChip(
                  avatar: Icon(noteKindIcon(note.kind), size: 18),
                  label: Text(note.kind.label),
                  onPressed: _chooseKind,
                  visualDensity: VisualDensity.compact,
                ),
                FutureBuilder(
                  future: services.store.folders(),
                  builder: (context, snap) {
                    final name = snap.data?.where((f) => f.id == note.folderId).firstOrNull?.name;
                    return ActionChip(
                      avatar: const Icon(Icons.folder_outlined, size: 18),
                      label: Text(name ?? 'No folder'),
                      onPressed: _chooseFolder,
                      visualDensity: VisualDensity.compact,
                    );
                  },
                ),
                Text('Edited ${relativeTime(note.updatedAt)}', style: context.text.labelSmall?.copyWith(color: context.muted)),
              ]),
              const SizedBox(height: 10),
              const Divider(),
              const SizedBox(height: 6),
              Listener(
                onPointerDown: (_) => _focusedAtPointerDown = _bodyFocus.hasFocus,
                child: TextField(
                  controller: _body,
                  focusNode: _bodyFocus,
                  undoController: _undo,
                  readOnly: _preview != null,
                  maxLines: null,
                  minLines: 12,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  inputFormatters: [ListContinuationFormatter()],
                  onTap: _onBodyTap,
                  style: bodyStyle,
                  scrollPadding: const EdgeInsets.only(bottom: 140),
                  decoration: const InputDecoration(
                    hintText: 'Start writing…\n\nScripture references such as John 3:16 or Romans 8:28–30 become tappable.',
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

IconData noteKindIcon(NoteKind k) => switch (k) {
      NoteKind.sermon => Icons.church_outlined,
      NoteKind.study => Icons.school_outlined,
      NoteKind.devotional => Icons.wb_twilight,
      NoteKind.prayer => Icons.volunteer_activism_outlined,
      NoteKind.general => Icons.notes,
    };

/// Returns a folder id, 0 for "no folder", or null if cancelled.
Future<int?> pickFolder(BuildContext context, {int? current}) async {
  final folders = await services.store.folders();
  if (!context.mounted) return null;
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
        child: ListView(shrinkWrap: true, children: [
          Padding(padding: const EdgeInsets.fromLTRB(24, 0, 24, 8), child: Text('Move to folder', style: context.text.titleLarge)),
          ListTile(
            leading: const Icon(Icons.folder_off_outlined),
            title: const Text('No folder'),
            trailing: current == null ? Icon(Icons.check, color: context.colors.primary) : null,
            onTap: () => Navigator.pop(context, 0),
          ),
          for (final f in folders)
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: Text(f.name),
              trailing: current == f.id ? Icon(Icons.check, color: context.colors.primary) : null,
              onTap: () => Navigator.pop(context, f.id),
            ),
          ListTile(
            leading: const Icon(Icons.create_new_folder_outlined),
            title: const Text('New folder…'),
            onTap: () async {
              final name = await promptText(context, title: 'New folder', hint: 'Folder name');
              if (name == null || name.trim().isEmpty) return;
              final id = await services.store.createFolder(name);
              if (context.mounted) Navigator.pop(context, id);
            },
          ),
        ]),
      ),
    ),
  );
}

Future<String?> promptText(BuildContext context, {required String title, String hint = '', String initial = '', String action = 'Save'}) {
  final ctl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctl,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, ctl.text), child: Text(action)),
      ],
    ),
  );
}

class _SaveIndicator extends StatelessWidget {
  final _SaveState state;
  final VoidCallback onRetry;
  const _SaveIndicator({required this.state, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final (icon, label, color) = switch (state) {
      _SaveState.saved => (Icons.cloud_done_outlined, 'Saved', context.muted),
      _SaveState.editing => (Icons.edit_outlined, 'Editing', context.muted),
      _SaveState.saving => (Icons.sync, 'Saving…', context.muted),
      _SaveState.failed => (Icons.error_outline, 'Not saved · retry', context.colors.error),
    };
    final child = Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(state == _SaveState.saved ? Icons.check_circle_outline : icon, size: 16, color: color),
      const SizedBox(width: 4),
      Text(label, style: context.text.labelMedium?.copyWith(color: color)),
    ]);
    return Semantics(
      liveRegion: true,
      label: 'Note status: $label',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: state == _SaveState.failed ? TextButton(onPressed: onRetry, child: child) : child,
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  final UndoHistoryController undo;
  final ValueChanged<String> onAction;
  const _Toolbar({required this.undo, required this.onAction});

  @override
  Widget build(BuildContext context) {
    Widget b(String id, IconData icon, String tip) => IconButton(
          tooltip: tip,
          icon: Icon(icon),
          onPressed: () => onAction(id),
        );
    Widget gap() => Container(width: 1, height: 24, margin: const EdgeInsets.symmetric(horizontal: 4), color: context.colors.outlineVariant);
    return TextFieldTapRegion(
      child: Material(
        color: context.colors.surfaceContainerHigh,
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 52,
            child: ValueListenableBuilder<UndoHistoryValue>(
              valueListenable: undo,
              builder: (context, v, _) => ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 4), children: [
                IconButton(tooltip: 'Undo', icon: const Icon(Icons.undo), onPressed: v.canUndo ? undo.undo : null),
                IconButton(tooltip: 'Redo', icon: const Icon(Icons.redo), onPressed: v.canRedo ? undo.redo : null),
                gap(),
                b('scripture', Icons.menu_book_outlined, 'Insert Scripture'),
                b('h1', Icons.title, 'Heading'),
                b('h2', Icons.text_fields, 'Subheading'),
                b('bold', Icons.format_bold, 'Bold'),
                b('italic', Icons.format_italic, 'Italic'),
                gap(),
                b('bullet', Icons.format_list_bulleted, 'Bulleted list'),
                b('number', Icons.format_list_numbered, 'Numbered list'),
                b('check', Icons.checklist, 'Checklist'),
                b('quote', Icons.format_quote_outlined, 'Quote'),
                b('para', Icons.keyboard_return, 'Paragraph break'),
                gap(),
                b('date', Icons.event_outlined, 'Insert today’s date'),
                b('copy', Icons.copy_rounded, 'Copy'),
                b('paste', Icons.content_paste, 'Paste'),
                b('all', Icons.select_all, 'Select all'),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

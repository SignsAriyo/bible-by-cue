import 'package:flutter/material.dart';

import '../core/user_store.dart';
import 'common.dart';
import 'note_editor.dart';
import 'theme.dart';

class NotesPage extends StatefulWidget {
  const NotesPage({super.key});
  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage> {
  NoteView _view = NoteView.active;
  NoteKind? _kind;
  int? _folder;
  String _query = '';
  bool _searching = false;
  List<Note>? _notes;
  List<Folder> _folders = const [];
  int _token = 0;

  NoteSort get _sort => NoteSort.values.firstWhere((s) => s.name == services.settings.noteSort, orElse: () => NoteSort.edited);

  @override
  void initState() {
    super.initState();
    services.store.addListener(_load);
    services.store.purgeOldTrash();
    _load();
  }

  @override
  void dispose() {
    services.store.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final t = ++_token;
    final notes = await services.store.notes(view: _view, kind: _kind, folderId: _folder, query: _query, sort: _sort);
    final folders = await services.store.folders();
    if (!mounted || t != _token) return;
    setState(() {
      _notes = notes;
      _folders = folders;
      if (_folder != null && !folders.any((f) => f.id == _folder)) _folder = null;
    });
  }

  void _set(VoidCallback f) {
    setState(f);
    _load();
  }

  Future<void> _newNote() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ScrollColumn(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.fromLTRB(24, 0, 24, 8), child: Text('New note', style: context.text.titleLarge)),
          ListTile(
            leading: const Icon(Icons.edit_note),
            title: const Text('Blank note'),
            subtitle: const Text('Start with an empty page'),
            onTap: () => Navigator.pop(context, 'blank'),
          ),
          ListTile(
            leading: const Icon(Icons.church_outlined),
            title: const Text('Sermon notes'),
            subtitle: const Text('Template with preacher, Scriptures, main points and prayer'),
            onTap: () => Navigator.pop(context, 'sermon'),
          ),
          ListTile(
            leading: const Icon(Icons.school_outlined),
            title: const Text('Bible study'),
            onTap: () => Navigator.pop(context, 'study'),
          ),
          ListTile(
            leading: const Icon(Icons.wb_twilight),
            title: const Text('Devotional'),
            onTap: () => Navigator.pop(context, 'devotional'),
          ),
          ListTile(
            leading: const Icon(Icons.volunteer_activism_outlined),
            title: const Text('Prayer'),
            onTap: () => Navigator.pop(context, 'prayer'),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (choice == null || !mounted) return;
    await createAndOpenNote(
      context,
      sermonTemplate: choice == 'sermon',
      kind: switch (choice) {
        'study' => NoteKind.study,
        'devotional' => NoteKind.devotional,
        'prayer' => NoteKind.prayer,
        _ => _kind ?? NoteKind.general,
      },
      folderId: _folder,
    );
  }

  Future<void> _noteActions(Note n) async {
    final trash = _view == NoteView.trash;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ScrollColumn(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(n.displayTitle, style: context.text.titleLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          if (trash) ...[
            ListTile(leading: const Icon(Icons.restore), title: const Text('Restore'), onTap: () => Navigator.pop(context, 'restore')),
            ListTile(
              leading: Icon(Icons.delete_forever_outlined, color: context.colors.error),
              title: Text('Delete forever', style: TextStyle(color: context.colors.error)),
              onTap: () => Navigator.pop(context, 'forever'),
            ),
          ] else ...[
            ListTile(
              leading: Icon(n.pinned ? Icons.push_pin : Icons.push_pin_outlined),
              title: Text(n.pinned ? 'Unpin' : 'Pin to top'),
              onTap: () => Navigator.pop(context, 'pin'),
            ),
            ListTile(leading: const Icon(Icons.drive_file_rename_outline), title: const Text('Rename'), onTap: () => Navigator.pop(context, 'rename')),
            ListTile(leading: const Icon(Icons.copy_all_outlined), title: const Text('Duplicate'), onTap: () => Navigator.pop(context, 'duplicate')),
            ListTile(leading: const Icon(Icons.folder_outlined), title: const Text('Move to folder'), onTap: () => Navigator.pop(context, 'folder')),
            ListTile(
              leading: const Icon(Icons.archive_outlined),
              title: Text(n.archived ? 'Unarchive' : 'Archive'),
              onTap: () => Navigator.pop(context, 'archive'),
            ),
            ListTile(leading: const Icon(Icons.delete_outline), title: const Text('Move to trash'), onTap: () => Navigator.pop(context, 'trash')),
          ],
        ]),
      ),
    );
    if (action == null || !mounted) return;
    final s = services.store;
    switch (action) {
      case 'restore':
        await s.restoreNote(n.id);
      case 'forever':
        final ok = await _confirm('Delete “${n.displayTitle}” forever?', 'This cannot be undone.', 'Delete');
        if (ok) await s.deleteNoteForever(n.id);
      case 'pin':
        await s.updateNoteMeta(n.id, pinned: !n.pinned);
      case 'rename':
        final name = await promptText(context, title: 'Rename note', initial: n.title, hint: 'Title');
        if (name != null) await s.saveNote(n.id, title: name.trim(), subtitle: n.subtitle, body: n.body);
      case 'duplicate':
        await s.duplicateNote(n);
      case 'folder':
        final id = await pickFolder(context, current: n.folderId);
        if (id != null) await s.updateNoteMeta(n.id, folderId: id == 0 ? null : id);
      case 'archive':
        await s.updateNoteMeta(n.id, archived: !n.archived);
      case 'trash':
        await s.trashNote(n.id);
        if (mounted) {
          toast(context, 'Moved to trash', action: SnackBarAction(label: 'Undo', onPressed: () => s.restoreNote(n.id)));
        }
    }
  }

  Future<bool> _confirm(String title, String message, String action) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: context.colors.error, foregroundColor: context.colors.onError),
                onPressed: () => Navigator.pop(context, true),
                child: Text(action),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _manageFolders() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(builder: (context, setSheet) {
        return FutureBuilder(
          future: services.store.folders(),
          builder: (context, snap) {
            final folders = snap.data ?? const <Folder>[];
            return SafeArea(
              child: ScrollColumn(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(padding: const EdgeInsets.fromLTRB(24, 0, 24, 8), child: Text('Folders', style: context.text.titleLarge)),
                if (folders.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    child: Text('Group sermons by church, series or season.', style: TextStyle(color: context.muted)),
                  ),
                for (final f in folders)
                  ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(f.name),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        tooltip: 'Rename folder',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () async {
                          final n = await promptText(context, title: 'Rename folder', initial: f.name);
                          if (n != null && n.trim().isNotEmpty) await services.store.renameFolder(f.id, n);
                          setSheet(() {});
                        },
                      ),
                      IconButton(
                        tooltip: 'Delete folder (notes are kept)',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          await services.store.deleteFolder(f.id);
                          setSheet(() {});
                        },
                      ),
                    ]),
                  ),
                ListTile(
                  leading: const Icon(Icons.create_new_folder_outlined),
                  title: const Text('New folder'),
                  onTap: () async {
                    final n = await promptText(context, title: 'New folder', hint: 'Folder name');
                    if (n != null && n.trim().isNotEmpty) await services.store.createFolder(n);
                    setSheet(() {});
                  },
                ),
                const SizedBox(height: 8),
              ]),
            );
          },
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (_view) {
      NoteView.active => 'Notes',
      NoteView.archived => 'Archive',
      NoteView.trash => 'Trash',
    };
    return Scaffold(
      appBar: AppBar(
        leading: _view == NoteView.active
            ? null
            : IconButton(tooltip: 'Back to notes', icon: const Icon(Icons.arrow_back), onPressed: () => _set(() => _view = NoteView.active)),
        title: _searching
            ? TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search notes',
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
                onChanged: (q) => _set(() => _query = q),
              )
            : Text(title),
        actions: [
          IconButton(
            tooltip: _searching ? 'Close search' : 'Search notes',
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: () => _set(() {
              _searching = !_searching;
              _query = '';
            }),
          ),
          PopupMenuButton<String>(
            tooltip: 'Sort and more',
            onSelected: (v) async {
              switch (v) {
                case 'edited' || 'created' || 'title':
                  services.settings.noteSort = v;
                  _load();
                case 'folders':
                  await _manageFolders();
                case 'archive':
                  _set(() => _view = NoteView.archived);
                case 'trash':
                  _set(() => _view = NoteView.trash);
                case 'empty':
                  if (await _confirm('Empty trash?', 'All notes in the trash will be deleted permanently.', 'Empty trash')) {
                    await services.store.emptyTrash();
                  }
              }
            },
            itemBuilder: (_) => [
              for (final (v, label) in [('edited', 'Last edited'), ('created', 'Date created'), ('title', 'Title')])
                CheckedPopupMenuItem(value: v, checked: _sort.name == v, child: Text('Sort by $label')),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'folders', child: Text('Manage folders')),
              if (_view != NoteView.archived) const PopupMenuItem(value: 'archive', child: Text('Archived notes')),
              if (_view != NoteView.trash) const PopupMenuItem(value: 'trash', child: Text('Recently deleted')),
              if (_view == NoteView.trash) const PopupMenuItem(value: 'empty', child: Text('Empty trash')),
            ],
          ),
        ],
      ),
      floatingActionButton: _view == NoteView.active
          ? FloatingActionButton.extended(onPressed: _newNote, icon: const Icon(Icons.add), label: const Text('New note'))
          : null,
      body: ReadableWidth(
        max: 840,
        child: Column(children: [
          if (_view == NoteView.active) _filters(context),
          if (_view == NoteView.trash)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text('Notes in the trash are deleted permanently after 30 days.', style: TextStyle(color: context.muted)),
            ),
          Expanded(child: _list(context)),
        ]),
      ),
    );
  }

  Widget _filters(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(16, 4, 16, 8), children: [
        ChoiceChip(label: const Text('All'), selected: _kind == null, onSelected: (_) => _set(() => _kind = null)),
        for (final k in NoteKind.values) ...[
          const SizedBox(width: 8),
          ChoiceChip(
            avatar: Icon(noteKindIcon(k), size: 16),
            label: Text(k.label),
            selected: _kind == k,
            onSelected: (_) => _set(() => _kind = _kind == k ? null : k),
          ),
        ],
        if (_folders.isNotEmpty) ...[
          const SizedBox(width: 8),
          Container(width: 1, margin: const EdgeInsets.symmetric(vertical: 8), color: context.colors.outlineVariant),
          for (final f in _folders) ...[
            const SizedBox(width: 8),
            FilterChip(
              avatar: const Icon(Icons.folder_outlined, size: 16),
              label: Text(f.name),
              selected: _folder == f.id,
              onSelected: (_) => _set(() => _folder = _folder == f.id ? null : f.id),
            ),
          ],
        ],
      ]),
    );
  }

  Widget _list(BuildContext context) {
    final notes = _notes;
    if (notes == null) return const SizedBox.shrink();
    if (notes.isEmpty) {
      if (_query.isNotEmpty || _kind != null || _folder != null) {
        return const EmptyState(icon: Icons.search_off, title: 'No matching notes', message: 'Try another word or clear the filters.');
      }
      return switch (_view) {
        NoteView.trash => const EmptyState(icon: Icons.delete_outline, title: 'Trash is empty', message: 'Deleted notes stay here for 30 days.'),
        NoteView.archived => const EmptyState(icon: Icons.archive_outlined, title: 'No archived notes', message: 'Archive notes you want to keep but rarely need.'),
        NoteView.active => EmptyState(
            icon: Icons.edit_note,
            title: 'Your notes live here',
            message: 'Capture sermons, Bible studies and prayers. Type a reference like John 3:16 and tap it to read the passage instantly.',
            action: FilledButton.icon(
              onPressed: () => createAndOpenNote(context, sermonTemplate: true),
              icon: const Icon(Icons.church_outlined),
              label: const Text('Start a sermon note'),
            ),
          ),
      };
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
      itemCount: notes.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) => NoteCard(
        note: notes[i],
        onTap: () => _view == NoteView.trash ? _noteActions(notes[i]) : openNote(context, notes[i].id),
        onLongPress: () => _noteActions(notes[i]),
      ),
    );
  }
}

class NoteCard extends StatelessWidget {
  final Note note;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  const NoteCard({super.key, required this.note, required this.onTap, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final preview = note.plainBody.trim().replaceAll(RegExp(r'\s*\n\s*'), ' · ');
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(note.displayTitle,
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.titleMedium?.copyWith(fontFamily: readingFont, fontWeight: FontWeight.w700)),
              ),
              if (note.pinned) Icon(Icons.push_pin, size: 18, color: context.colors.secondary, semanticLabel: 'Pinned'),
            ]),
            if (note.subtitle.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(note.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.muted)),
              ),
            if (preview.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(preview, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium?.copyWith(height: 1.4)),
              ),
            const SizedBox(height: 10),
            Row(children: [
              Icon(noteKindIcon(note.kind), size: 15, color: context.colors.primary),
              const SizedBox(width: 4),
              Text(note.kind.label, style: context.text.labelSmall?.copyWith(color: context.colors.primary, fontWeight: FontWeight.w600)),
              const Spacer(),
              Text(note.deletedAt != null ? 'Deleted ${relativeTime(note.deletedAt!)}' : relativeTime(note.updatedAt),
                  style: context.text.labelSmall?.copyWith(color: context.muted)),
            ]),
          ]),
        ),
      ),
    );
  }
}

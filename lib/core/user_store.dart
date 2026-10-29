import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'bible_repository.dart';
import 'reference.dart';

String newUid() {
  final r = Random.secure();
  return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

int nowMs() => DateTime.now().millisecondsSinceEpoch;

enum NoteKind {
  sermon('Sermon'),
  study('Bible study'),
  devotional('Devotional'),
  prayer('Prayer'),
  general('General');

  final String label;
  const NoteKind(this.label);
  static NoteKind parse(String? s) => NoteKind.values.firstWhere((k) => k.name == s, orElse: () => NoteKind.general);
}

class Note {
  final int id;
  final String uid;
  final String title;
  final String subtitle;
  final String body;
  final NoteKind kind;
  final int? folderId;
  final bool pinned;
  final bool archived;
  final int? deletedAt;
  final int createdAt;
  final int updatedAt;

  const Note({
    required this.id,
    required this.uid,
    required this.title,
    required this.subtitle,
    required this.body,
    required this.kind,
    required this.folderId,
    required this.pinned,
    required this.archived,
    required this.deletedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Note.fromRow(Map<String, Object?> r) => Note(
        id: r['id'] as int,
        uid: r['uid'] as String,
        title: r['title'] as String,
        subtitle: r['subtitle'] as String,
        body: r['body'] as String,
        kind: NoteKind.parse(r['kind'] as String?),
        folderId: r['folder_id'] as int?,
        pinned: (r['pinned'] as int) == 1,
        archived: (r['archived'] as int) == 1,
        deletedAt: r['deleted_at'] as int?,
        createdAt: r['created_at'] as int,
        updatedAt: r['updated_at'] as int,
      );

  String get displayTitle => title.trim().isEmpty ? 'Untitled note' : title.trim();

  /// Body without Markdown markers, for previews and plain-text export.
  String get plainBody => plainText(body);
}

String plainText(String md) => md
    .replaceAll(RegExp(r'^#{1,3} ', multiLine: true), '')
    .replaceAll(RegExp(r'^- \[[xX]\] ', multiLine: true), '☑ ')
    .replaceAll(RegExp(r'^- \[ \] ', multiLine: true), '☐ ')
    .replaceAll(RegExp(r'^> ', multiLine: true), '')
    .replaceAll('**', '')
    .replaceAllMapped(RegExp(r'(^|[^*\w])\*([^*\n]+)\*'), (m) => '${m[1]}${m[2]}');

class Folder {
  final int id;
  final String name;
  const Folder(this.id, this.name);
}

class Bookmark {
  final int id;
  final String uid;
  final int startId;
  final int endId;
  final String comment;
  final int createdAt;
  final int updatedAt;
  const Bookmark(this.id, this.uid, this.startId, this.endId, this.comment, this.createdAt, this.updatedAt);
  Reference get reference => Reference.fromIds(startId, endId);
}

class Highlight {
  final int verseId;
  final int color;
  final int createdAt;
  const Highlight(this.verseId, this.color, this.createdAt);
}

class HistoryEntry {
  final int chapterKey;
  final int verse;
  final int openedAt;
  const HistoryEntry(this.chapterKey, this.verse, this.openedAt);
  int get book => chapterKey ~/ 1000;
  int get chapter => chapterKey % 1000;
}

enum NoteSort { edited, created, title }

enum NoteView { active, archived, trash }

class RestoreReport {
  int notesAdded = 0, notesCopied = 0, notesSkipped = 0;
  int bookmarksAdded = 0, bookmarksSkipped = 0;
  int highlightsAdded = 0, highlightsKept = 0;
  int foldersAdded = 0;
  bool settingsRestored = false;
  String? safetyBackup;

  @override
  String toString() {
    final parts = <String>[
      '$notesAdded notes added',
      if (notesCopied > 0) '$notesCopied changed notes kept side by side as copies',
      if (notesSkipped > 0) '$notesSkipped already up to date',
      '$bookmarksAdded bookmarks added',
      '$highlightsAdded highlights added',
      if (highlightsKept > 0) '$highlightsKept highlights kept as they were on this device',
      if (settingsRestored) 'settings restored',
    ];
    return parts.join(' · ');
  }
}

class BackupSummary {
  final int notes, bookmarks, highlights, folders;
  final DateTime? exportedAt;
  const BackupSummary(this.notes, this.bookmarks, this.highlights, this.folders, this.exportedAt);
}

/// Local, private storage for everything the user creates. Changes notify listeners so
/// screens refresh without polling.
class UserStore extends ChangeNotifier {
  final Database db;
  Versification versification;
  UserStore._(this.db, this.versification);

  static const _version = 1;
  static const backupFormat = 'bible-by-cue-backup';

  static Future<UserStore> open(Versification v) async {
    final path = p.join(await getDatabasesPath(), 'user.db');
    final db = await openDatabase(
      path,
      version: _version,
      singleInstance: true,
      onConfigure: (db) async {
        await db.rawQuery('PRAGMA journal_mode=WAL');
        await db.execute('PRAGMA foreign_keys=ON');
      },
      onCreate: (db, _) async {
        final b = db.batch();
        b.execute('''CREATE TABLE folders(id INTEGER PRIMARY KEY, name TEXT NOT NULL UNIQUE, created_at INTEGER NOT NULL)''');
        b.execute('''CREATE TABLE notes(
          id INTEGER PRIMARY KEY, uid TEXT NOT NULL UNIQUE, title TEXT NOT NULL DEFAULT '',
          subtitle TEXT NOT NULL DEFAULT '', body TEXT NOT NULL DEFAULT '', kind TEXT NOT NULL DEFAULT 'general',
          folder_id INTEGER REFERENCES folders(id) ON DELETE SET NULL, pinned INTEGER NOT NULL DEFAULT 0,
          archived INTEGER NOT NULL DEFAULT 0, deleted_at INTEGER, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)''');
        b.execute('CREATE INDEX notes_updated ON notes(updated_at)');
        b.execute('''CREATE TABLE note_refs(note_id INTEGER NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
          start_id INTEGER NOT NULL, end_id INTEGER NOT NULL)''');
        b.execute('CREATE INDEX note_refs_range ON note_refs(start_id, end_id)');
        b.execute('CREATE INDEX note_refs_note ON note_refs(note_id)');
        b.execute('''CREATE TABLE bookmarks(id INTEGER PRIMARY KEY, uid TEXT NOT NULL UNIQUE, start_id INTEGER NOT NULL,
          end_id INTEGER NOT NULL, comment TEXT NOT NULL DEFAULT '', created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)''');
        b.execute('CREATE INDEX bookmarks_start ON bookmarks(start_id)');
        b.execute('CREATE TABLE highlights(verse_id INTEGER PRIMARY KEY, color INTEGER NOT NULL, created_at INTEGER NOT NULL)');
        b.execute('CREATE TABLE history(chapter_key INTEGER PRIMARY KEY, verse INTEGER NOT NULL, opened_at INTEGER NOT NULL)');
        b.execute('CREATE INDEX history_opened ON history(opened_at)');
        b.execute('CREATE TABLE prefs(k TEXT PRIMARY KEY, v TEXT NOT NULL)');
        b.execute('''CREATE TABLE plan_days(plan TEXT NOT NULL, day INTEGER NOT NULL, done_at INTEGER NOT NULL,
          PRIMARY KEY(plan, day))''');
        b.execute('''CREATE TABLE translations(code TEXT PRIMARY KEY, name TEXT NOT NULL, abbreviation TEXT NOT NULL,
          license TEXT NOT NULL, installed_at INTEGER NOT NULL)''');
        await b.commit(noResult: true);
      },
    );
    return UserStore._(db, v);
  }

  int _rev = 0;
  int get revision => _rev;
  void _changed() {
    _rev++;
    notifyListeners();
  }

  // ---------------------------------------------------------------- preferences

  Future<Map<String, String>> loadPrefs() async {
    final rows = await db.query('prefs');
    return {for (final r in rows) r['k'] as String: r['v'] as String};
  }

  Future<void> setPref(String k, String v) =>
      db.insert('prefs', {'k': k, 'v': v}, conflictAlgorithm: ConflictAlgorithm.replace);

  // ---------------------------------------------------------------- notes

  Future<Note> createNote({String title = '', String subtitle = '', String body = '', NoteKind kind = NoteKind.general, int? folderId}) async {
    final t = nowMs();
    final id = await db.transaction((tx) async {
      final id = await tx.insert('notes', {
        'uid': newUid(), 'title': title, 'subtitle': subtitle, 'body': body, 'kind': kind.name,
        'folder_id': folderId, 'created_at': t, 'updated_at': t,
      });
      await _writeRefs(tx, id, '$title\n$subtitle\n$body');
      return id;
    });
    _changed();
    return (await note(id))!;
  }

  Future<Note?> note(int id) async {
    final r = await db.query('notes', where: 'id = ?', whereArgs: [id]);
    return r.isEmpty ? null : Note.fromRow(r.first);
  }

  /// Saves the editable fields of a note and its Scripture links in one transaction.
  Future<void> saveNote(int id, {required String title, required String subtitle, required String body}) async {
    await db.transaction((tx) async {
      await tx.update('notes', {'title': title, 'subtitle': subtitle, 'body': body, 'updated_at': nowMs()},
          where: 'id = ?', whereArgs: [id]);
      await _writeRefs(tx, id, '$title\n$subtitle\n$body');
    });
    _changed();
  }

  Future<void> _writeRefs(DatabaseExecutor tx, int id, String text) async {
    await tx.delete('note_refs', where: 'note_id = ?', whereArgs: [id]);
    final seen = <int>{};
    for (final m in findReferences(text, versification)) {
      final r = m.reference;
      if (r == null || !seen.add(r.startId * 7 + r.endId)) continue;
      await tx.insert('note_refs', {'note_id': id, 'start_id': r.startId, 'end_id': r.endId});
    }
  }

  Future<void> updateNoteMeta(int id, {NoteKind? kind, Object? folderId = _keep, bool? pinned, bool? archived}) async {
    final v = <String, Object?>{
      if (kind != null) 'kind': kind.name,
      if (folderId != _keep) 'folder_id': folderId,
      if (pinned != null) 'pinned': pinned ? 1 : 0,
      if (archived != null) 'archived': archived ? 1 : 0,
    };
    if (v.isEmpty) return;
    await db.update('notes', v, where: 'id = ?', whereArgs: [id]);
    _changed();
  }

  Future<Note> duplicateNote(Note n) => createNote(
      title: '${n.displayTitle} (copy)', subtitle: n.subtitle, body: n.body, kind: n.kind, folderId: n.folderId);

  Future<void> trashNote(int id) async {
    await db.update('notes', {'deleted_at': nowMs(), 'pinned': 0}, where: 'id = ?', whereArgs: [id]);
    _changed();
  }

  Future<void> restoreNote(int id) async {
    await db.update('notes', {'deleted_at': null}, where: 'id = ?', whereArgs: [id]);
    _changed();
  }

  Future<void> deleteNoteForever(int id) async {
    await db.delete('notes', where: 'id = ?', whereArgs: [id]);
    _changed();
  }

  Future<void> emptyTrash() async {
    await db.delete('notes', where: 'deleted_at IS NOT NULL');
    _changed();
  }

  /// Notes in the trash for more than 30 days are removed permanently.
  Future<void> purgeOldTrash() async {
    final cutoff = nowMs() - const Duration(days: 30).inMilliseconds;
    final n = await db.delete('notes', where: 'deleted_at IS NOT NULL AND deleted_at < ?', whereArgs: [cutoff]);
    if (n > 0) _changed();
  }

  Future<List<Note>> notes({
    NoteView view = NoteView.active,
    NoteKind? kind,
    int? folderId,
    String query = '',
    NoteSort sort = NoteSort.edited,
    int? limit,
  }) async {
    final where = <String>[];
    final args = <Object?>[];
    switch (view) {
      case NoteView.active:
        where.add('deleted_at IS NULL AND archived = 0');
      case NoteView.archived:
        where.add('deleted_at IS NULL AND archived = 1');
      case NoteView.trash:
        where.add('deleted_at IS NOT NULL');
    }
    if (kind != null) {
      where.add('kind = ?');
      args.add(kind.name);
    }
    if (folderId != null) {
      where.add('folder_id = ?');
      args.add(folderId);
    }
    final q = query.trim();
    if (q.isNotEmpty) {
      where.add("(title LIKE ? ESCAPE '\\' OR subtitle LIKE ? ESCAPE '\\' OR body LIKE ? ESCAPE '\\')");
      final like = '%${q.replaceAll('\\', '\\\\').replaceAll('%', '\\%').replaceAll('_', '\\_')}%';
      args.addAll([like, like, like]);
    }
    final order = switch (sort) {
      NoteSort.edited => 'updated_at DESC',
      NoteSort.created => 'created_at DESC',
      NoteSort.title => "CASE WHEN TRIM(title) = '' THEN 1 ELSE 0 END, title COLLATE NOCASE",
    };
    final rows = await db.query('notes',
        where: where.join(' AND '), whereArgs: args, orderBy: view == NoteView.active ? 'pinned DESC, $order' : order, limit: limit);
    return [for (final r in rows) Note.fromRow(r)];
  }

  /// Notes that mention any verse in the range.
  Future<List<Note>> notesForRange(int startId, int endId) async {
    final rows = await db.rawQuery('''SELECT DISTINCT n.* FROM notes n JOIN note_refs r ON r.note_id = n.id
      WHERE r.start_id <= ? AND r.end_id >= ? AND n.deleted_at IS NULL ORDER BY n.updated_at DESC''', [endId, startId]);
    return [for (final r in rows) Note.fromRow(r)];
  }

  /// Verse ids in [startId, endId] that are referenced by at least one note.
  Future<Set<int>> linkedVerses(int startId, int endId) async {
    final rows = await db.rawQuery('''SELECT r.start_id, r.end_id FROM note_refs r JOIN notes n ON n.id = r.note_id
      WHERE r.start_id <= ? AND r.end_id >= ? AND n.deleted_at IS NULL''', [endId, startId]);
    final out = <int>{};
    for (final r in rows) {
      final s = r['start_id'] as int, e = r['end_id'] as int;
      // Whole-chapter references would mark every verse; only mark verse-level links.
      if (e - s > 200) continue;
      for (var id = s < startId ? startId : s; id <= e && id <= endId; id++) {
        out.add(id);
      }
    }
    return out;
  }

  // ---------------------------------------------------------------- folders

  Future<List<Folder>> folders() async {
    final rows = await db.query('folders', orderBy: 'name COLLATE NOCASE');
    return [for (final r in rows) Folder(r['id'] as int, r['name'] as String)];
  }

  Future<int> createFolder(String name) async {
    final id = await db.insert('folders', {'name': name.trim(), 'created_at': nowMs()},
        conflictAlgorithm: ConflictAlgorithm.ignore);
    _changed();
    if (id <= 0) {
      final r = await db.query('folders', where: 'name = ?', whereArgs: [name.trim()]);
      return r.first['id'] as int;
    }
    return id;
  }

  Future<void> renameFolder(int id, String name) async {
    await db.update('folders', {'name': name.trim()}, where: 'id = ?', whereArgs: [id]);
    _changed();
  }

  Future<void> deleteFolder(int id) async {
    await db.delete('folders', where: 'id = ?', whereArgs: [id]);
    _changed();
  }

  // ---------------------------------------------------------------- bookmarks & highlights

  Future<Bookmark> addBookmark(int startId, int endId, {String comment = ''}) async {
    final existing = await db.query('bookmarks', where: 'start_id = ? AND end_id = ?', whereArgs: [startId, endId]);
    if (existing.isNotEmpty) return _bookmark(existing.first);
    final t = nowMs();
    final uid = newUid();
    final id = await db.insert('bookmarks',
        {'uid': uid, 'start_id': startId, 'end_id': endId, 'comment': comment, 'created_at': t, 'updated_at': t});
    _changed();
    return Bookmark(id, uid, startId, endId, comment, t, t);
  }

  Bookmark _bookmark(Map<String, Object?> r) => Bookmark(r['id'] as int, r['uid'] as String, r['start_id'] as int,
      r['end_id'] as int, r['comment'] as String, r['created_at'] as int, r['updated_at'] as int);

  Future<void> updateBookmarkComment(int id, String comment) async {
    await db.update('bookmarks', {'comment': comment, 'updated_at': nowMs()}, where: 'id = ?', whereArgs: [id]);
    _changed();
  }

  Future<void> deleteBookmark(int id) async {
    await db.delete('bookmarks', where: 'id = ?', whereArgs: [id]);
    _changed();
  }

  Future<List<Bookmark>> bookmarks({String query = ''}) async {
    final rows = await db.query('bookmarks', orderBy: 'created_at DESC');
    final all = [for (final r in rows) _bookmark(r)];
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return all;
    return all.where((b) => b.comment.toLowerCase().contains(q) || b.reference.label.toLowerCase().contains(q)).toList();
  }

  /// Bookmarks that overlap the given verse range.
  Future<List<Bookmark>> bookmarksIn(int startId, int endId) async {
    final rows = await db.query('bookmarks', where: 'start_id <= ? AND end_id >= ?', whereArgs: [endId, startId]);
    return [for (final r in rows) _bookmark(r)];
  }

  Future<void> setHighlight(Iterable<int> verseIds, int? color) async {
    final b = db.batch();
    for (final id in verseIds) {
      if (color == null) {
        b.delete('highlights', where: 'verse_id = ?', whereArgs: [id]);
      } else {
        b.insert('highlights', {'verse_id': id, 'color': color, 'created_at': nowMs()},
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }
    await b.commit(noResult: true);
    _changed();
  }

  Future<Map<int, int>> highlightsIn(int startId, int endId) async {
    final rows = await db.query('highlights', where: 'verse_id BETWEEN ? AND ?', whereArgs: [startId, endId]);
    return {for (final r in rows) r['verse_id'] as int: r['color'] as int};
  }

  Future<List<Highlight>> highlights() async {
    final rows = await db.query('highlights', orderBy: 'created_at DESC, verse_id');
    return [for (final r in rows) Highlight(r['verse_id'] as int, r['color'] as int, r['created_at'] as int)];
  }

  // ---------------------------------------------------------------- reading history

  Future<void> recordReading(int book, int chapter, int verse) async {
    await db.insert('history', {'chapter_key': book * 1000 + chapter, 'verse': verse, 'opened_at': nowMs()},
        conflictAlgorithm: ConflictAlgorithm.replace);
    await db.execute('DELETE FROM history WHERE chapter_key NOT IN (SELECT chapter_key FROM history ORDER BY opened_at DESC LIMIT 100)');
    _changed();
  }

  Future<List<HistoryEntry>> history({int limit = 100}) async {
    final rows = await db.query('history', orderBy: 'opened_at DESC', limit: limit);
    return [for (final r in rows) HistoryEntry(r['chapter_key'] as int, r['verse'] as int, r['opened_at'] as int)];
  }

  Future<void> clearHistory() async {
    await db.delete('history');
    _changed();
  }

  // ---------------------------------------------------------------- reading plans

  Future<Set<int>> planDaysDone(String plan) async {
    final rows = await db.query('plan_days', columns: ['day'], where: 'plan = ?', whereArgs: [plan]);
    return {for (final r in rows) r['day'] as int};
  }

  Future<void> setPlanDay(String plan, int day, bool done) async {
    if (done) {
      await db.insert('plan_days', {'plan': plan, 'day': day, 'done_at': nowMs()}, conflictAlgorithm: ConflictAlgorithm.replace);
    } else {
      await db.delete('plan_days', where: 'plan = ? AND day = ?', whereArgs: [plan, day]);
    }
    _changed();
  }

  Future<void> resetPlan(String plan) async {
    await db.delete('plan_days', where: 'plan = ?', whereArgs: [plan]);
    _changed();
  }

  // ---------------------------------------------------------------- translations

  Future<List<Translation>> installedTranslations() async {
    final rows = await db.query('translations', orderBy: 'installed_at');
    return [webTranslation, for (final r in rows) Translation.fromJson(r)];
  }

  Future<void> registerTranslation(Translation t) async {
    await db.insert('translations', {...t.toJson(), 'installed_at': nowMs()}, conflictAlgorithm: ConflictAlgorithm.replace);
    _changed();
  }

  Future<void> unregisterTranslation(String code) async {
    await db.delete('translations', where: 'code = ?', whereArgs: [code]);
    _changed();
  }

  // ---------------------------------------------------------------- backup & restore

  Future<Map<String, Object?>> exportBackup() async {
    final folders = await db.query('folders');
    final notes = await db.query('notes');
    final bookmarks = await db.query('bookmarks');
    final highlights = await db.query('highlights');
    final plans = await db.query('plan_days');
    final prefs = await loadPrefs();
    final folderNames = {for (final f in folders) f['id']: f['name']};
    return {
      'format': backupFormat,
      'version': 1,
      'app': 'Bible by Cue',
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'folders': [for (final f in folders) f['name']],
      'notes': [
        for (final n in notes)
          {
            'uid': n['uid'], 'title': n['title'], 'subtitle': n['subtitle'], 'body': n['body'], 'kind': n['kind'],
            'folder': folderNames[n['folder_id']], 'pinned': n['pinned'] == 1, 'archived': n['archived'] == 1,
            'deleted_at': n['deleted_at'], 'created_at': n['created_at'], 'updated_at': n['updated_at'],
          }
      ],
      'bookmarks': [
        for (final b in bookmarks)
          {
            'uid': b['uid'], 'reference': Reference.fromIds(b['start_id'] as int, b['end_id'] as int).label,
            'start': b['start_id'], 'end': b['end_id'], 'comment': b['comment'],
            'created_at': b['created_at'], 'updated_at': b['updated_at'],
          }
      ],
      'highlights': [
        for (final h in highlights) {'verse': h['verse_id'], 'color': h['color'], 'created_at': h['created_at']}
      ],
      'plans': [for (final d in plans) {'plan': d['plan'], 'day': d['day'], 'done_at': d['done_at']}],
      'settings': prefs,
    };
  }

  static Map<String, Object?> decodeBackup(String json) {
    final Object? data;
    try {
      data = jsonDecode(json);
    } on FormatException {
      throw const FormatException('This file is not a Bible by Cue backup (it is not valid JSON).');
    }
    if (data is! Map<String, Object?> || data['format'] != backupFormat) {
      throw const FormatException('This file is not a Bible by Cue backup.');
    }
    if ((data['version'] as int? ?? 0) > 1) {
      throw const FormatException('This backup was made by a newer version of Bible by Cue.');
    }
    return data;
  }

  static BackupSummary summarize(Map<String, Object?> b) => BackupSummary(
        (b['notes'] as List? ?? const []).length,
        (b['bookmarks'] as List? ?? const []).length,
        (b['highlights'] as List? ?? const []).length,
        (b['folders'] as List? ?? const []).length,
        DateTime.tryParse(b['exported_at'] as String? ?? '')?.toLocal(),
      );

  /// Writes an automatic safety copy of current data before a destructive restore.
  Future<String> writeSafetyBackup() async {
    final dir = Directory(p.join(await getDatabasesPath(), 'safety_backups'));
    await dir.create(recursive: true);
    final name = 'before-restore-${DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first}.json';
    final file = File(p.join(dir.path, name));
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(await exportBackup()), flush: true);
    await tmp.rename(file.path);
    final all = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    for (final old in all.skip(5)) {
      await old.delete();
    }
    return name;
  }

  /// Restores a backup in a single transaction.
  ///
  /// With [replace] false (merge) nothing on this device is deleted or overwritten: new items are
  /// added, and a note that differs from its local version is added as a separate copy.
  /// With [replace] true, current data is first saved to a safety backup, then replaced.
  Future<RestoreReport> restoreBackup(Map<String, Object?> b, {required bool replace, bool restoreSettings = false}) async {
    final report = RestoreReport();
    if (replace) report.safetyBackup = await writeSafetyBackup();
    await db.transaction((tx) async {
      if (replace) {
        for (final t in ['note_refs', 'notes', 'folders', 'bookmarks', 'highlights', 'plan_days']) {
          await tx.delete(t);
        }
      }
      final folderIds = <String, int>{};
      for (final r in await tx.query('folders')) {
        folderIds[r['name'] as String] = r['id'] as int;
      }
      Future<int?> folderFor(Object? name) async {
        if (name is! String || name.trim().isEmpty) return null;
        final existing = folderIds[name];
        if (existing != null) return existing;
        final id = await tx.insert('folders', {'name': name, 'created_at': nowMs()});
        report.foldersAdded++;
        return folderIds[name] = id;
      }

      for (final name in (b['folders'] as List? ?? const [])) {
        await folderFor(name);
      }
      for (final raw in (b['notes'] as List? ?? const [])) {
        final n = (raw as Map).cast<String, Object?>();
        final uid = n['uid'] as String? ?? newUid();
        final local = await tx.query('notes', where: 'uid = ?', whereArgs: [uid]);
        var row = <String, Object?>{
          'uid': uid,
          'title': n['title'] as String? ?? '',
          'subtitle': n['subtitle'] as String? ?? '',
          'body': n['body'] as String? ?? '',
          'kind': NoteKind.parse(n['kind'] as String?).name,
          'folder_id': await folderFor(n['folder']),
          'pinned': n['pinned'] == true ? 1 : 0,
          'archived': n['archived'] == true ? 1 : 0,
          'deleted_at': n['deleted_at'] as int?,
          'created_at': n['created_at'] as int? ?? nowMs(),
          'updated_at': n['updated_at'] as int? ?? nowMs(),
        };
        if (local.isNotEmpty) {
          final l = local.first;
          if (l['title'] == row['title'] && l['subtitle'] == row['subtitle'] && l['body'] == row['body']) {
            report.notesSkipped++;
            continue;
          }
          row = {...row, 'uid': newUid(), 'title': '${row['title'] == '' ? 'Untitled note' : row['title']} (from backup)'};
          report.notesCopied++;
        } else {
          report.notesAdded++;
        }
        final id = await tx.insert('notes', row);
        await _writeRefs(tx, id, '${row['title']}\n${row['subtitle']}\n${row['body']}');
      }
      for (final raw in (b['bookmarks'] as List? ?? const [])) {
        final m = (raw as Map).cast<String, Object?>();
        final start = m['start'] as int?, end = m['end'] as int?;
        if (start == null || end == null) continue;
        final uid = m['uid'] as String? ?? newUid();
        final dup = await tx.query('bookmarks',
            where: 'uid = ? OR (start_id = ? AND end_id = ? AND comment = ?)', whereArgs: [uid, start, end, m['comment'] ?? '']);
        if (dup.isNotEmpty) {
          report.bookmarksSkipped++;
          continue;
        }
        await tx.insert('bookmarks', {
          'uid': uid, 'start_id': start, 'end_id': end, 'comment': m['comment'] as String? ?? '',
          'created_at': m['created_at'] as int? ?? nowMs(), 'updated_at': m['updated_at'] as int? ?? nowMs(),
        });
        report.bookmarksAdded++;
      }
      for (final raw in (b['highlights'] as List? ?? const [])) {
        final m = (raw as Map).cast<String, Object?>();
        final id = await tx.insert('highlights',
            {'verse_id': m['verse'], 'color': m['color'], 'created_at': m['created_at'] ?? nowMs()},
            conflictAlgorithm: ConflictAlgorithm.ignore);
        if (id <= 0) {
          report.highlightsKept++;
        } else {
          report.highlightsAdded++;
        }
      }
      for (final raw in (b['plans'] as List? ?? const [])) {
        final m = (raw as Map).cast<String, Object?>();
        await tx.insert('plan_days', {'plan': m['plan'], 'day': m['day'], 'done_at': m['done_at'] ?? nowMs()},
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      if (restoreSettings && b['settings'] is Map) {
        for (final e in (b['settings'] as Map).entries) {
          await tx.insert('prefs', {'k': '${e.key}', 'v': '${e.value}'}, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        report.settingsRestored = true;
      }
    });
    _changed();
    return report;
  }

  Future<int> fileSize() async {
    final path = db.path;
    var total = 0;
    for (final f in [path, '$path-wal', '$path-shm']) {
      final file = File(f);
      if (await file.exists()) total += await file.length();
    }
    return total;
  }
}

const _keep = Object();

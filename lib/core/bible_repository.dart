import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'books.dart';
import 'reference.dart';

/// An installed (or installable) Bible translation. Each translation lives in its own
/// database file so that user data and Scripture text never mix.
class Translation {
  final String code;
  final String name;
  final String abbreviation;
  final String license;
  final bool builtIn;

  const Translation(this.code, this.name, this.abbreviation, this.license, {this.builtIn = false});

  String get fileName => 'bible_$code.db';

  Map<String, Object?> toJson() => {'code': code, 'name': name, 'abbreviation': abbreviation, 'license': license};

  factory Translation.fromJson(Map<String, Object?> j) =>
      Translation(j['code'] as String, j['name'] as String, j['abbreviation'] as String, j['license'] as String);
}

const webTranslation = Translation(
  'web',
  'World English Bible',
  'WEB',
  'Public domain. "World English Bible" is a trademark of eBible.org; this text is unmodified (2020 stable edition).',
  builtIn: true,
);

class Verse {
  final int id;
  final String text;
  const Verse(this.id, this.text);
  int get book => bookOf(id);
  int get chapter => chapterOf(id);
  int get number => verseOf(id);
}

class SearchResults {
  final int total;
  final List<Verse> verses;
  const SearchResults(this.total, this.verses);
}

class CrossReference {
  final int start;
  final int end;
  const CrossReference(this.start, this.end);
  Reference get reference => Reference.fromIds(start, end);
}

/// SQL-safe search text: everything except letters and digits becomes a space so that
/// "God’s" indexes as "god" + "s" and curly quotes never block a match.
String searchNormalize(String s) => s.replaceAll(RegExp(r'[^A-Za-z0-9]+'), ' ').trim().toLowerCase();

const _vplCodes = [
  'GEN', 'EXO', 'LEV', 'NUM', 'DEU', 'JOS', 'JDG', 'RUT', '1SA', '2SA', '1KI', '2KI', '1CH', '2CH', 'EZR', 'NEH', //
  'EST', 'JOB', 'PSA', 'PRO', 'ECC', 'SOL', 'ISA', 'JER', 'LAM', 'EZE', 'DAN', 'HOS', 'JOE', 'AMO', 'OBA', 'JON', //
  'MIC', 'NAH', 'HAB', 'ZEP', 'HAG', 'ZEC', 'MAL', 'MAT', 'MAR', 'LUK', 'JOH', 'ACT', 'ROM', '1CO', '2CO', 'GAL', //
  'EPH', 'PHI', 'COL', '1TH', '2TH', '1TI', '2TI', 'TIT', 'PHM', 'HEB', 'JAM', '1PE', '2PE', '1JO', '2JO', '3JO', //
  'JUD', 'REV',
];
// Alternate USFM/SIL codes used by some VPL exports.
const _altCodes = {'SNG': 22, 'EZK': 26, 'JOL': 29, 'NAM': 34, 'MRK': 41, 'JHN': 43, 'PHP': 50, 'JAS': 59, 'JDE': 65};

/// Parses verse-per-line text. Accepts the bundled "id TAB text" form and the common
/// eBible.org VPL form "JHN 3:16 For God so loved…". Lines outside the 66 books are skipped.
List<Verse> parseVerseLines(String data) {
  final out = <Verse>[];
  final vpl = RegExp(r'^\s*([1-3]?[A-Z]{2,3})\s+(\d{1,3}):(\d{1,3})\s+(.*)$');
  for (final line in const LineSplitter().convert(data)) {
    if (line.trim().isEmpty) continue;
    final tab = line.indexOf('\t');
    if (tab > 0) {
      final id = int.tryParse(line.substring(0, tab));
      if (id != null) {
        final t = line.substring(tab + 1).trim();
        if (t.isNotEmpty && bookOf(id) >= 1 && bookOf(id) <= 66) out.add(Verse(id, t));
        continue;
      }
    }
    final m = vpl.firstMatch(line);
    if (m == null) continue;
    final code = m[1]!.toUpperCase();
    final idx = _vplCodes.indexOf(code);
    final book = idx >= 0 ? idx + 1 : _altCodes[code];
    final text = m[4]!.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (book == null || text.isEmpty) continue;
    out.add(Verse(verseId(book, int.parse(m[2]!), int.parse(m[3]!)), text));
  }
  return out;
}

class BibleRepository implements Versification {
  final Translation translation;
  final Database _db;
  final Map<int, int> _maxVerse;
  final String path;

  /// Number of verses actually present (some translations omit verses on textual grounds).
  final int verseCount;

  BibleRepository._(this.translation, this._db, this._maxVerse, this.path, this.verseCount);

  static Future<String> _pathFor(Translation t) async => p.join(await getDatabasesPath(), t.fileName);

  static Future<bool> isInstalled(Translation t) async => File(await _pathFor(t)).exists();

  /// Opens the translation, building its database first if this is the first launch.
  static Future<BibleRepository> open(Translation t, {void Function(double progress)? onProgress}) async {
    final path = await _pathFor(t);
    if (!await File(path).exists()) {
      if (!t.builtIn) throw StateError('${t.name} is not installed');
      await _installBundled(path, onProgress);
    }
    final db = await openReadOnlyDatabase(path, singleInstance: true);
    final rows = await db.rawQuery('SELECT id / 1000 AS k, MAX(id % 1000) AS m FROM verses GROUP BY k');
    final maxVerse = {for (final r in rows) r['k'] as int: r['m'] as int};
    final count = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM verses')) ?? 0;
    onProgress?.call(1);
    return BibleRepository._(t, db, maxVerse, path, count);
  }

  /// Installs a translation from verse-per-line text supplied by the user.
  static Future<int> install(Translation t, String data, {void Function(double)? onProgress}) async {
    final verses = parseVerseLines(data);
    final bookCount = verses.map((v) => v.book).toSet().length;
    if (verses.length < 1000 || bookCount < 2) {
      throw const FormatException('This file does not look like a verse-per-line Bible text.');
    }
    final path = await _pathFor(t);
    if (await File(path).exists()) throw StateError('A translation with this code is already installed.');
    await _build(path, verses, null, onProgress);
    return verses.length;
  }

  /// Unpacks the bundled database (verses and cross references) and builds its search index with
  /// native SQL, so nothing passes through the platform channel row by row. Work happens in a
  /// temporary file that is renamed only when complete.
  static Future<void> _installBundled(String path, void Function(double)? onProgress) async {
    final clock = Stopwatch()..start();
    onProgress?.call(0.05);
    final tmp = '$path.tmp';
    await deleteDatabase(tmp);
    final raw = await rootBundle.load('assets/bible/web.db.gz');
    final bytes = gzip.decode(raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes));
    await File(tmp).writeAsBytes(bytes, flush: true);
    debugPrint('[cue-build] unpacked ${clock.elapsedMilliseconds} ms');
    onProgress?.call(0.25);
    final db = await openDatabase(tmp, singleInstance: false);
    try {
      await db.rawQuery('PRAGMA journal_mode=OFF');
      await db.execute('PRAGMA synchronous=OFF');
      await db.execute('CREATE INDEX IF NOT EXISTS xref_f ON xref(f)');
      onProgress?.call(0.35);
      await db.execute('CREATE VIRTUAL TABLE fts USING fts4(content="", t)');
      // The simple tokenizer already splits on ASCII punctuation; map the typographic quotes and
      // dashes used by the text to spaces so "God’s" indexes as "god" + "s", like searchNormalize.
      var expr = 't';
      for (final c in const ['–', '—', '‘', '’', '“', '”']) {
        expr = "replace($expr, '$c', ' ')";
      }
      await db.execute('INSERT INTO fts(docid, t) SELECT id, $expr FROM verses');
      debugPrint('[cue-build] indexed ${clock.elapsedMilliseconds} ms');
      onProgress?.call(0.9);
      await db.execute("INSERT INTO fts(fts) VALUES('optimize')");
      debugPrint('[cue-build] optimized ${clock.elapsedMilliseconds} ms');
    } catch (_) {
      await db.close();
      await deleteDatabase(tmp);
      rethrow;
    }
    await db.close();
    await File(tmp).rename(path);
  }

  static Future<void> uninstall(Translation t) async {
    final path = await _pathFor(t);
    await deleteDatabase(path);
  }

  /// Builds into a temporary file and renames it only when complete, so an interrupted
  /// first launch can never leave a partial Bible behind.
  static Future<void> _build(String path, List<Verse> verses, Uint8List? xref, void Function(double)? onProgress) async {
    final tmp = '$path.tmp';
    final clock = Stopwatch()..start();
    void mark(String step) {
      debugPrint('[cue-build] $step ${clock.elapsedMilliseconds} ms');
    }
    await deleteDatabase(tmp);
    final db = await openDatabase(tmp, singleInstance: false);
    try {
      await db.rawQuery('PRAGMA journal_mode=OFF');
      await db.execute('PRAGMA synchronous=OFF');
      await db.execute('CREATE TABLE verses(id INTEGER PRIMARY KEY, t TEXT NOT NULL)');
      await db.execute('CREATE VIRTUAL TABLE fts USING fts4(content="", t)');
      await db.execute('CREATE TABLE xref(f INTEGER NOT NULL, s INTEGER NOT NULL, e INTEGER NOT NULL)');
      await db.execute('CREATE TABLE meta(k TEXT PRIMARY KEY, v TEXT)');
      const chunk = 400;
      final seen = <int>{};
      final unique = [for (final v in verses) if (seen.add(v.id)) v];
      for (var i = 0; i < unique.length; i += chunk) {
        final part = unique.sublist(i, i + chunk > unique.length ? unique.length : i + chunk);
        final marks = List.filled(part.length, '(?,?)').join(',');
        final batch = db.batch();
        batch.rawInsert('INSERT INTO verses(id, t) VALUES $marks', [for (final v in part) ...[v.id, v.text]]);
        batch.rawInsert('INSERT INTO fts(docid, t) VALUES $marks',
            [for (final v in part) ...[v.id, searchNormalize(v.text)]]);
        await batch.commit(noResult: true);
        onProgress?.call(0.05 + 0.75 * (i + part.length) / unique.length);
      }
      mark('verses+fts inserted');
      if (xref != null) {
        final data = ByteData.sublistView(xref);
        final n = xref.length ~/ 12;
        const rowsPer = 330;
        var batch = db.batch();
        for (var i = 0; i < n; i += rowsPer) {
          final m = (i + rowsPer > n ? n : i + rowsPer) - i;
          final args = <int>[];
          for (var k = i; k < i + m; k++) {
            args
              ..add(data.getUint32(k * 12, Endian.little))
              ..add(data.getUint32(k * 12 + 4, Endian.little))
              ..add(data.getUint32(k * 12 + 8, Endian.little));
          }
          batch.rawInsert('INSERT INTO xref VALUES ${List.filled(m, '(?,?,?)').join(',')}', args);
          if ((i ~/ rowsPer) % 40 == 39) {
            await batch.commit(noResult: true);
            batch = db.batch();
            onProgress?.call(0.80 + 0.12 * i / n);
          }
        }
        await batch.commit(noResult: true);
      }
      mark('xref inserted');
      await db.execute('CREATE INDEX xref_f ON xref(f)');
      mark('xref indexed');
      await db.execute("INSERT INTO fts(fts) VALUES('optimize')");
      mark('fts optimized');
      await db.insert('meta', {'k': 'verses', 'v': '${unique.length}'});
      onProgress?.call(0.96);
    } catch (_) {
      await db.close();
      await deleteDatabase(tmp);
      rethrow;
    }
    await db.close();
    await File(tmp).rename(path);
  }

  Future<void> close() => _db.close();

  @override
  int? maxVerse(int book, int chapter) => _maxVerse[book * 1000 + chapter];

  @override
  int chapterCount(int book) {
    var c = bookByNumber(book).chapters;
    while (c > 1 && !_maxVerse.containsKey(book * 1000 + c)) {
      c--;
    }
    return c;
  }

  bool hasBook(int book) => _maxVerse.containsKey(book * 1000 + 1);

  Future<List<Verse>> range(int startId, int endId) async {
    final rows = await _db.rawQuery('SELECT id, t FROM verses WHERE id BETWEEN ? AND ? ORDER BY id', [startId, endId]);
    return [for (final r in rows) Verse(r['id'] as int, r['t'] as String)];
  }

  Future<List<Verse>> chapter(int book, int chapter) =>
      range(verseId(book, chapter, 0), verseId(book, chapter, 999));

  Future<List<Verse>> passage(Reference r) => range(r.startId, r.endId);

  Future<Verse?> verse(int id) async {
    final v = await range(id, id);
    return v.isEmpty ? null : v.first;
  }

  Future<List<Verse>> verses(Iterable<int> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return const [];
    final rows = await _db.rawQuery(
        'SELECT id, t FROM verses WHERE id IN (${List.filled(list.length, '?').join(',')}) ORDER BY id', list);
    return [for (final r in rows) Verse(r['id'] as int, r['t'] as String)];
  }

  Future<List<CrossReference>> crossReferences(int id) async {
    final rows = await _db.rawQuery('SELECT s, e FROM xref WHERE f = ?', [id]);
    return [for (final r in rows) CrossReference(r['s'] as int, r['e'] as int)];
  }

  Future<int> fileSize() async => File(path).length();

  /// Full-text search using the local FTS4 index. [book] or [testament] (1 = OT, 2 = NT) narrow the scope.
  Future<SearchResults> search(String query, {bool exactPhrase = false, int? book, int? testament, int limit = 300}) async {
    final terms = searchNormalize(query).split(' ').where((w) => w.isNotEmpty).toList();
    if (terms.isEmpty) return const SearchResults(0, []);
    final match = exactPhrase ? '"${terms.join(' ')}"' : terms.join(' ');
    var lo = verseId(1, 0, 0), hi = verseId(66, 999, 999);
    if (book != null) {
      lo = verseId(book, 0, 0);
      hi = verseId(book, 999, 999);
    } else if (testament == 1) {
      hi = verseId(39, 999, 999);
    } else if (testament == 2) {
      lo = verseId(40, 0, 0);
    }
    final rows = await _db.rawQuery(
        'SELECT docid FROM fts WHERE fts MATCH ? AND docid BETWEEN ? AND ? ORDER BY docid', [match, lo, hi]);
    final ids = [for (final r in rows) r['docid'] as int];
    final first = ids.take(limit).toList();
    final verses = <Verse>[];
    for (var i = 0; i < first.length; i += 500) {
      verses.addAll(await this.verses(first.sublist(i, i + 500 > first.length ? first.length : i + 500)));
    }
    return SearchResults(ids.length, verses);
  }
}

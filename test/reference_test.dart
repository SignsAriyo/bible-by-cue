import 'dart:convert';
import 'dart:io';

import 'package:bible_by_cue/core/books.dart';
import 'package:bible_by_cue/core/content.dart';
import 'package:bible_by_cue/core/reference.dart';
import 'package:flutter_test/flutter_test.dart';

class AssetVersification implements Versification {
  final Map<int, int> max = {};
  AssetVersification() {
    final lines = const LineSplitter()
        .convert(utf8.decode(gzip.decode(File('tools/data/web.txt.gz').readAsBytesSync())));
    for (final l in lines) {
      final id = int.parse(l.substring(0, l.indexOf('\t')));
      final k = id ~/ 1000;
      final v = id % 1000;
      if ((max[k] ?? 0) < v) max[k] = v;
    }
  }
  @override
  int? maxVerse(int book, int chapter) => max[book * 1000 + chapter];
  @override
  int chapterCount(int book) => bookByNumber(book).chapters;
}

void main() {
  final v = AssetVersification();
  List<String> labels(String s) => [for (final m in findReferences(s, v)) if (m.isValid) m.reference!.label];
  List<String> spans(String s) => [for (final m in findReferences(s, v)) s.substring(m.start, m.end)];

  test('book metadata matches the bundled translation', () {
    var chapters = 0;
    for (final b in books) {
      chapters += b.chapters;
      expect(v.maxVerse(b.number, b.chapters), isNotNull, reason: b.name);
      expect(v.maxVerse(b.number, b.chapters + 1), isNull, reason: b.name);
    }
    expect(chapters, 1189);
  });

  test('recognises the required reference forms', () {
    expect(labels('John 3:16'), ['John 3:16']);
    expect(labels('Romans 8:28–30'), ['Romans 8:28–30']);
    expect(labels('Psalm 23'), ['Psalm 23']);
    expect(labels('Genesis 1:1'), ['Genesis 1:1']);
    expect(labels('1 Corinthians 13:4–7'), ['1 Corinthians 13:4–7']);
    expect(labels('Song of Solomon 2:1'), ['Song of Solomon 2:1']);
    expect(labels('1 Cor. 13:4–7'), ['1 Corinthians 13:4–7']);
    expect(labels('John 3:16–18'), ['John 3:16–18']);
    expect(labels('Jn 3:16-4:2'), ['John 3:16–4:2']);
    expect(labels('II Kings 2:11'), ['2 Kings 2:11']);
    expect(labels('First John 1:9'), ['1 John 1:9']);
    expect(labels('1Cor 13:4'), ['1 Corinthians 13:4']);
    expect(labels('Jude 3'), ['Jude 1:3']);
    expect(labels('Ps. 119'), ['Psalm 119']);
    expect(labels('Song of Songs 2:1'), ['Song of Solomon 2:1']);
    expect(labels('john 3:16'), ['John 3:16']);
    expect(labels('John 3:16a'), ['John 3:16']);
  });

  test('finds multiple references with punctuation in prose', () {
    const note = "God's grace is sufficient for us. See 2 Corinthians 12:9. We must learn to trust Him "
        'even in difficult seasons. Read Romans 8:28 as well.';
    expect(labels(note), ['2 Corinthians 12:9', 'Romans 8:28']);
    expect(spans(note), ['2 Corinthians 12:9', 'Romans 8:28']);
    const testB = 'God is faithful. See John 3:16 and Romans 8:28–30. Read 1 Corinthians 13:4–7 for further study.';
    expect(labels(testB), ['John 3:16', 'Romans 8:28–30', '1 Corinthians 13:4–7']);
    expect(labels('# Main text: Ephesians 2:8-9\n- see (Heb 11:1), and Isa 40:31!'),
        ['Ephesians 2:8–9', 'Hebrews 11:1', 'Isaiah 40:31']);
  });

  test('avoids false positives in ordinary text', () {
    for (final s in [
      'Service starts at 10:30 on Sunday.',
      'Point 1: grace. Point 2: faith.',
      'We met on 12/05/2024 and 3 people came.',
      'He acts 3 times a day.',
      'Is 5 enough for the group?',
      'MARK 2 people as present',
      'I mark 4 places on the map',
      'the job 3 days ago',
      'Mark 3rd place',
      'Gen Z 3 times',
      'i am 25 years old',
      'AM 10:30 meeting',
    ]) {
      expect(findReferences(s, v), isEmpty, reason: s);
    }
  });

  test('flags references to chapters and verses that do not exist', () {
    final m = findReferences('See Psalm 151 and John 3:99 and Jude 2:1 and Romans 8:30-28', v);
    expect(m.length, 4);
    expect(m.every((x) => !x.isValid), isTrue);
    expect(m[0].error, 'Psalms has 150 chapters');
    expect(m[1].error, 'John 3 has 36 verses');
    expect(m[2].error, 'Jude has only one chapter');
    expect(m[3].error, 'The range ends before it starts');
  });

  test('parses typed navigation queries leniently', () {
    expect(parseQuery('jn 3 16', v).reference?.label, 'John 3:16');
    expect(parseQuery('rom 8:28-30', v).reference?.label, 'Romans 8:28–30');
    expect(parseQuery('psalm 23', v).reference?.label, 'Psalm 23');
    expect(parseQuery('song of solomon 2:1', v).reference?.label, 'Song of Solomon 2:1');
    expect(parseQuery('1 corinthians 13:4–7', v).reference?.label, '1 Corinthians 13:4–7');
    expect(parseQuery('mark 4', v).reference?.label, 'Mark 4');
    expect(parseQuery('genesis', v).book?.name, 'Genesis');
    expect(parseQuery('Genesis 51', v).error, isNotNull);
    expect(parseQuery('hello world', v).reference, isNull);
    expect(suggestBooks('jo').map((b) => b.name), containsAll(['Joshua', 'Job', 'Joel', 'John']));
  });

  test('reference ids cover the expected verses', () {
    final r = parseQuery('Psalm 23', v).reference!;
    expect(r.startId, verseId(19, 23, 1));
    expect(r.endId, verseId(19, 23, 999));
    final s = Reference.fromIds(verseId(43, 3, 16), verseId(43, 3, 18));
    expect(s.label, 'John 3:16–18');
  });

  test('every verse-of-the-day reference exists in the bundled translation', () {
    for (final r in dailyVerseRefs) {
      expect(parseQuery(r, v).reference, isNotNull, reason: r);
    }
  });

  test('reading plans cover their chapters exactly once', () {
    for (final plan in ReadingPlan.all) {
      final all = [for (var d = 0; d < plan.days; d++) ...plan.chaptersForDay(d)];
      expect(all, plan.chapters, reason: plan.id);
      expect(plan.chaptersForDay(0), isNotEmpty);
    }
    expect(describeChapters([1001, 1002, 1003]), 'Genesis 1–3');
  });
}

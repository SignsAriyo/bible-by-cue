import 'package:bible_by_cue/core/bible_repository.dart';
import 'package:bible_by_cue/core/books.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses eBible.org VPL lines, including alternate book codes', () {
    final verses = parseVerseLines('''
GEN 1:1 In the beginning God created the heaven and the earth.
JHN 3:16 For God so loved the world,   that he gave his only begotten Son.
JOH 3:17 For God sent not his Son into the world to condemn the world.
TOB 1:1 Deuterocanonical lines are skipped.
not a verse line
REV 22:21 The grace of our Lord Jesus Christ be with you all. Amen.
''');
    expect(verses.map((v) => v.id), [verseId(1, 1, 1), verseId(43, 3, 16), verseId(43, 3, 17), verseId(66, 22, 21)]);
    expect(verses[1].text, 'For God so loved the world, that he gave his only begotten Son.');
  });

  test('parses the id-tab-text form', () {
    final verses = parseVerseLines('43003016\tFor God so loved the world\n99001001\tout of range\n');
    expect(verses.single.id, verseId(43, 3, 16));
  });

  test('search normalisation matches the index tokenizer', () {
    expect(searchNormalize('God’s “love”—forever!'), 'god s love forever');
  });
}

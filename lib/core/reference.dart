import 'books.dart';

/// Supplies the real chapter/verse structure of the installed translation so
/// references can be validated rather than trusted.
abstract class Versification {
  /// Highest verse number in [chapter] of [book], or null when the chapter does not exist.
  int? maxVerse(int book, int chapter);

  int chapterCount(int book);
}

/// Versification derived only from book metadata (chapter counts); verses are unchecked.
class LooseVersification implements Versification {
  const LooseVersification();
  @override
  int? maxVerse(int book, int chapter) =>
      chapter >= 1 && chapter <= bookByNumber(book).chapters ? 999 : null;
  @override
  int chapterCount(int book) => bookByNumber(book).chapters;
}

/// A contiguous passage: a single verse, a verse range, a whole chapter or a chapter range.
class Reference {
  final int book;
  final int chapter;
  final int? verse;
  final int endChapter;
  final int? endVerse;

  const Reference(this.book, this.chapter, [this.verse, int? endChapter, this.endVerse])
      : endChapter = endChapter ?? chapter;

  factory Reference.fromIds(int start, int end) {
    final single = start == end;
    return Reference(bookOf(start), chapterOf(start), verseOf(start), chapterOf(end), single ? null : verseOf(end))
        ._normalized();
  }

  Reference _normalized() {
    if (endVerse != null && endChapter == chapter && endVerse == verse) {
      return Reference(book, chapter, verse);
    }
    return this;
  }

  bool get isWholeChapter => verse == null;
  bool get isSingleVerse => verse != null && endChapter == chapter && (endVerse == null || endVerse == verse);

  int get startId => verseId(book, chapter, verse ?? 1);
  int get endId {
    if (verse == null) return verseId(book, endChapter, endVerse ?? 999);
    return verseId(book, endChapter, endVerse ?? verse!);
  }

  Book get bookInfo => bookByNumber(book);

  String get bookLabel {
    if (book == 19 && chapter == endChapter && verse == null) return 'Psalm';
    if (book == 19 && isSingleVerse) return 'Psalm';
    return bookInfo.name;
  }

  String get label {
    final b = bookLabel;
    if (verse == null) {
      if (endChapter != chapter) {
        return endVerse != null ? '$b $chapter–$endChapter:$endVerse' : '$b $chapter–$endChapter';
      }
      return '$b $chapter';
    }
    if (endChapter != chapter) return '$b $chapter:$verse–$endChapter:${endVerse ?? 1}';
    if (endVerse != null && endVerse != verse) return '$b $chapter:$verse–$endVerse';
    return '$b $chapter:$verse';
  }

  /// Short form used in compact chips, e.g. "1 Cor 13:4–7".
  String get shortLabel => label.replaceFirst(bookLabel, bookInfo.short);

  @override
  bool operator ==(Object other) => other is Reference && other.startId == startId && other.endId == endId;
  @override
  int get hashCode => Object.hash(startId, endId);
  @override
  String toString() => label;
}

/// A reference recognised inside free text.
class ReferenceMatch {
  final int start;
  final int end;
  final Reference? reference;

  /// Human-readable reason when the text looks like a reference but does not exist.
  final String? error;

  const ReferenceMatch(this.start, this.end, this.reference, this.error);

  bool get isValid => reference != null;
}

enum _T { word, num, punct }

class _Tok {
  final _T type;
  final int start;
  final int end;
  final String text;
  final bool spaceBefore;
  final bool newlineBefore;
  const _Tok(this.type, this.start, this.end, this.text, this.spaceBefore, this.newlineBefore);
  int get value => int.parse(text);
}

bool _isDigit(int c) => c >= 48 && c <= 57;
bool _isLetter(int c) => (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 39 || c == 0x2019 || c > 0xBF;

List<_Tok> _tokenize(String s) {
  final toks = <_Tok>[];
  var i = 0;
  var space = true, newline = true;
  while (i < s.length) {
    final c = s.codeUnitAt(i);
    if (c == 32 || c == 9 || c == 0xA0) {
      space = true;
      i++;
      continue;
    }
    if (c == 10 || c == 13) {
      space = true;
      newline = true;
      i++;
      continue;
    }
    final start = i;
    _T type;
    if (_isDigit(c)) {
      while (i < s.length && _isDigit(s.codeUnitAt(i))) {
        i++;
      }
      type = _T.num;
    } else if (_isLetter(c) && c != 39 && c != 0x2019) {
      while (i < s.length && _isLetter(s.codeUnitAt(i))) {
        i++;
      }
      type = _T.word;
    } else {
      i++;
      type = _T.punct;
    }
    toks.add(_Tok(type, start, i, s.substring(start, i), space, newline));
    space = false;
    newline = false;
  }
  return toks;
}

const _fullNameKeys = {'psalm', 'proverb', 'song of songs', 'revelations'};

/// Words that are ordinary English and must look deliberate before being treated as a book.
const _commonWords = {'mark', 'job', 'acts', 'act', 'numbers', 'judges', 'song', 'songs', 'is', 'am', 'ex', 'so'};

final Map<String, int> _aliasToBook = () {
  final m = <String, int>{};
  for (final b in books) {
    m[b.name.toLowerCase()] = b.number;
    for (final a in b.aliases) {
      m[a] = b.number;
    }
  }
  return m;
}();

final Set<String> _fullNames = {for (final b in books) b.name.toLowerCase(), ..._fullNameKeys};

const _ordinals = {'i': 1, 'ii': 2, 'iii': 3, 'first': 1, 'second': 2, 'third': 3};

class _Candidate {
  final int startTok;
  final int endTok;
  final int book;
  final String aliasKey;
  final String bookText;
  final bool abbrevDot;
  final int chapter;
  final int? verse;
  final int? endA;
  final int? endB;
  const _Candidate(this.startTok, this.endTok, this.book, this.aliasKey, this.bookText, this.abbrevDot, this.chapter,
      this.verse, this.endA, this.endB);
}

bool _isDash(String t) => t == '-' || t == '–' || t == '—' || t == '‒';

_Candidate? _parseBookAndNumbers(List<_Tok> t, int i, int? prefix, int bookTok) {
  // Try the longest run of words first so "Song of Solomon" wins over "Song".
  for (var len = 3; len >= 1; len--) {
    final last = bookTok + len - 1;
    if (last >= t.length) continue;
    var ok = true;
    for (var k = bookTok; k <= last; k++) {
      if (t[k].type != _T.word || (k > bookTok && (!t[k].spaceBefore || t[k].newlineBefore))) {
        ok = false;
        break;
      }
    }
    if (!ok) continue;
    final words = [for (var k = bookTok; k <= last; k++) t[k].text.toLowerCase()].join(' ');
    final key = prefix != null ? '$prefix $words' : words;
    final book = _aliasToBook[key];
    if (book == null) continue;
    if (prefix == null && const {1, 2, 3}.any((n) => _aliasToBook['$n $words'] == book)) {
      continue; // "Corinthians 13" without a number is not a book on its own.
    }
    var j = last + 1;
    var dot = false;
    if (j < t.length && t[j].text == '.' && !t[j].spaceBefore) {
      dot = true;
      j++;
    }
    if (j >= t.length || t[j].type != _T.num || t[j].newlineBefore || t[j].text.length > 3) return null;
    if (!dot && !t[j].spaceBefore && t[last].text.length > 3 && !_fullNames.contains(words)) return null;
    final chapter = t[j].value;
    j++;
    int? verse, endA, endB;
    bool sepAt(int k, {bool allowDot = true}) =>
        k + 1 < t.length &&
        (t[k].text == ':' || (allowDot && t[k].text == '.' && !t[k].spaceBefore && !t[k + 1].spaceBefore)) &&
        !t[k].newlineBefore &&
        t[k + 1].type == _T.num &&
        !t[k + 1].newlineBefore &&
        t[k + 1].text.length <= 3;
    if (j < t.length && sepAt(j)) {
      verse = t[j + 1].value;
      j += 2;
    }
    if (j + 1 < t.length && _isDash(t[j].text) && !t[j].newlineBefore && t[j + 1].type == _T.num && !t[j + 1].newlineBefore &&
        t[j + 1].text.length <= 3) {
      endA = t[j + 1].value;
      j += 2;
      if (j < t.length && sepAt(j)) {
        endB = t[j + 1].value;
        j += 2;
      }
    }
    // Allow scholarly part-verse suffixes such as "John 3:16a".
    if (j < t.length && t[j].type == _T.word && !t[j].spaceBefore) {
      if (verse != null && const {'a', 'b', 'c'}.contains(t[j].text)) {
        j++;
      } else {
        return null; // "John 3rd", "Mark 2pm" and similar are not references.
      }
    }
    final bookText = [for (var k = bookTok; k <= last; k++) t[k].text].join(' ');
    return _Candidate(i, j, book, words, bookText, dot, chapter, verse, endA, endB);
  }
  return null;
}

/// Decides whether the candidate looks deliberate enough to link, avoiding false positives
/// in ordinary prose ("Mark 2 people", "is 5:30", "acts 3 times").
bool _plausible(_Candidate c, {required bool lenient}) {
  if (lenient) return true;
  final first = c.bookText.codeUnitAt(0);
  final capitalized = first >= 65 && first <= 90;
  final allCaps = c.bookText.length > 1 && c.bookText == c.bookText.toUpperCase();
  final isFull = _fullNames.contains(c.aliasKey) ||
      bookByNumber(c.book).name.toLowerCase().replaceFirst(RegExp(r'^[123] '), '') == c.aliasKey;
  final hasVerse = c.verse != null || (bookByNumber(c.book).chapters == 1 && c.chapter > 1);
  if (!capitalized) {
    return isFull && hasVerse && !_commonWords.contains(c.aliasKey);
  }
  if (c.aliasKey.length <= 2 && allCaps) return false;
  if (!hasVerse) {
    if (_commonWords.contains(c.aliasKey) && (!isFull || allCaps)) return false;
    return isFull || c.abbrevDot;
  }
  return true;
}

class _Validated {
  final Reference? ref;
  final String? error;
  const _Validated(this.ref, this.error);
}

_Validated _validate(_Candidate c, Versification v) {
  final book = bookByNumber(c.book);
  final chapters = v.chapterCount(c.book);
  var chapter = c.chapter;
  int? verse = c.verse, endChapter, endVerse;
  if (verse == null) {
    if (chapters == 1 && !(chapter == 1 && c.endA == null)) {
      // "Jude 5" and "Jude 3-5" refer to verses of the only chapter.
      verse = chapter;
      chapter = 1;
      if (c.endA != null && c.endB == null) endVerse = c.endA;
    } else if (c.endA != null) {
      endChapter = c.endA;
      endVerse = c.endB;
    }
  } else if (c.endA != null) {
    if (c.endB != null) {
      endChapter = c.endA;
      endVerse = c.endB;
    } else {
      endVerse = c.endA;
    }
  }
  endChapter ??= chapter;
  final name = book.name;
  if (chapter < 1 || chapter > chapters) {
    return _Validated(null, chapters == 1 ? '$name has only one chapter' : '$name has $chapters chapters');
  }
  final maxV = v.maxVerse(c.book, chapter) ?? 0;
  if (verse != null && (verse < 1 || verse > maxV)) {
    return _Validated(null, '$name $chapter has $maxV verses');
  }
  if (endChapter < chapter || endChapter > chapters) {
    return _Validated(null, endChapter > chapters ? '$name has $chapters chapters' : 'The range ends before it starts');
  }
  if (endVerse != null) {
    final maxEnd = v.maxVerse(c.book, endChapter) ?? 0;
    if (endVerse < 1 || endVerse > maxEnd) return _Validated(null, '$name $endChapter has $maxEnd verses');
    if (endChapter == chapter && verse != null && endVerse < verse) {
      return const _Validated(null, 'The range ends before it starts');
    }
  }
  return _Validated(Reference(c.book, chapter, verse, endChapter, endVerse)._normalized(), null);
}

/// Parses all candidate references starting at token [i], trying both the numbered-book and
/// plain readings, and prefers the one that validates.
({_Candidate cand, _Validated result})? _bestAt(List<_Tok> t, int i, Versification v, bool lenient) {
  final options = <_Candidate>[];
  final tok = t[i];
  int? prefix;
  var bookTok = i + 1;
  if (tok.type == _T.num && tok.text.length == 1 && const {'1', '2', '3'}.contains(tok.text)) {
    prefix = tok.value;
    if (bookTok < t.length && t[bookTok].type == _T.word && !t[bookTok].spaceBefore &&
        const {'st', 'nd', 'rd'}.contains(t[bookTok].text.toLowerCase())) {
      bookTok++;
    }
  } else if (tok.type == _T.word && _ordinals.containsKey(tok.text.toLowerCase())) {
    final roman = !const {'first', 'second', 'third'}.contains(tok.text.toLowerCase());
    // Roman numerals must be written in capitals ("II Kings"), never as the pronoun "i".
    if (!roman || tok.text == tok.text.toUpperCase() || lenient) prefix = _ordinals[tok.text.toLowerCase()];
  }
  if (prefix != null && bookTok < t.length && t[bookTok].type == _T.word && !t[bookTok].newlineBefore) {
    final c = _parseBookAndNumbers(t, i, prefix, bookTok);
    if (c != null) options.add(c);
  }
  if (tok.type == _T.word) {
    final c = _parseBookAndNumbers(t, i, null, i);
    if (c != null) options.add(c);
  }
  ({_Candidate cand, _Validated result})? best;
  for (final c in options) {
    if (!_plausible(c, lenient: lenient)) continue;
    final r = _validate(c, v);
    if (best == null || (best.result.ref == null && r.ref != null)) best = (cand: c, result: r);
  }
  return best;
}

/// Finds every Scripture reference written inside [text], validated against [v].
List<ReferenceMatch> findReferences(String text, Versification v) {
  final t = _tokenize(text);
  final out = <ReferenceMatch>[];
  var i = 0;
  while (i < t.length) {
    final tok = t[i];
    if (tok.type == _T.punct || (i > 0 && !tok.spaceBefore && t[i - 1].type != _T.punct)) {
      i++;
      continue;
    }
    final best = _bestAt(t, i, v, false);
    if (best == null) {
      i++;
      continue;
    }
    final c = best.cand;
    out.add(ReferenceMatch(t[c.startTok].start, t[c.endTok - 1].end, best.result.ref, best.result.error));
    i = c.endTok;
  }
  return out;
}

/// Result of interpreting a reference typed into a search or "go to" box.
class QueryParse {
  final Reference? reference;
  final Book? book;
  final String? error;
  const QueryParse({this.reference, this.book, this.error});
}

String _normalizeQuery(String q) => q.trim().replaceAll(RegExp(r'\s+'), ' ');

/// Leniently interprets a whole query such as "jn 3 16", "rom 8:28-30", "psalm 23" or "genesis".
QueryParse parseQuery(String query, Versification v) {
  var q = _normalizeQuery(query);
  if (q.isEmpty) return const QueryParse();
  // "John 3 16" -> "John 3:16"
  q = q.replaceFirstMapped(RegExp(r'^(.*[A-Za-z]\.?\s*\d{1,3})\s+(\d{1,3}\b.*)$'), (m) => '${m[1]}:${m[2]}');
  final t = _tokenize(q);
  if (t.isEmpty) return const QueryParse();
  final best = _bestAt(t, 0, v, true);
  if (best != null && best.cand.endTok == t.length) {
    return QueryParse(
        reference: best.result.ref, book: bookByNumber(best.cand.book), error: best.result.error);
  }
  final book = matchBook(q);
  if (book != null) return QueryParse(book: book);
  return const QueryParse();
}

/// Exact book match for a typed name or abbreviation ("1 cor", "Song of Songs", "ps").
Book? matchBook(String q) {
  var k = _normalizeQuery(q).toLowerCase().replaceAll('.', '');
  k = k.replaceFirstMapped(RegExp(r'^(1|2|3)(st|nd|rd)?\s*'), (m) => '${m[1]} ');
  k = k.replaceFirstMapped(RegExp(r'^(iii|ii|i|first|second|third) '), (m) => '${_ordinals[m[1]]} ');
  final n = _aliasToBook[k];
  return n == null ? null : bookByNumber(n);
}

/// Books whose names or abbreviations start with [prefix], for autocomplete.
List<Book> suggestBooks(String prefix) {
  final p = _normalizeQuery(prefix).toLowerCase().replaceAll('.', '');
  if (p.isEmpty) return const [];
  final compact = p.replaceAll(' ', '');
  return books.where((b) {
    final n = b.name.toLowerCase();
    if (n.startsWith(p) || n.replaceAll(' ', '').startsWith(compact)) return true;
    return b.aliases.any((a) => a.startsWith(p) || a.replaceAll(' ', '').startsWith(compact));
  }).toList();
}

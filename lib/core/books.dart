/// Canonical metadata for the 66 books of the Protestant Bible.
///
/// Verse identifiers throughout the app use `book * 1000000 + chapter * 1000 + verse`
/// so that a reference survives any translation that shares this versification.
class Book {
  final int number;
  final String name;
  final String short;
  final int chapters;
  final List<String> aliases;

  const Book(this.number, this.name, this.short, this.chapters, this.aliases);

  bool get isOldTestament => number <= 39;
}

int verseId(int book, int chapter, int verse) => book * 1000000 + chapter * 1000 + verse;
int bookOf(int id) => id ~/ 1000000;
int chapterOf(int id) => (id ~/ 1000) % 1000;
int verseOf(int id) => id % 1000;

const List<Book> books = [
  Book(1, 'Genesis', 'Gen', 50, ['gen', 'ge', 'gn']),
  Book(2, 'Exodus', 'Exod', 40, ['exod', 'exo', 'ex']),
  Book(3, 'Leviticus', 'Lev', 27, ['lev', 'le', 'lv']),
  Book(4, 'Numbers', 'Num', 36, ['num', 'nu', 'nm', 'nb']),
  Book(5, 'Deuteronomy', 'Deut', 34, ['deut', 'deu', 'dt']),
  Book(6, 'Joshua', 'Josh', 24, ['josh', 'jos', 'jsh']),
  Book(7, 'Judges', 'Judg', 21, ['judg', 'jdg', 'jg', 'jdgs']),
  Book(8, 'Ruth', 'Ruth', 4, ['rut', 'rth', 'ru']),
  Book(9, '1 Samuel', '1 Sam', 31, ['1 sam', '1 sa', '1 sm', '1 samuel']),
  Book(10, '2 Samuel', '2 Sam', 24, ['2 sam', '2 sa', '2 sm', '2 samuel']),
  Book(11, '1 Kings', '1 Kgs', 22, ['1 kgs', '1 ki', '1 kin', '1 kings']),
  Book(12, '2 Kings', '2 Kgs', 25, ['2 kgs', '2 ki', '2 kin', '2 kings']),
  Book(13, '1 Chronicles', '1 Chr', 29, ['1 chron', '1 chr', '1 ch', '1 chronicles']),
  Book(14, '2 Chronicles', '2 Chr', 36, ['2 chron', '2 chr', '2 ch', '2 chronicles']),
  Book(15, 'Ezra', 'Ezra', 10, ['ezr']),
  Book(16, 'Nehemiah', 'Neh', 13, ['neh', 'ne']),
  Book(17, 'Esther', 'Esth', 10, ['esth', 'est', 'es']),
  Book(18, 'Job', 'Job', 42, ['jb']),
  Book(19, 'Psalms', 'Ps', 150, ['psalm', 'psa', 'ps', 'pss', 'psm', 'pslm']),
  Book(20, 'Proverbs', 'Prov', 31, ['proverb', 'prov', 'pro', 'prv', 'pr']),
  Book(21, 'Ecclesiastes', 'Eccl', 12, ['eccles', 'eccl', 'ecc', 'ec', 'qoh']),
  Book(22, 'Song of Solomon', 'Song', 8, ['song of songs', 'song', 'songs', 'sos', 'canticles', 'sng']),
  Book(23, 'Isaiah', 'Isa', 66, ['isa', 'is']),
  Book(24, 'Jeremiah', 'Jer', 52, ['jer', 'je', 'jr']),
  Book(25, 'Lamentations', 'Lam', 5, ['lam', 'la']),
  Book(26, 'Ezekiel', 'Ezek', 48, ['ezek', 'eze', 'ezk']),
  Book(27, 'Daniel', 'Dan', 12, ['dan', 'da', 'dn']),
  Book(28, 'Hosea', 'Hos', 14, ['hos', 'ho']),
  Book(29, 'Joel', 'Joel', 3, ['jl']),
  Book(30, 'Amos', 'Amos', 9, ['am']),
  Book(31, 'Obadiah', 'Obad', 1, ['obad', 'ob']),
  Book(32, 'Jonah', 'Jonah', 4, ['jon', 'jnh']),
  Book(33, 'Micah', 'Mic', 7, ['mic', 'mc']),
  Book(34, 'Nahum', 'Nah', 3, ['nah', 'na']),
  Book(35, 'Habakkuk', 'Hab', 3, ['hab', 'hb']),
  Book(36, 'Zephaniah', 'Zeph', 3, ['zeph', 'zep', 'zp']),
  Book(37, 'Haggai', 'Hag', 2, ['hag', 'hg']),
  Book(38, 'Zechariah', 'Zech', 14, ['zech', 'zec', 'zc']),
  Book(39, 'Malachi', 'Mal', 4, ['mal', 'ml']),
  Book(40, 'Matthew', 'Matt', 28, ['matt', 'mat', 'mt']),
  Book(41, 'Mark', 'Mark', 16, ['mrk', 'mk', 'mr', 'mar']),
  Book(42, 'Luke', 'Luke', 24, ['luk', 'lk']),
  Book(43, 'John', 'John', 21, ['jn', 'jhn', 'joh']),
  Book(44, 'Acts', 'Acts', 28, ['act', 'ac']),
  Book(45, 'Romans', 'Rom', 16, ['rom', 'ro', 'rm']),
  Book(46, '1 Corinthians', '1 Cor', 16, ['1 cor', '1 co', '1 corinthians']),
  Book(47, '2 Corinthians', '2 Cor', 13, ['2 cor', '2 co', '2 corinthians']),
  Book(48, 'Galatians', 'Gal', 6, ['gal', 'ga']),
  Book(49, 'Ephesians', 'Eph', 6, ['eph', 'ephes']),
  Book(50, 'Philippians', 'Phil', 4, ['phil', 'php', 'pp']),
  Book(51, 'Colossians', 'Col', 4, ['col']),
  Book(52, '1 Thessalonians', '1 Thess', 5, ['1 thess', '1 thes', '1 th', '1 thessalonians']),
  Book(53, '2 Thessalonians', '2 Thess', 3, ['2 thess', '2 thes', '2 th', '2 thessalonians']),
  Book(54, '1 Timothy', '1 Tim', 6, ['1 tim', '1 ti', '1 timothy']),
  Book(55, '2 Timothy', '2 Tim', 4, ['2 tim', '2 ti', '2 timothy']),
  Book(56, 'Titus', 'Titus', 3, ['tit']),
  Book(57, 'Philemon', 'Phlm', 1, ['philem', 'phm', 'phlm']),
  Book(58, 'Hebrews', 'Heb', 13, ['heb']),
  Book(59, 'James', 'Jas', 5, ['jas', 'jm', 'jam']),
  Book(60, '1 Peter', '1 Pet', 5, ['1 pet', '1 pe', '1 pt', '1 peter']),
  Book(61, '2 Peter', '2 Pet', 3, ['2 pet', '2 pe', '2 pt', '2 peter']),
  Book(62, '1 John', '1 John', 5, ['1 jn', '1 jhn', '1 jo', '1 john']),
  Book(63, '2 John', '2 John', 1, ['2 jn', '2 jhn', '2 jo', '2 john']),
  Book(64, '3 John', '3 John', 1, ['3 jn', '3 jhn', '3 jo', '3 john']),
  Book(65, 'Jude', 'Jude', 1, ['jud', 'jd']),
  Book(66, 'Revelation', 'Rev', 22, ['revelations', 'rev', 're', 'rv']),
];

Book bookByNumber(int n) => books[n - 1];

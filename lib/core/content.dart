import 'books.dart';
import 'reference.dart';

/// Well-loved passages used for the verse of the day. Only references are stored here;
/// the text always comes from the installed translation.
const dailyVerseRefs = [
  'John 3:16', 'Psalm 23:1', 'Philippians 4:13', 'Jeremiah 29:11', 'Romans 8:28', 'Proverbs 3:5-6', 'Isaiah 40:31',
  'Joshua 1:9', 'Matthew 11:28', 'Psalm 46:1', '2 Corinthians 5:17', 'Romans 12:2', 'Philippians 4:6-7',
  'Galatians 2:20', 'Hebrews 11:1', 'Psalm 119:105', 'Matthew 6:33', 'Romans 15:13', 'Isaiah 41:10', '1 Peter 5:7',
  'Lamentations 3:22-23', 'Psalm 37:4', 'Micah 6:8', 'John 14:6', 'Ephesians 2:8-9', '2 Timothy 1:7',
  'Psalm 27:1', 'Romans 5:8', 'John 16:33', 'Colossians 3:23', 'James 1:5', 'Psalm 34:8', 'Matthew 5:16',
  'Deuteronomy 31:6', 'Zephaniah 3:17', 'Psalm 121:1-2', '1 John 1:9', 'Hebrews 12:1-2', 'Romans 10:9',
  'Psalm 91:1-2', 'Isaiah 26:3', 'John 15:5', '2 Corinthians 12:9', 'Psalm 139:14', 'Galatians 5:22-23',
  'Matthew 22:37-39', 'Proverbs 16:3', 'Psalm 16:11', 'John 10:10', 'Romans 8:38-39', 'Ephesians 3:20',
  'Psalm 51:10', '1 Corinthians 10:13', 'Hebrews 4:16', 'Psalm 103:2-4', 'Isaiah 43:2', 'John 13:34-35',
  'Philippians 1:6', 'Psalm 62:1-2', 'Matthew 28:19-20', '1 Thessalonians 5:16-18', 'Psalm 145:18', 'James 1:2-3',
  'Proverbs 18:10', 'Romans 12:12', 'Colossians 3:15', 'Psalm 19:14', 'Isaiah 55:8-9', 'John 8:12', 'Psalm 32:8',
  '2 Chronicles 7:14', 'Hebrews 13:8', 'Psalm 56:3', 'Matthew 7:7', 'Ephesians 4:32', 'Psalm 4:8', 'John 11:25',
  '1 Corinthians 13:4-7', 'Romans 6:23', 'Psalm 30:5', 'Isaiah 53:5', 'Nahum 1:7', 'Psalm 118:24', 'John 1:1',
  'Genesis 1:1', 'Psalm 100:4-5', 'Matthew 5:9', 'Philippians 4:19', '1 John 4:18', 'Psalm 40:1-3',
  'Hebrews 10:23', 'Romans 1:16', 'Psalm 73:26', 'Isaiah 9:6', 'Luke 1:37', 'Psalm 147:3', '2 Peter 3:9',
  'Exodus 14:14', 'Psalm 18:2', 'John 14:27', 'Ecclesiastes 3:1', 'Psalm 9:9-10', 'Revelation 21:4',
  'Matthew 5:3-4', 'Psalm 31:24', 'Romans 8:1', 'Isaiah 30:15', 'Psalm 84:11', '1 John 4:19', 'Galatians 6:9',
  'Psalm 90:12', 'Colossians 3:2', 'John 6:35', 'Psalm 127:1', 'Hebrews 11:6', 'Mark 11:24', 'Psalm 5:3',
  'Proverbs 4:23', 'Isaiah 58:11', 'Luke 6:31', 'Psalm 136:1', 'Acts 1:8', 'Romans 12:10', 'Psalm 57:10',
];

int epochDay(DateTime d) => DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/ 86400000;

/// The same passage for everyone on a given calendar day, chosen deterministically.
Reference verseOfTheDay(DateTime day, Versification v) {
  final i = (epochDay(day) * 7919) % dailyVerseRefs.length;
  return parseQuery(dailyVerseRefs[i], v).reference ?? const Reference(43, 3, 16);
}

class ReadingPlan {
  final String id;
  final String title;
  final String description;
  final int days;
  final List<int> chapters; // chapter keys: book * 1000 + chapter

  ReadingPlan(this.id, this.title, this.description, this.days, this.chapters);

  /// Chapters for a zero-based [day], spread as evenly as possible.
  List<int> chaptersForDay(int day) {
    final n = chapters.length;
    return chapters.sublist((day * n) ~/ days, ((day + 1) * n) ~/ days);
  }

  static List<int> _range(int fromBook, int toBook) => [
        for (var b = fromBook; b <= toBook; b++)
          for (var c = 1; c <= bookByNumber(b).chapters; c++) b * 1000 + c
      ];

  static final all = [
    ReadingPlan('year', 'Bible in a Year', 'Every chapter from Genesis to Revelation in 365 days.', 365, _range(1, 66)),
    ReadingPlan('nt90', 'New Testament in 90 Days', 'Matthew to Revelation, about three chapters a day.', 90, _range(40, 66)),
    ReadingPlan('gospels30', 'The Gospels in 30 Days', 'The life of Jesus in Matthew, Mark, Luke and John.', 30, _range(40, 43)),
    ReadingPlan('psalms30', 'Psalms in 30 Days', 'Five psalms a day for a month of prayer and praise.', 30, _range(19, 19)),
    ReadingPlan('proverbs31', 'Proverbs in a Month', 'One chapter of wisdom for each day of the month.', 31, _range(20, 20)),
  ];

  static ReadingPlan? byId(String id) {
    for (final p in all) {
      if (p.id == id) return p;
    }
    return null;
  }
}

String describeChapters(List<int> keys) {
  if (keys.isEmpty) return '';
  final parts = <String>[];
  var i = 0;
  while (i < keys.length) {
    final b = keys[i] ~/ 1000;
    var j = i;
    while (j + 1 < keys.length && keys[j + 1] == keys[j] + 1 && keys[j + 1] ~/ 1000 == b) {
      j++;
    }
    final name = bookByNumber(b).name;
    final from = keys[i] % 1000, to = keys[j] % 1000;
    parts.add(from == to ? '$name $from' : '$name $from–$to');
    i = j + 1;
  }
  return parts.join(', ');
}

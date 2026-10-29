import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_services.dart';
import '../core/bible_repository.dart';
import '../core/books.dart';
import '../core/platform.dart';
import '../core/reference.dart';
import 'reader_page.dart';
import 'theme.dart';

Services get services => Services.I;

/// Opens the full reader at a passage.
Future<void> openReader(BuildContext context, Reference r) {
  return Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => ReaderPage(book: r.book, chapter: r.chapter, focusStart: r.verse == null ? null : r.startId, focusEnd: r.verse == null ? null : r.endId),
  ));
}

Future<void> openReaderAt(BuildContext context, int verseIdValue) =>
    openReader(context, Reference(bookOf(verseIdValue), chapterOf(verseIdValue), verseOf(verseIdValue)));

/// Plain text of a passage, with verse numbers when more than one verse is included.
String passagePlain(List<Verse> verses) {
  if (verses.length == 1) return verses.first.text;
  return verses.map((v) => '${v.number} ${v.text}').join(' ');
}

String passageForSharing(List<Verse> verses, Reference r, String abbreviation) =>
    '“${passagePlain(verses)}”\n— ${r.label} ($abbreviation)';

/// Groups verse ids into contiguous runs, e.g. [16, 17, 18, 20] -> [(16, 18), (20, 20)].
List<(int, int)> contiguousRuns(Iterable<int> ids) {
  final sorted = ids.toList()..sort();
  final out = <(int, int)>[];
  for (final id in sorted) {
    if (out.isNotEmpty && out.last.$2 + 1 == id) {
      out[out.length - 1] = (out.last.$1, id);
    } else {
      out.add((id, id));
    }
  }
  return out;
}

void toast(BuildContext context, String message, {SnackBarAction? action}) {
  final m = ScaffoldMessenger.maybeOf(context);
  m?.hideCurrentSnackBar();
  m?.showSnackBar(SnackBar(content: Text(message), action: action, duration: const Duration(seconds: 3)));
}

Future<void> copyToClipboard(BuildContext context, String text, {String message = 'Copied'}) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) toast(context, message);
}

Future<void> shareText(BuildContext context, String text, {String? subject}) async {
  try {
    await PlatformBridge.shareText(text, subject: subject);
  } catch (_) {
    if (context.mounted) await copyToClipboard(context, text, message: 'Sharing is unavailable, so the text was copied');
  }
}

const _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
const _days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

String longDate(DateTime d) => '${_days[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]} ${d.year}';
String shortDate(DateTime d) => '${d.day} ${_months[d.month - 1].substring(0, 3)} ${d.year}';
String timeOfDay(int minutes) {
  final h = minutes ~/ 60, m = minutes % 60;
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12:${m.toString().padLeft(2, '0')} ${h < 12 ? 'AM' : 'PM'}';
}

String relativeTime(int ms) {
  final t = DateTime.fromMillisecondsSinceEpoch(ms);
  final diff = DateTime.now().difference(t);
  if (diff.inSeconds < 45) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24 && t.day == DateTime.now().day) {
    return 'today ${timeOfDay(t.hour * 60 + t.minute)}';
  }
  if (diff.inDays < 2) return 'yesterday';
  if (diff.inDays < 7) return '${diff.inDays} days ago';
  return shortDate(t);
}

String formatBytes(int b) {
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
  return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  const EmptyState({super.key, required this.icon, required this.title, required this.message, this.action});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: context.colors.primaryContainer, shape: BoxShape.circle),
            child: Icon(icon, size: 32, color: context.colors.onPrimaryContainer),
          ),
          const SizedBox(height: 20),
          Text(title, style: context.text.titleLarge, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(message, style: context.text.bodyMedium?.copyWith(color: context.muted, height: 1.5), textAlign: TextAlign.center),
          if (action != null) ...[const SizedBox(height: 20), action!],
        ]),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const SectionHeader(this.title, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
      child: Row(children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(title.toUpperCase(),
                style: context.text.labelMedium?.copyWith(letterSpacing: 1.2, color: context.muted, fontWeight: FontWeight.w600)),
          ),
        ),
        ?trailing,
      ]),
    );
  }
}

/// Constrains content to a comfortable reading width on tablets and landscape screens.
class ReadableWidth extends StatelessWidget {
  final Widget child;
  final double max;
  const ReadableWidth({super.key, required this.child, this.max = 720});
  @override
  Widget build(BuildContext context) =>
      Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: BoxConstraints(maxWidth: max), child: child));
}

/// Pill showing the active translation abbreviation; tapping lets the user switch.
class TranslationChip extends StatelessWidget {
  final VoidCallback? onTap;
  const TranslationChip({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: services.bibleChanged,
      builder: (context, _, _) {
        final t = services.bible.translation;
        return Semantics(
          button: true,
          label: 'Translation: ${t.name}',
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap ?? () => showTranslationPicker(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: context.colors.outlineVariant),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(t.abbreviation,
                  style: context.text.labelMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.6, color: context.colors.primary)),
            ),
          ),
        );
      },
    );
  }
}

Future<void> showTranslationPicker(BuildContext context) async {
  final list = await services.store.installedTranslations();
  if (!context.mounted) return;
  final current = services.bible.translation.code;
  final chosen = await showModalBottomSheet<Translation>(
    context: context,
    builder: (context) => SafeArea(
      child: ScrollColumn(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Text('Translation', style: context.text.titleLarge),
        ),
        for (final t in list)
          ListTile(
            leading: Icon(t.code == current ? Icons.radio_button_checked : Icons.radio_button_off,
                color: t.code == current ? context.colors.primary : null),
            title: Text(t.name),
            subtitle: Text('${t.abbreviation} · Installed${t.builtIn ? ' · built in' : ''}'),
            onTap: () => Navigator.pop(context, t),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
          child: Text('Add translations in Settings › Bible translations.',
              style: context.text.bodySmall?.copyWith(color: context.muted)),
        ),
      ]),
    ),
  );
  if (chosen != null) {
    try {
      await services.switchTranslation(chosen);
    } catch (e) {
      if (context.mounted) toast(context, 'Could not open ${chosen.name}: $e');
    }
  }
}

/// Segment text that stays on one line and shrinks to fit at large system font sizes.
class SegmentLabel extends StatelessWidget {
  final String text;
  const SegmentLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) =>
      FittedBox(fit: BoxFit.scaleDown, child: Text(text, maxLines: 1, softWrap: false));
}

/// A column for bottom sheets that scrolls instead of overflowing on short screens
/// (landscape phones, large system font sizes).
class ScrollColumn extends StatelessWidget {
  final MainAxisSize mainAxisSize;
  final CrossAxisAlignment crossAxisAlignment;
  final List<Widget> children;
  const ScrollColumn({
    super.key,
    this.mainAxisSize = MainAxisSize.min,
    this.crossAxisAlignment = CrossAxisAlignment.center,
    required this.children,
  });

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        child: Column(mainAxisSize: mainAxisSize, crossAxisAlignment: crossAxisAlignment, children: children),
      );
}

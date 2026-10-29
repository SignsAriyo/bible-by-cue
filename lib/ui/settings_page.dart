import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/bible_repository.dart';
import '../core/platform.dart';
import '../core/user_store.dart';
import 'common.dart';
import 'note_editor.dart';
import 'plans_page.dart';
import 'reader_page.dart';
import 'theme.dart';

const appVersion = '1.0.1';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = services.settings;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListenableBuilder(
        listenable: s,
        builder: (context, _) => ReadableWidth(
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
            const SectionHeader('Reading'),
            _Group(children: [
              ListTile(
                leading: const Icon(Icons.text_fields),
                title: const Text('Text size and spacing'),
                subtitle: Text('Size ${s.fontSize.round()} · spacing ${s.lineHeight.toStringAsFixed(1)}'),
                onTap: () => showReadingSettings(context),
              ),
              ListTile(
                leading: const Icon(Icons.contrast),
                title: const Text('Theme'),
                trailing: DropdownButton<ThemeMode>(
                  value: s.themeMode,
                  underline: const SizedBox.shrink(),
                  onChanged: (m) => s.themeMode = m!,
                  items: const [
                    DropdownMenuItem(value: ThemeMode.system, child: Text('Match device')),
                    DropdownMenuItem(value: ThemeMode.light, child: Text('Light')),
                    DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
                  ],
                ),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.format_list_numbered),
                title: const Text('Show verse numbers'),
                value: s.verseNumbers,
                onChanged: (v) => s.verseNumbers = v,
              ),
              ListTile(
                leading: const Icon(Icons.event_note_outlined),
                title: const Text('Reading plans'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PlansPage())),
              ),
              const _ReminderTile(),
            ]),
            const SectionHeader('Notes'),
            _Group(children: [
              SwitchListTile(
                secondary: const Icon(Icons.preview_outlined),
                title: const Text('Preview references automatically'),
                subtitle: const Text('Open the Scripture panel when you pause after typing a reference. Off by default; tapping a reference always works.'),
                value: s.autoPreview,
                onChanged: (v) => s.autoPreview = v,
              ),
            ]),
            const SectionHeader('Bible'),
            _Group(children: [
              ListTile(
                leading: const Icon(Icons.translate),
                title: const Text('Bible translations'),
                subtitle: ValueListenableBuilder(
                  valueListenable: services.bibleChanged,
                  builder: (_, _, _) => Text('Reading ${services.bible.translation.name}'),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TranslationsPage())),
              ),
              ListTile(
                leading: const Icon(Icons.sd_storage_outlined),
                title: const Text('Storage'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StoragePage())),
              ),
            ]),
            const SectionHeader('Your data'),
            _Group(children: [
              ListTile(
                leading: const Icon(Icons.backup_outlined),
                title: const Text('Back up and restore'),
                subtitle: const Text('Notes, bookmarks, highlights, plans and settings'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BackupPage())),
              ),
              ListTile(
                leading: const Icon(Icons.lock_outline),
                title: const Text('Privacy'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacyPage())),
              ),
            ]),
            const SectionHeader('About'),
            _Group(children: [
              ListTile(
                leading: const AppMark(size: 32),
                title: const Text('Bible by Cue'),
                subtitle: const Text('Created by Cue · version $appVersion'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AboutPage())),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  final List<Widget> children;
  const _Group({required this.children});
  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(indent: 56),
            children[i],
          ],
        ]),
      );
}

class _ReminderTile extends StatelessWidget {
  const _ReminderTile();

  @override
  Widget build(BuildContext context) {
    final s = services.settings;
    Future<void> apply(bool on, int minutes) async {
      try {
        final granted = await PlatformBridge.setReminder(on, minutes);
        s.setReminder(on && granted, minutes);
        if (on && !granted && context.mounted) {
          toast(context, 'Notifications are turned off for Bible by Cue. Allow them in system settings to get reminders.');
        } else if (on && context.mounted) {
          toast(context, 'Daily reminder set for ${timeOfDay(minutes)}');
        }
      } catch (e) {
        if (context.mounted) toast(context, 'Could not set the reminder: $e');
      }
    }

    // Listens itself: as a const child it is not rebuilt when the settings page rebuilds.
    return ListenableBuilder(listenable: s, builder: (context, _) => SwitchListTile(
      secondary: const Icon(Icons.notifications_none),
      title: const Text('Daily reading reminder'),
      subtitle: s.reminderOn
          ? InkWell(
              onTap: () async {
                final t = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay(hour: s.reminderMinutes ~/ 60, minute: s.reminderMinutes % 60),
                );
                if (t != null) await apply(true, t.hour * 60 + t.minute);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text('Every day at ${timeOfDay(s.reminderMinutes)} · tap to change',
                    style: TextStyle(color: context.colors.primary, fontWeight: FontWeight.w600)),
              ),
            )
          : const Text('A gentle local notification. Off by default.'),
      value: s.reminderOn,
      onChanged: (v) => apply(v, s.reminderMinutes),
    ));
  }
}

// ---------------------------------------------------------------------------- translations

class TranslationsPage extends StatefulWidget {
  const TranslationsPage({super.key});
  @override
  State<TranslationsPage> createState() => _TranslationsPageState();
}

class _TranslationsPageState extends State<TranslationsPage> {
  double? _progress;

  Future<void> _import() async {
    final file = await PlatformBridge.openDocument(['text/plain', 'application/octet-stream']);
    if (file == null || !mounted) return;
    String data;
    try {
      data = utf8.decode(file.bytes, allowMalformed: true);
    } catch (_) {
      toast(context, 'This file could not be read as text.');
      return;
    }
    final verses = parseVerseLines(data);
    if (verses.length < 1000) {
      toast(context, 'No Bible text was found in ${file.name}. Use a verse-per-line (VPL) text file.');
      return;
    }
    final name = TextEditingController(text: file.name.replaceAll(RegExp(r'\.[^.]+$'), ''));
    final abbr = TextEditingController();
    bool licensed = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, set) => AlertDialog(
          title: const Text('Install translation'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('${verses.length} verses found in ${verses.map((v) => v.book).toSet().length} books.'),
              const SizedBox(height: 12),
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: 8),
              TextField(controller: abbr, decoration: const InputDecoration(labelText: 'Abbreviation, e.g. KJV')),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: licensed,
                onChanged: (v) => set(() => licensed = v ?? false),
                title: const Text('I have the right to use this text (e.g. it is in the public domain).'),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: licensed ? () => Navigator.pop(context, true) : null, child: const Text('Install')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final ab = abbr.text.trim().isEmpty ? 'BIBLE' : abbr.text.trim().toUpperCase();
    final code = ab.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final existing = await services.store.installedTranslations();
    if (existing.any((t) => t.code == code) || code.isEmpty) {
      if (mounted) toast(context, 'A translation called $ab is already installed. Choose another abbreviation.');
      return;
    }
    final t = Translation(code, name.text.trim().isEmpty ? ab : name.text.trim(), ab, 'Imported by the user from ${file.name}.');
    setState(() => _progress = 0);
    try {
      await BibleRepository.install(t, data, onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      });
      await services.store.registerTranslation(t);
      if (mounted) toast(context, '${t.name} installed');
    } catch (e) {
      if (mounted) toast(context, 'Install failed: $e');
    } finally {
      if (mounted) setState(() => _progress = null);
    }
  }

  Future<void> _remove(Translation t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${t.name}?'),
        content: const Text('Your notes, bookmarks and highlights are kept — they refer to verses, not to a translation.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    if (services.bible.translation.code == t.code) await services.switchTranslation(webTranslation);
    await BibleRepository.uninstall(t);
    await services.store.unregisterTranslation(t.code);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bible translations')),
      body: ListenableBuilder(
        listenable: Listenable.merge([services.store, services.bibleChanged]),
        builder: (context, _) => FutureBuilder<List<Translation>>(
          future: services.store.installedTranslations(),
          builder: (context, snap) {
            final list = snap.data ?? const <Translation>[];
            return ReadableWidth(
              child: ListView(padding: const EdgeInsets.all(16), children: [
                if (_progress != null) ...[
                  Text('Installing… ${(_progress! * 100).round()}%'),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(value: _progress),
                  const SizedBox(height: 16),
                ],
                const SectionHeader('Installed'),
                for (final t in list)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text(t.name, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
                          if (services.bible.translation.code == t.code)
                            Chip(label: const Text('Reading'), backgroundColor: context.colors.primaryContainer, visualDensity: VisualDensity.compact),
                        ]),
                        Text('${t.abbreviation} · installed · works offline${t.builtIn ? ' · built in' : ''}', style: TextStyle(color: context.muted)),
                        const SizedBox(height: 8),
                        Text(t.license, style: context.text.bodySmall),
                        const SizedBox(height: 8),
                        Row(children: [
                          if (services.bible.translation.code != t.code)
                            TextButton(onPressed: () => services.switchTranslation(t), child: const Text('Read this translation')),
                          const Spacer(),
                          if (!t.builtIn) TextButton(onPressed: () => _remove(t), child: const Text('Remove')),
                        ]),
                      ]),
                    ),
                  ),
                const SectionHeader('Add a translation'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(
                        'Install another translation from a verse-per-line text file on this device, such as the “_vpl.txt” files published '
                        'by eBible.org for public-domain Bibles. Installation happens entirely offline and only adds what you choose.',
                        style: TextStyle(height: 1.45, color: context.colors.onSurface),
                      ),
                      const SizedBox(height: 6),
                      Text('No translations are downloaded by the app itself, so it never needs internet access.',
                          style: TextStyle(color: context.muted, height: 1.4)),
                      const SizedBox(height: 12),
                      FilledButton.tonalIcon(
                        onPressed: _progress == null ? _import : null,
                        icon: const Icon(Icons.file_open_outlined),
                        label: const Text('Install from file'),
                      ),
                    ]),
                  ),
                ),
              ]),
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------- storage

class StoragePage extends StatelessWidget {
  const StoragePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Storage')),
      body: FutureBuilder(
        future: Future.wait([services.bible.fileSize(), services.store.fileSize(), services.store.notes(), services.store.bookmarks(), services.store.highlights()]),
        builder: (context, snap) {
          final d = snap.data;
          if (d == null) return const SizedBox.shrink();
          return ReadableWidth(
            child: ListView(padding: const EdgeInsets.all(16), children: [
              _Group(children: [
                ListTile(
                  leading: const Icon(Icons.menu_book_outlined),
                  title: Text(services.bible.translation.name),
                  subtitle: Text('${services.bible.verseCount} verses with a full-text search index and cross references'),
                  trailing: Text(formatBytes(d[0] as int)),
                ),
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: const Text('Your notes and study data'),
                  subtitle: Text('${(d[2] as List).length} notes · ${(d[3] as List).length} bookmarks · ${(d[4] as List).length} highlighted verses'),
                  trailing: Text(formatBytes(d[1] as int)),
                ),
              ]),
              const SizedBox(height: 16),
              Text(
                'The Bible text ships compressed inside the app and is unpacked once into an indexed database on first launch. '
                'Your own data is stored separately from Scripture text, on this device only.',
                style: TextStyle(color: context.muted, height: 1.45),
              ),
            ]),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------- backup

class BackupPage extends StatefulWidget {
  const BackupPage({super.key});
  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  bool _busy = false;

  String _stamp() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}-${two(n.month)}-${two(n.day)}-${two(n.hour)}${two(n.minute)}';
  }

  Future<void> _run(Future<void> Function() f) async {
    setState(() => _busy = true);
    try {
      await f();
    } catch (e) {
      if (mounted) toast(context, 'Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() => _run(() async {
        final json = const JsonEncoder.withIndent(' ').convert(await services.store.exportBackup());
        final name = await PlatformBridge.saveDocument('bible-by-cue-backup-${_stamp()}.json', 'application/json', utf8.encode(json));
        if (name != null && mounted) toast(context, 'Backup saved as $name');
      });

  Future<void> _exportNotes() => _run(() async {
        final notes = await services.store.notes(sort: NoteSort.created);
        if (notes.isEmpty) {
          if (mounted) toast(context, 'You have no notes to export yet.');
          return;
        }
        final md = notes.map((n) => noteAsMarkdown(n)).join('\n---\n\n');
        final name = await PlatformBridge.saveDocument('bible-by-cue-notes-${_stamp()}.md', 'text/markdown', utf8.encode(md));
        if (name != null && mounted) toast(context, '${notes.length} notes saved as $name');
      });

  Future<void> _restore() async {
    final file = await PlatformBridge.openDocument(['application/json', 'text/plain', 'application/octet-stream']);
    if (file == null || !mounted) return;
    Map<String, Object?> backup;
    try {
      backup = UserStore.decodeBackup(utf8.decode(file.bytes));
    } on FormatException catch (e) {
      toast(context, e.message);
      return;
    }
    final s = UserStore.summarize(backup);
    var replace = false;
    var settings = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, set) => AlertDialog(
          title: const Text('Restore backup'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(file.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              if (s.exportedAt != null) Text('Made ${shortDate(s.exportedAt!)} at ${timeOfDay(s.exportedAt!.hour * 60 + s.exportedAt!.minute)}'),
              const SizedBox(height: 6),
              Text([plural(s.notes, 'note'), plural(s.bookmarks, 'bookmark'), plural(s.highlights, 'highlight'), plural(s.folders, 'folder')].join(' · ')),
              const SizedBox(height: 12),
              RadioGroup<bool>(
                groupValue: replace,
                onChanged: (v) => set(() => replace = v ?? false),
                child: const Column(children: [
                  RadioListTile(
                    contentPadding: EdgeInsets.zero,
                    value: false,
                    title: Text('Merge (recommended)'),
                    subtitle: Text('Adds what is missing. Nothing on this device is deleted; a note that differs is added as a separate copy.'),
                  ),
                  RadioListTile(
                    contentPadding: EdgeInsets.zero,
                    value: true,
                    title: Text('Replace'),
                    subtitle: Text('Makes this device match the backup. Your current data is first saved automatically as a safety copy.'),
                  ),
                ]),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: settings,
                onChanged: (v) => set(() => settings = v ?? false),
                title: const Text('Also restore settings'),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(replace ? 'Replace my data' : 'Merge')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await _run(() async {
      final report = await services.store.restoreBackup(backup, replace: replace, restoreSettings: settings);
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Restore complete'),
          content: Text([
            report.toString(),
            if (report.safetyBackup != null) 'Your previous data was saved as ${report.safetyBackup} inside the app.',
            if (settings) 'Restart the app to apply restored settings everywhere.',
          ].join('\n\n')),
          actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done'))],
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Back up and restore')),
      body: ReadableWidth(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (_busy) const LinearProgressIndicator(),
          Text(
            'Backups are saved where you choose, for example Downloads, a memory card or a cloud folder you use. '
            'Each backup gets a new, dated file name, and the system will not overwrite an existing file without asking.',
            style: TextStyle(color: context.muted, height: 1.45),
          ),
          const SizedBox(height: 16),
          _Group(children: [
            ListTile(
              leading: const Icon(Icons.save_alt),
              title: const Text('Create a backup'),
              subtitle: const Text('A single .json file with notes, folders, bookmarks, highlights, plans and settings'),
              onTap: _busy ? null : _export,
            ),
            ListTile(
              leading: const Icon(Icons.restore),
              title: const Text('Restore from a backup'),
              subtitle: const Text('Choose merge or replace before anything changes'),
              onTap: _busy ? null : _restore,
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('Export all notes as Markdown'),
              subtitle: const Text('Readable in any text editor'),
              onTap: _busy ? null : _exportNotes,
            ),
          ]),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------- privacy & about

class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.wifi_off, 'Works without internet', 'The app does not request internet access. Reading, search, notes and previews all run on your device.'),
      (Icons.phone_android, 'Your notes stay on this device', 'Notes, bookmarks, highlights and reading history are stored only in the app’s private storage.'),
      (Icons.no_accounts_outlined, 'No account, no tracking', 'There is no sign-in, no analytics and no advertising.'),
      (Icons.cloud_off_outlined, 'Not included in cloud backups', 'The app opts out of automatic Android cloud backup, so nothing is uploaded without you. Use “Back up and restore” to keep your own copy.'),
      (Icons.lock_outline, 'About encryption', 'Data is protected by Android’s app sandbox and device encryption. The app does not add its own database encryption.'),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy')),
      body: ReadableWidth(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          for (final (icon, title, body) in items)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(vertical: 6),
              leading: Icon(icon, color: context.colors.primary),
              title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Padding(padding: const EdgeInsets.only(top: 4), child: Text(body, style: const TextStyle(height: 1.4))),
            ),
        ]),
      ),
    );
  }
}

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ReadableWidth(
        child: ListView(padding: const EdgeInsets.all(24), children: [
          const Center(child: AppMark(size: 84)),
          const SizedBox(height: 16),
          Text('Bible by Cue', textAlign: TextAlign.center, style: context.text.headlineMedium),
          const SizedBox(height: 4),
          Text('Created by Cue', textAlign: TextAlign.center, style: context.text.titleMedium?.copyWith(color: context.colors.secondary)),
          const SizedBox(height: 4),
          Text('Version $appVersion', textAlign: TextAlign.center, style: TextStyle(color: context.muted)),
          const SizedBox(height: 24),
          Text('A calm, private Bible for reading, study and sermon notes — fully offline.',
              textAlign: TextAlign.center, style: context.text.bodyLarge?.copyWith(height: 1.5)),
          const SectionHeader('Sources'),
          const _Source(
            'World English Bible (WEB)',
            'Public domain, 2020 stable text from eBible.org. “World English Bible” is a trademark of eBible.org; '
                'the text is included without changes. 66 books of the Protestant canon.',
          ),
          const _Source(
            'Cross references',
            'From OpenBible.info, licensed under Creative Commons Attribution (CC BY). '
                'Filtered to references with at least five community votes, up to twelve per verse.',
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () => showLicensePage(context: context, applicationName: 'Bible by Cue', applicationVersion: appVersion),
            child: const Text('Open-source licences'),
          ),
        ]),
      ),
    );
  }
}

class _Source extends StatelessWidget {
  final String title;
  final String body;
  const _Source(this.title, this.body);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(body, style: TextStyle(color: context.muted, height: 1.45)),
        ]),
      );
}

/// The app's mark: an open book with a small cross, drawn in code so no image assets are needed.
class AppMark extends StatelessWidget {
  final double size;
  const AppMark({super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: Palette.forest, borderRadius: BorderRadius.circular(size * 0.28)),
      child: CustomPaint(painter: _MarkPainter()),
    );
  }
}

class _MarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width;
    final page = Paint()..color = Palette.cream;
    final left = Path()
      ..moveTo(w * 0.5, w * 0.36)
      ..quadraticBezierTo(w * 0.36, w * 0.28, w * 0.2, w * 0.32)
      ..lineTo(w * 0.2, w * 0.74)
      ..quadraticBezierTo(w * 0.36, w * 0.7, w * 0.5, w * 0.78)
      ..close();
    final right = Path()
      ..moveTo(w * 0.5, w * 0.36)
      ..quadraticBezierTo(w * 0.64, w * 0.28, w * 0.8, w * 0.32)
      ..lineTo(w * 0.8, w * 0.74)
      ..quadraticBezierTo(w * 0.64, w * 0.7, w * 0.5, w * 0.78)
      ..close();
    canvas.drawPath(left, page);
    canvas.drawPath(right, page..color = Palette.cream.withValues(alpha: 0.88));
    final cross = Paint()..color = const Color(0xFFE5D7A8);
    canvas.drawRRect(RRect.fromLTRBR(w * 0.475, w * 0.1, w * 0.525, w * 0.3, Radius.circular(w * 0.02)), cross);
    canvas.drawRRect(RRect.fromLTRBR(w * 0.42, w * 0.155, w * 0.58, w * 0.2, Radius.circular(w * 0.02)), cross);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

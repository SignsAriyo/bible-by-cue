// Phase 2: runs in a fresh process after app_test.dart and confirms everything persisted.
import 'package:bible_by_cue/core/app_services.dart';
import 'package:bible_by_cue/core/books.dart';
import 'package:bible_by_cue/main.dart' as app;
import 'package:bible_by_cue/ui/note_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Bible by Cue persistence after restart (phase 2)', (tester) async {
    final launch = Stopwatch()..start();
    app.main();
    await pumpUntil(tester, () => find.byType(app.AppShell).evaluate().isNotEmpty, timeout: const Duration(seconds: 60));
    log('METRIC warm_db_startup_to_shell_ms=${launch.elapsedMilliseconds}');
    final s = Services.I;
    final prefs = await s.store.loadPrefs();
    expect(prefs['test.phase1'], 'done', reason: 'phase 1 ran first');

    // Test C: long formatted note survives the restart byte for byte.
    final notes = await s.store.notes(query: 'PERSIST: Long sermon');
    final n = notes.singleWhere((n) => n.uid == prefs['test.sermonUid']);
    expect(n.subtitle, 'Pastor Test');
    expect(n.body, startsWith('# Grace that is sufficient\n## Introduction\nOpening thoughts on **grace** and *faith*.'));
    expect(n.body, contains('## Point 120\n120. Main idea number 120'));
    expect(n.body, contains('- [x] apply point 2 this week'));
    expect(n.body, endsWith('x' * 20));
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    nav.push(MaterialPageRoute(builder: (_) => NoteEditorPage(noteId: n.id)));
    await pumpUntil(tester, () => find.byType(TextField).evaluate().length >= 3);
    await pumpFor(tester, const Duration(milliseconds: 300));
    expect(bodyController(tester).text, n.body);
    expect(find.text('PERSIST: Long sermon'), findsOneWidget);
    log('PASS C2 long sermon with headings, lists and checklists intact after restart (${n.body.length} chars)');
    await goBackToShell(tester);

    // Test F: bookmarks, comments and highlights survive.
    final bookmarks = await s.store.bookmarks();
    final rom = bookmarks.where((b) => b.startId == verseId(45, 8, 28)).toList();
    expect(rom, hasLength(1));
    expect(rom.single.comment, 'PERSIST comment: all things work together');
    expect(bookmarks.any((b) => b.startId == verseId(43, 3, 16) && b.endId == verseId(43, 3, 17)), isTrue);
    expect(bookmarks.any((b) => b.startId == verseId(19, 23, 4)), isTrue);
    final hl = await s.store.highlightsIn(verseId(19, 23, 0), verseId(19, 23, 999));
    expect(hl, {verseId(19, 23, 1): 1, verseId(19, 23, 2): 1});
    expect((await s.store.bookmarks(query: 'work together')).length, 1);
    log('PASS F2 bookmarks, comment search and highlights intact after restart');

    // Preferences and reading position survive.
    expect(s.settings.onboarded, isTrue);
    expect(s.settings.lastPosition, isNotNull);
    log('PASS F3 preferences and last reading position persisted (${s.settings.lastPosition})');
    log('METRIC bible_db_bytes=${await s.bible.fileSize()} user_db_bytes=${await s.store.fileSize()}');
  });
}

// Phase 1 of the on-device acceptance tests. Run with:
//   flutter test integration_test/app_test.dart -d <device>
// then restart_test.dart, which verifies data after a real process restart.
import 'package:bible_by_cue/core/app_services.dart';
import 'package:bible_by_cue/core/bible_repository.dart';
import 'package:bible_by_cue/core/books.dart';
import 'package:bible_by_cue/core/user_store.dart';
import 'package:bible_by_cue/main.dart' as app;
import 'package:bible_by_cue/ui/note_editor.dart';
import 'package:bible_by_cue/ui/note_text.dart';
import 'package:bible_by_cue/ui/reader_page.dart';
import 'package:bible_by_cue/ui/scripture_preview.dart';
import 'package:bible_by_cue/ui/search_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers.dart';

const testB = 'God is faithful. See John 3:16 and Romans 8:28–30. Read 1 Corinthians 13:4–7 for further study.';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Bible by Cue acceptance (phase 1)', (tester) async {
    final firstLaunch = !await BibleRepository.isInstalled(webTranslation);
    final launch = Stopwatch()..start();
    app.main();
    await pumpUntil(tester, () => find.byType(app.AppShell).evaluate().isNotEmpty || find.byType(app.WelcomePage).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 120));
    log('METRIC startup_to_ui_ms=${launch.elapsedMilliseconds} first_launch_db_build=$firstLaunch');
    if (find.byType(app.WelcomePage).evaluate().isNotEmpty) {
      await tapWhenReady(tester, find.text('Begin'));
      await pumpFor(tester, const Duration(milliseconds: 600));
    }
    expect(find.byType(app.AppShell), findsOneWidget);
    final s = Services.I;

    // ------------------------------------------------------------- Test A: complete offline Bible
    expect(s.bible.translation.abbreviation, 'WEB');
    expect(s.bible.verseCount, 31098);
    var chapters = 0;
    for (final b in books) {
      expect(s.bible.chapterCount(b.number), b.chapters, reason: b.name);
      chapters += s.bible.chapterCount(b.number);
    }
    expect(chapters, 1189);
    expect((await s.bible.verse(verseId(1, 1, 1)))!.text, startsWith('In the beginning, God created'));
    expect((await s.bible.verse(verseId(66, 22, 21)))!.text, contains('grace of the Lord Jesus Christ'));
    final sw = Stopwatch()..start();
    final ps119 = await s.bible.chapter(19, 119);
    log('METRIC chapter_load_ps119_ms=${sw.elapsedMilliseconds} verses=${ps119.length}');
    expect(ps119.length, 176);
    log('PASS A1 complete WEB text: ${s.bible.verseCount} verses, 1189 chapters');

    // Navigate through the UI: Bible tab -> Genesis -> chapter 1 -> next chapter.
    await tapWhenReady(tester, find.text('Bible').last);
    await tapWhenReady(tester, find.text('Genesis'));
    await tapWhenReady(tester, find.bySemanticsLabel('Genesis chapter 1'));
    await pumpUntil(tester, () => find.textContaining('In the beginning, God created', findRichText: true).evaluate().isNotEmpty);
    expect(find.byType(ReaderPage), findsOneWidget);
    await shot(binding, tester, 'A_reader_genesis1');
    await tapWhenReady(tester, find.text('Gen 2'));
    await pumpUntil(tester, () => find.text('Genesis 2').evaluate().isNotEmpty);
    log('PASS A2 reader opens Genesis 1 and moves to Genesis 2');
    await goBackToShell(tester);

    // ------------------------------------------------------------- Test B: Scripture preview
    final note = await s.store.createNote(title: 'Faithfulness', body: testB, kind: NoteKind.sermon);
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    nav.push(MaterialPageRoute(builder: (_) => NoteEditorPage(noteId: note.id)));
    await pumpUntil(tester, () => find.byWidgetPredicate((w) => w is TextField && w.controller is NoteTextController).evaluate().isNotEmpty);
    await pumpFor(tester, const Duration(milliseconds: 300));
    final body = bodyController(tester);
    final refs = body.references.where((m) => m.isValid).toList();
    expect(refs.map((m) => m.reference!.label), ['John 3:16', 'Romans 8:28–30', '1 Corinthians 13:4–7']);
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    final topInset = tester.view.padding.top / tester.view.devicePixelRatio;
    for (final (i, label, firstWords) in [
      (0, 'John 3:16', 'For God so loved the world'),
      (1, 'Romans 8:28–30', 'We know that all things work together'),
      (2, '1 Corinthians 13:4–7', 'Love is patient and is kind'),
    ]) {
      if (find.byType(ScripturePreviewSheet).evaluate().isNotEmpty) await closePreview(tester);
      await tapTextOffset(tester, refs[i].start + 2);
      final settleMs = await waitForSheet(tester);
      expect(find.byType(ScripturePreviewSheet), findsOneWidget, reason: label);
      final sheet = sheetRect(tester);
      final title = tester.getRect(find.descendant(of: find.byType(ScripturePreviewSheet), matching: find.text(label)));
      final verse = find.descendant(of: find.byType(ScripturePreviewSheet), matching: find.textContaining(firstWords, findRichText: true));
      expect(verse, findsOneWidget, reason: '$label text shown');
      final verseRect = tester.getRect(verse);
      final fraction = (sheet.height - topInset) / (screen.height - topInset);
      log('METRIC preview $label sheet_top=${sheet.top.toStringAsFixed(1)} title_top=${title.top.toStringAsFixed(1)} '
          'verse_top=${verseRect.top.toStringAsFixed(1)} inset=${topInset.toStringAsFixed(1)} height_fraction=${fraction.toStringAsFixed(2)} '
          'tap_to_settled_ms=$settleMs');
      expect(sheet.top, inInclusiveRange(-0.5, 0.5), reason: 'anchored to the top edge');
      expect(title.top - topInset, greaterThanOrEqualTo(0), reason: 'below the status bar');
      expect(title.top - topInset, lessThan(24), reason: 'reference is the first thing below the status bar');
      expect(verseRect.top - topInset, lessThan(90), reason: 'verse text starts immediately below the reference');
      expect(fraction, inInclusiveRange(0.65, 0.80));
      await shot(binding, tester, 'B_preview_${i + 1}');
      log('PASS B${i + 1} $label opens at top with text first');
    }
    // Navigate within the open preview without closing it.
    await tapWhenReady(tester, find.byTooltip('Previous reference in this note'));
    await pumpFor(tester, const Duration(milliseconds: 600));
    expect(find.descendant(of: find.byType(ScripturePreviewSheet), matching: find.text('Romans 8:28–30')), findsOneWidget);
    log('PASS B4 previous/next moves between references without closing');
    // Back button closes the preview, not the note.
    await tester.binding.handlePopRoute();
    await waitForSheetGone(tester);
    expect(find.byType(NoteEditorPage), findsOneWidget);
    log('PASS B5 back closes the preview and keeps the note open');

    // ------------------------------------------------------------- Test D: editing continuity
    final editable = find.descendant(of: find.byWidgetPredicate((w) => w is TextField && w.controller is NoteTextController), matching: find.byType(EditableText));
    await tapWhenReady(tester, editable);
    await pumpFor(tester, const Duration(milliseconds: 400));
    const cursorAt = 17; // just after "God is faithful. "
    body.selection = const TextSelection.collapsed(offset: cursorAt);
    await pumpFor(tester, const Duration(milliseconds: 100));
    // Insert text at the cursor the way an edit arrives from the keyboard, then park the cursor after it.
    body.value = TextEditingValue(
      text: body.text.replaceRange(cursorAt, cursorAt, 'UNSAVED '),
      selection: const TextSelection.collapsed(offset: cursorAt + 8),
    );
    await tester.pump();
    final beforeText = body.text;
    expect(beforeText, contains('faithful. UNSAVED See John'));
    expect(body.selection, const TextSelection.collapsed(offset: cursorAt + 8));
    final johnStart = body.references.firstWhere((m) => m.reference?.label == 'John 3:16').start;
    await tapTextOffset(tester, johnStart + 2);
    await waitForSheet(tester);
    expect(find.byType(ScripturePreviewSheet), findsOneWidget);
    await shot(binding, tester, 'D_preview_while_editing');
    await closePreview(tester);
    await pumpFor(tester, const Duration(milliseconds: 400));
    expect(body.text, beforeText);
    expect(body.selection, const TextSelection.collapsed(offset: cursorAt + 8));
    final focused = tester.state<EditableTextState>(editable).widget.focusNode.hasFocus;
    expect(focused, isTrue);
    log('PASS D cursor (offset ${body.selection.baseOffset}), unsaved text and focus preserved across preview');
    // Autosave runs after a short pause in typing.
    final saveClock = Stopwatch()..start();
    var saved = false;
    while (!saved && saveClock.elapsed < const Duration(seconds: 10)) {
      await pumpFor(tester, const Duration(milliseconds: 200));
      saved = (await s.store.note(note.id))!.body.contains('UNSAVED');
    }
    expect(saved, isTrue);
    log('METRIC autosave_after_ms<=${saveClock.elapsedMilliseconds}');
    log('PASS D2 autosave stored the edit');

    // ------------------------------------------------------------- Test G: invalid references
    body.value = const TextEditingValue(text: 'Points: 1, 2 and 3. Meet at 10:30. Psalm 151 and John 3:99 and Jude 2:1 and Rom 8:30-28.\nGenesis 51');
    await tester.pump();
    final bad = body.references;
    expect(bad.where((m) => m.isValid), isEmpty);
    expect(bad.length, 5);
    await tapTextOffset(tester, bad.first.start + 2);
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(find.byType(ScripturePreviewSheet), findsNothing);
    expect(find.textContaining('Psalms has 150 chapters'), findsOneWidget);
    await shot(binding, tester, 'G_invalid_reference');
    log('PASS G invalid references are flagged and never open a preview; numbers and times ignored');
    await goBackToShell(tester);

    // ------------------------------------------------------------- Test C: long formatted sermon (persistence verified in phase 2)
    final long = StringBuffer('# Grace that is sufficient\n## Introduction\nOpening thoughts on **grace** and *faith*.\n');
    for (var i = 1; i <= 120; i++) {
      long.writeln('## Point $i');
      long.writeln('$i. Main idea number $i, see Romans 8:28 and Psalm 23.');
      long.writeln('- supporting thought $i with **bold** and *italic* text');
      long.writeln('- [${i.isEven ? 'x' : ' '}] apply point $i this week');
      long.writeln();
    }
    final sermon = await s.store.createNote(title: 'PERSIST: Long sermon', subtitle: 'Pastor Test', body: long.toString(), kind: NoteKind.sermon);
    nav.push(MaterialPageRoute(builder: (_) => NoteEditorPage(noteId: sermon.id)));
    final open = Stopwatch()..start();
    await pumpUntil(tester, () => find.byWidgetPredicate((w) => w is TextField && w.controller is NoteTextController && w.controller!.text.startsWith('# Grace')).evaluate().isNotEmpty);
    log('METRIC long_note_chars=${long.length} open_ms=${open.elapsedMilliseconds}');
    await pumpFor(tester, const Duration(milliseconds: 300));
    final sc = bodyController(tester);
    final typing = Stopwatch()..start();
    for (var i = 0; i < 20; i++) {
      sc.value = TextEditingValue(text: '${sc.text}x', selection: TextSelection.collapsed(offset: sc.text.length + 1));
      await tester.pump();
    }
    log('METRIC long_note_20_keystrokes_ms=${typing.elapsedMilliseconds}');
    await pumpFor(tester, const Duration(milliseconds: 1200));
    await shot(binding, tester, 'C_long_sermon');
    await goBackToShell(tester);
    log('PASS C1 long formatted sermon (${long.length} chars) edits and autosaves');

    // ------------------------------------------------------------- Test E: search
    sw.reset();
    final shepherd = await s.bible.search('shepherd');
    log('METRIC search_word_ms=${sw.elapsedMilliseconds} total=${shepherd.total}');
    expect(shepherd.total, greaterThan(50));
    expect(shepherd.verses.any((v) => v.id == verseId(19, 23, 1)), isTrue);
    sw.reset();
    // The WEB renders the divine name as "Yahweh": Psalm 23:1 reads "Yahweh is my shepherd".
    final phrase = await s.bible.search('Yahweh is my shepherd', exactPhrase: true);
    log('METRIC search_phrase_ms=${sw.elapsedMilliseconds} total=${phrase.total}');
    expect(phrase.verses.map((v) => v.id), contains(verseId(19, 23, 1)));
    final nt = await s.bible.search('love', testament: 2);
    expect(nt.verses.every((v) => v.book >= 40), isTrue);
    final johnOnly = await s.bible.search('light', book: 43);
    expect(johnOnly.verses.every((v) => v.book == 43), isTrue);
    expect((await s.bible.search('God’s love')).total, greaterThan(0));
    log('PASS E1 word, exact phrase, testament and book filters return correct verses');
    nav.push(MaterialPageRoute(builder: (_) => const SearchPage()));
    await pumpUntil(tester, () => find.descendant(of: find.byType(SearchPage), matching: find.byType(TextField)).hitTestable().evaluate().isNotEmpty);
    await typeInto(tester, find.descendant(of: find.byType(SearchPage), matching: find.byType(TextField)).first, 'still small voice');
    await pumpUntil(tester, () => find.textContaining('1 Kings 19:12').evaluate().isNotEmpty);
    await shot(binding, tester, 'E_search');
    await tapWhenReady(tester, find.textContaining('1 Kings 19:12'));
    await pumpUntil(tester, () => find.text('1 Kings 19').evaluate().isNotEmpty);
    expect(find.byType(ReaderPage), findsOneWidget);
    log('PASS E2 search UI finds “still small voice” and opens 1 Kings 19');
    await goBackToShell(tester);
    nav.push(MaterialPageRoute(builder: (_) => const SearchPage()));
    await pumpUntil(tester, () => find.descendant(of: find.byType(SearchPage), matching: find.byType(TextField)).hitTestable().evaluate().isNotEmpty);
    await typeInto(tester, find.descendant(of: find.byType(SearchPage), matching: find.byType(TextField)).first, 'rom 8:28');
    await pumpUntil(tester, () => find.text('Open Romans 8:28').evaluate().isNotEmpty);
    log('PASS E3 typed reference offers direct navigation');
    await goBackToShell(tester);

    // ------------------------------------------------------------- Test F: saved content (verified after restart in phase 2)
    await s.store.addBookmark(verseId(45, 8, 28), verseId(45, 8, 28), comment: 'PERSIST comment: all things work together');
    await s.store.setHighlight([verseId(19, 23, 1), verseId(19, 23, 2)], 1);
    await s.store.addBookmark(verseId(43, 3, 16), verseId(43, 3, 17));
    nav.push(MaterialPageRoute(builder: (_) => const ReaderPage(book: 19, chapter: 23)));
    await pumpUntil(tester, () => find.bySemanticsLabel(RegExp(r'^Verse 4')).hitTestable().evaluate().isNotEmpty);
    await pumpFor(tester, const Duration(milliseconds: 500));
    await shot(binding, tester, 'F_highlights_psalm23');
    // Select a verse with a real tap and bookmark it from the selection bar.
    await tapWhenReady(tester, find.bySemanticsLabel(RegExp(r'^Verse 4\b')));
    await pumpUntil(tester, () => find.text('Psalm 23:4').evaluate().isNotEmpty);
    await shot(binding, tester, 'F_selection_bar');
    await tapWhenReady(tester, find.text('Bookmark'));
    await pumpFor(tester, const Duration(milliseconds: 800));
    expect((await s.store.bookmarksIn(verseId(19, 23, 4), verseId(19, 23, 4))).length, 1);
    log('PASS F1 bookmark, highlight and comment saved against book/chapter/verse ids');
    await goBackToShell(tester);

    // ------------------------------------------------------------- Test J: backup and restore
    final backup = await s.store.exportBackup();
    final notesBefore = (await s.store.notes()).length;
    await s.store.saveNote(note.id, title: 'Faithfulness (edited after backup)', subtitle: '', body: 'changed');
    final extra = await s.store.createNote(title: 'Created after backup', body: 'keep me');
    final merge = await s.store.restoreBackup(UserStore.decodeBackup(jsonRoundTrip(backup)), replace: false);
    final afterMerge = await s.store.notes();
    expect(afterMerge.any((n) => n.id == extra.id), isTrue, reason: 'merge keeps unrelated new data');
    expect(afterMerge.any((n) => n.title == 'Faithfulness (edited after backup)'), isTrue, reason: 'merge keeps local edit');
    expect(afterMerge.any((n) => n.title == 'Faithfulness (from backup)'), isTrue, reason: 'backup version restored as copy');
    expect(afterMerge.length, notesBefore + 2);
    log('PASS J1 merge restore: $merge');
    final replace = await s.store.restoreBackup(UserStore.decodeBackup(jsonRoundTrip(backup)), replace: true);
    final afterReplace = await s.store.notes();
    expect(afterReplace.length, notesBefore);
    expect(afterReplace.any((n) => n.title == 'Faithfulness'), isTrue);
    expect(replace.safetyBackup, isNotNull);
    log('PASS J2 replace restore matched backup; safety copy ${replace.safetyBackup}');
    expect(() => UserStore.decodeBackup('{"hello": 1}'), throwsFormatException);
    log('PASS J3 non-backup files are rejected');

    // Leave a marker for the restart test.
    await s.store.setPref('test.sermonUid', sermon.uid);
    await s.store.setPref('test.phase1', 'done');
    await pumpFor(tester, const Duration(milliseconds: 500));
  });
}

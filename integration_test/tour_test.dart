// Visual tour for device-usability review (Test H). Captures every main screen; run under
// different device settings (dark mode, font scale, tablet size, landscape).
//   flutter drive --driver=test_driver/integration_test.dart --target=integration_test/tour_test.dart --dart-define=TOUR=<label>
import 'package:bible_by_cue/core/app_services.dart';
import 'package:bible_by_cue/core/user_store.dart';
import 'package:bible_by_cue/main.dart' as app;
import 'package:bible_by_cue/ui/note_editor.dart';
import 'package:bible_by_cue/ui/reader_page.dart';
import 'package:bible_by_cue/ui/scripture_preview.dart';
import 'package:bible_by_cue/ui/search_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers.dart';

const label = String.fromEnvironment('TOUR', defaultValue: 'tour');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('visual tour', (tester) async {
    Future<void> snap(String name) => shot(binding, tester, '${label}_$name');
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    log('METRIC tour=$label logical_size=${size.width.toStringAsFixed(0)}x${size.height.toStringAsFixed(0)} '
        'text_scale=${tester.platformDispatcher.textScaleFactor} dark=${tester.platformDispatcher.platformBrightness == Brightness.dark}');
    app.main();
    var sawPreparing = false;
    await pumpUntil(tester, () {
      if (!sawPreparing && find.textContaining('Preparing your Bible').evaluate().isNotEmpty) {
        sawPreparing = true;
        log('SCREEN ${label}_preparing');
      }
      return find.byType(app.AppShell).evaluate().isNotEmpty || find.byType(app.WelcomePage).evaluate().isNotEmpty;
    }, timeout: const Duration(seconds: 120));
    if (find.byType(app.WelcomePage).evaluate().isNotEmpty) {
      await pumpFor(tester, const Duration(milliseconds: 600));
      await snap('welcome');
      await tapWhenReady(tester, find.text('Begin'));
      await pumpFor(tester, const Duration(milliseconds: 800));
    }
    final s = Services.I;
    if ((await s.store.notes()).isEmpty) {
      await s.store.createNote(
        title: 'Grace that is sufficient',
        subtitle: 'Sunday service',
        kind: NoteKind.sermon,
        body: '**Preacher:** Pastor James\n**Main Scripture:** 2 Corinthians 12:9\n\n## Introduction\n'
            'God’s grace is sufficient for us. See 2 Corinthians 12:9. We must learn to trust Him even in difficult '
            'seasons. Read Romans 8:28 as well.\n\n## Main points\n1. Grace meets us in weakness — Psalm 23\n'
            '2. Love is patient and kind, 1 Cor. 13:4–7\n\n## Prayer points\n- [x] Thank God for His faithfulness\n'
            '- [ ] Pray for the sick in our church\n',
      );
      await s.store.addBookmark(45008028, 45008028, comment: 'All things work together for good.');
      await s.store.setHighlight([43003016, 43003017], 0);
    }
    await pumpFor(tester, const Duration(milliseconds: 800));
    await snap('home');

    await tapNav(tester, 'Bible');
    await pumpFor(tester, const Duration(milliseconds: 600));
    await tapWhenReady(tester, find.text('Genesis'));
    await pumpFor(tester, const Duration(milliseconds: 600));
    await snap('bible_books');

    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    nav.push(MaterialPageRoute(builder: (_) => const ReaderPage(book: 43, chapter: 3, focusStart: 43003016, focusEnd: 43003016)));
    await pumpUntil(tester, () => find.bySemanticsLabel(RegExp(r'^Verse 16')).evaluate().isNotEmpty);
    await pumpFor(tester, const Duration(milliseconds: 1200));
    await snap('reader');
    await tapWhenReady(tester, find.bySemanticsLabel(RegExp(r'^Verse 16')));
    await pumpFor(tester, const Duration(milliseconds: 600));
    await snap('reader_selection');
    await tapWhenReady(tester, find.text('Clear'));
    await tapWhenReady(tester, find.byTooltip('Text settings'));
    await pumpFor(tester, const Duration(milliseconds: 700));
    await snap('reader_text_settings');
    await goBackToShell(tester);

    final note = (await s.store.notes(query: 'Grace that is sufficient')).first;
    nav.push(MaterialPageRoute(builder: (_) => NoteEditorPage(noteId: note.id)));
    await pumpUntil(tester, () => find.byType(TextField).evaluate().length >= 3);
    await pumpFor(tester, const Duration(milliseconds: 800));
    await snap('note_editor');
    final body = bodyController(tester);
    final m = body.references.firstWhere((r) => r.isValid);
    await tapTextOffset(tester, m.start + 2);
    await waitForSheet(tester);
    expect(find.byType(ScripturePreviewSheet), findsOneWidget);
    await snap('note_preview');
    await closePreview(tester);
    await goBackToShell(tester);

    await tapNav(tester, 'Notes');
    await pumpFor(tester, const Duration(milliseconds: 700));
    await snap('notes');
    await tapNav(tester, 'Saved');
    await pumpFor(tester, const Duration(milliseconds: 1000));
    await snap('saved');

    nav.push(MaterialPageRoute(builder: (_) => const SearchPage()));
    await pumpUntil(tester, () => find.descendant(of: find.byType(SearchPage), matching: find.byType(TextField)).hitTestable().evaluate().isNotEmpty);
    await typeInto(tester, find.descendant(of: find.byType(SearchPage), matching: find.byType(TextField)).first, 'faith hope love');
    await pumpUntil(tester, () => find.textContaining('verse').evaluate().isNotEmpty);
    await pumpFor(tester, const Duration(milliseconds: 800));
    await snap('search');
    await goBackToShell(tester);

    await tapNav(tester, 'Settings');
    await pumpFor(tester, const Duration(milliseconds: 700));
    await snap('settings');
    final about = find.text('Created by Cue · version 1.0.0');
    await tester.scrollUntilVisible(about, 200, scrollable: find.byType(Scrollable).hitTestable().last);
    await tapWhenReady(tester, about);
    await pumpFor(tester, const Duration(milliseconds: 800));
    await snap('about');
    await goBackToShell(tester);
    await tapNav(tester, 'Home');
    await pumpFor(tester, const Duration(milliseconds: 500));
    log('PASS H tour $label completed without layout exceptions');
  });
}

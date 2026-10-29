import 'dart:convert';

import 'package:bible_by_cue/main.dart' as app;
import 'package:bible_by_cue/ui/note_text.dart';
import 'package:bible_by_cue/ui/scripture_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void log(String s) => debugPrint('[cue-test] $s');

Future<void> pumpFor(WidgetTester t, Duration d) async {
  final end = DateTime.now().add(d);
  while (DateTime.now().isBefore(end)) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

Future<void> pumpUntil(WidgetTester t, bool Function() cond, {Duration timeout = const Duration(seconds: 20)}) async {
  final end = DateTime.now().add(timeout);
  while (!cond()) {
    if (DateTime.now().isAfter(end)) throw TestFailure('Timed out waiting for condition');
    await t.pump(const Duration(milliseconds: 100));
  }
}

String jsonRoundTrip(Map<String, Object?> m) => jsonEncode(m);

NoteTextController bodyController(WidgetTester t) =>
    t.widget<TextField>(find.byWidgetPredicate((w) => w is TextField && w.controller is NoteTextController)).controller!
        as NoteTextController;

/// Taps the note body at the on-screen position of a character offset, as a finger would.
Future<void> tapTextOffset(WidgetTester t, int offset) async {
  final field = find.byWidgetPredicate((w) => w is TextField && w.controller is NoteTextController);
  final state = t.state<EditableTextState>(find.descendant(of: field, matching: find.byType(EditableText)));
  final re = state.renderEditable;
  var rect = re.getLocalRectForCaret(TextPosition(offset: offset));
  // Scroll the position into view first.
  re.showOnScreen(rect: rect.inflate(80));
  await t.pump(const Duration(milliseconds: 300));
  rect = re.getLocalRectForCaret(TextPosition(offset: offset));
  final pos = re.localToGlobal(rect.center + const Offset(4, 0));
  await t.tapAt(pos);
}

Rect sheetRect(WidgetTester t) =>
    t.getRect(find.descendant(of: find.byType(ScripturePreviewSheet), matching: find.byType(Material)).first);

/// Waits until the preview sheet has finished sliding in; returns how long that took.
Future<int> waitForSheet(WidgetTester t) async {
  final sw = Stopwatch()..start();
  await pumpUntil(t, () => find.byType(ScripturePreviewSheet).evaluate().isNotEmpty && sheetRect(t).top.abs() < 0.5,
      timeout: const Duration(seconds: 10));
  await t.pump(const Duration(milliseconds: 50));
  return sw.elapsedMilliseconds;
}

Future<void> waitForSheetGone(WidgetTester t) =>
    pumpUntil(t, () => find.byType(ScripturePreviewSheet).evaluate().isEmpty, timeout: const Duration(seconds: 10));

Future<void> closePreview(WidgetTester t) async {
  await t.tap(find.descendant(of: find.byType(ScripturePreviewSheet), matching: find.byTooltip('Close preview')));
  await waitForSheetGone(t);
  await t.pump(const Duration(milliseconds: 100));
}

Future<void> goBackToShell(WidgetTester t) async {
  final nav = t.state<NavigatorState>(find.byType(Navigator).first);
  while (nav.canPop()) {
    nav.pop();
    await pumpFor(t, const Duration(milliseconds: 350));
  }
  // Wait until exiting pages have fully left the tree.
  await pumpUntil(t, () => find.byType(TextField).hitTestable().evaluate().isEmpty || find.byType(app.AppShell).hitTestable().evaluate().isNotEmpty);
  await pumpUntil(t, () => find.byWidgetPredicate((w) => w is TextField && w.controller is NoteTextController).evaluate().isEmpty);
  ScaffoldMessenger.of(t.element(find.byType(app.AppShell))).clearSnackBars();
  await pumpFor(t, const Duration(milliseconds: 200));
}

Future<void> shot(IntegrationTestWidgetsFlutterBinding b, WidgetTester t, String name) async {
  // Screenshots are captured by the host with adb; this marker tells it when.
  await t.pump();
  log('SCREEN $name');
  await pumpFor(t, const Duration(milliseconds: 1200));
}

/// Taps [f] once it is laid out and actually receives pointer events (slow devices may need a few frames).
Future<void> tapWhenReady(WidgetTester t, Finder f) async {
  await pumpUntil(t, () => f.hitTestable().evaluate().isNotEmpty, timeout: const Duration(seconds: 15));
  await t.pump(const Duration(milliseconds: 100));
  await t.tap(f.hitTestable().first);
}

/// Enters text into a field through its controller and change callback. Works in profile and
/// release builds, where the test text-input channel is not available.
Future<void> typeInto(WidgetTester t, Finder field, String text) async {
  final w = t.widget<TextField>(field);
  w.controller!.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  w.onChanged?.call(text);
  await t.pump();
}

/// Taps a main navigation destination, whether shown with labels or as a compact icon rail.
Future<void> tapNav(WidgetTester t, String label) async {
  final text = find.text(label).hitTestable();
  await tapWhenReady(t, text.evaluate().isNotEmpty ? text.last : find.byTooltip(label));
}

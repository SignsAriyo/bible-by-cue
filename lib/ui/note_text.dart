import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/reference.dart';

const _h1 = 1, _h2 = 2, _h3 = 4, _marker = 8, _bold = 16, _italic = 32, _checked = 64, _quote = 128;
const _ref = 256, _badRef = 512, _composing = 1024, _listMark = 2048;

final _blockPrefix = RegExp(r'^(#{1,3} |- \[[ xX]\] |[-*•] |\d{1,3}[.)] |> )');
final _boldRe = RegExp(r'\*\*(?=\S)(.+?)(?<=\S)\*\*');
final _italicRe = RegExp(r'(?<![*\w])\*(?=[^\s*])([^*\n]+?)(?<=\S)\*(?![*\w])');

/// Editing controller for notes. The stored text is light Markdown so formatting survives
/// saving, searching and exporting; this controller renders it with live styling and
/// recognises Scripture references so they can be tapped.
class NoteTextController extends TextEditingController {
  final Versification Function() versification;
  NoteTextController({super.text, required this.versification});

  String? _parsedFor;
  List<ReferenceMatch> _matches = const [];
  final Map<int, TextStyle> _styleCache = {};
  Brightness? _cacheBrightness;
  TextStyle? _cacheBase;

  /// Per-line analysis keyed by the line's text. References never span lines, so while typing
  /// only the edited line is re-analysed; long sermons stay responsive.
  final Map<String, _LineInfo> _lines = {};

  _LineInfo _line(String line) {
    final hit = _lines[line];
    if (hit != null) return hit;
    if (_lines.length > 4000) _lines.clear();
    return _lines[line] = _LineInfo.analyze(line, versification());
  }

  List<ReferenceMatch> get references {
    if (_parsedFor != text) {
      final t = text;
      final out = <ReferenceMatch>[];
      var start = 0;
      while (start <= t.length) {
        final nl = t.indexOf('\n', start);
        final end = nl < 0 ? t.length : nl;
        for (final r in _line(t.substring(start, end)).refs) {
          out.add(ReferenceMatch(start + r.start, start + r.end, r.reference, r.error));
        }
        if (nl < 0) break;
        start = nl + 1;
      }
      _matches = out;
      _parsedFor = t;
    }
    return _matches;
  }

  /// Forces references to be re-validated, e.g. after switching translation.
  void invalidateReferences() {
    _lines.clear();
    _parsedFor = null;
    notifyListeners();
  }

  /// The reference whose text strictly contains [offset] (taps at either edge are treated as cursor placement).
  ReferenceMatch? referenceAt(int offset) {
    for (final m in references) {
      if (m.start < offset && offset < m.end) return m;
      if (m.start >= offset) break;
    }
    return null;
  }

  ({int start, int end}) _lineAt(int offset) {
    final s = text.lastIndexOf('\n', offset - 1 < 0 ? 0 : offset - 1);
    final start = offset == 0 ? 0 : s + 1;
    final e = text.indexOf('\n', offset);
    return (start: start, end: e < 0 ? text.length : e);
  }

  /// Start of a checklist box if [offset] falls on the "- [ ]" marker of its line.
  int? checkboxAt(int offset) {
    final l = _lineAt(offset);
    final line = text.substring(l.start, l.end);
    if (!RegExp(r'^- \[[ xX]\] ').hasMatch(line)) return null;
    return offset - l.start <= 5 ? l.start : null;
  }

  void toggleCheckbox(int lineStart) {
    final checked = text[lineStart + 3] != ' ';
    final sel = selection;
    value = value.copyWith(
      text: text.replaceRange(lineStart + 3, lineStart + 4, checked ? ' ' : 'x'),
      selection: sel,
      composing: TextRange.empty,
    );
  }

  // ------------------------------------------------------------------ editing commands

  void replaceSelection(String insert, {int? cursorOffsetFromStart}) {
    final sel = selection.isValid ? selection : TextSelection.collapsed(offset: text.length);
    final newText = text.replaceRange(sel.start, sel.end, insert);
    final caret = sel.start + (cursorOffsetFromStart ?? insert.length);
    value = TextEditingValue(text: newText, selection: TextSelection.collapsed(offset: caret));
  }

  /// Wraps the selection with [marker] (e.g. "**"), or removes it when already wrapped.
  void toggleInline(String marker) {
    final sel = selection.isValid ? selection : TextSelection.collapsed(offset: text.length);
    final n = marker.length;
    if (sel.isCollapsed) {
      replaceSelection('$marker$marker', cursorOffsetFromStart: n);
      return;
    }
    final inner = text.substring(sel.start, sel.end);
    final before = sel.start >= n ? text.substring(sel.start - n, sel.start) : '';
    final after = sel.end + n <= text.length ? text.substring(sel.end, sel.end + n) : '';
    if (before == marker && after == marker) {
      final t = text.replaceRange(sel.end, sel.end + n, '').replaceRange(sel.start - n, sel.start, '');
      value = TextEditingValue(text: t, selection: TextSelection(baseOffset: sel.start - n, extentOffset: sel.end - n));
    } else if (inner.startsWith(marker) && inner.endsWith(marker) && inner.length >= 2 * n) {
      final t = text.replaceRange(sel.start, sel.end, inner.substring(n, inner.length - n));
      value = TextEditingValue(text: t, selection: TextSelection(baseOffset: sel.start, extentOffset: sel.end - 2 * n));
    } else {
      final t = text.replaceRange(sel.start, sel.end, '$marker$inner$marker');
      value = TextEditingValue(text: t, selection: TextSelection(baseOffset: sel.start + n, extentOffset: sel.end + n));
    }
  }

  /// Applies or removes a block prefix ("# ", "- ", "1. ", "- [ ] ") on every selected line.
  void toggleBlock(String prefix, {bool numbered = false}) {
    final sel = selection.isValid ? selection : TextSelection.collapsed(offset: text.length);
    final first = _lineAt(sel.start).start;
    final last = _lineAt(sel.end).end;
    final lines = text.substring(first, last).split('\n');
    bool has(String l) => numbered ? RegExp(r'^\d{1,3}[.)] ').hasMatch(l) : l.startsWith(prefix);
    final remove = lines.every(has);
    var n = 0;
    final out = [
      for (final l in lines)
        if (remove)
          l.replaceFirst(_blockPrefix, '')
        else
          '${numbered ? '${++n}. ' : prefix}${l.replaceFirst(_blockPrefix, '')}'
    ].join('\n');
    final t = text.replaceRange(first, last, out);
    final delta = out.length - (last - first);
    value = TextEditingValue(
      text: t,
      selection: sel.isCollapsed
          ? TextSelection.collapsed(offset: (sel.end + delta).clamp(first, first + out.length))
          : TextSelection(baseOffset: first, extentOffset: first + out.length),
    );
  }

  // ------------------------------------------------------------------ rendering

  TextStyle _style(TextStyle base, int mask, ColorScheme c) {
    return _styleCache.putIfAbsent(mask, () {
      var s = base;
      final size = base.fontSize ?? 17;
      if (mask & _h1 != 0) s = s.copyWith(fontSize: size * 1.5, fontWeight: FontWeight.w700, height: 1.35);
      if (mask & _h2 != 0) s = s.copyWith(fontSize: size * 1.25, fontWeight: FontWeight.w700, height: 1.4);
      if (mask & _h3 != 0) s = s.copyWith(fontSize: size * 1.08, fontWeight: FontWeight.w700);
      if (mask & _bold != 0) s = s.copyWith(fontWeight: FontWeight.w700);
      if (mask & _italic != 0) s = s.copyWith(fontStyle: FontStyle.italic);
      if (mask & _quote != 0) s = s.copyWith(fontStyle: FontStyle.italic, color: c.onSurfaceVariant);
      if (mask & _checked != 0) {
        s = s.copyWith(color: c.onSurfaceVariant, decoration: TextDecoration.lineThrough, decorationColor: c.onSurfaceVariant);
      }
      if (mask & _marker != 0) s = s.copyWith(color: c.onSurfaceVariant.withValues(alpha: 0.55), fontWeight: FontWeight.w400);
      if (mask & _listMark != 0) s = s.copyWith(color: c.primary, fontWeight: FontWeight.w700);
      final decorations = <TextDecoration>[];
      if (mask & _ref != 0) {
        s = s.copyWith(color: c.primary, fontWeight: FontWeight.w600, decorationColor: c.primary.withValues(alpha: 0.6), decorationThickness: 1.6);
        decorations.add(TextDecoration.underline);
      }
      if (mask & _badRef != 0) {
        s = s.copyWith(decorationStyle: TextDecorationStyle.wavy, decorationColor: c.tertiary);
        decorations.add(TextDecoration.underline);
      }
      if (mask & _composing != 0) decorations.add(TextDecoration.underline);
      if (mask & _checked != 0) decorations.add(TextDecoration.lineThrough);
      if (decorations.isNotEmpty) s = s.copyWith(decoration: TextDecoration.combine(decorations));
      return s;
    });
  }

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    final base = style ?? const TextStyle();
    final scheme = Theme.of(context).colorScheme;
    if (_cacheBrightness != scheme.brightness || _cacheBase != base) {
      _styleCache.clear();
      _cacheBrightness = scheme.brightness;
      _cacheBase = base;
    }
    final t = text;
    if (t.isEmpty) return TextSpan(style: base, text: '');
    final composing = withComposing && value.isComposingRangeValid ? value.composing : TextRange.empty;
    final spans = <TextSpan>[];
    var start = 0;
    while (start <= t.length) {
      final nl = t.indexOf('\n', start);
      final end = nl < 0 ? t.length : nl;
      final lineText = t.substring(start, end);
      var info = _line(lineText);
      if (composing.isValid && !composing.isCollapsed && composing.start < end + 1 && composing.end > start) {
        info = info.withComposing(composing.start - start, composing.end - start);
      }
      var runStart = 0;
      for (var i = 0; i < info.runEnds.length; i++) {
        final runEnd = info.runEnds[i];
        final mask = info.runMasks[i];
        spans.add(TextSpan(text: lineText.substring(runStart, runEnd), style: mask == 0 ? null : _style(base, mask, scheme)));
        runStart = runEnd;
      }
      if (nl < 0) break;
      spans.add(const TextSpan(text: '\n'));
      start = nl + 1;
    }
    return TextSpan(style: base, children: spans);
  }
}

/// Styling runs and references for a single line of a note.
class _LineInfo {
  final List<int> runEnds;
  final List<int> runMasks;
  final List<ReferenceMatch> refs;
  final Uint16List _mask;

  _LineInfo(this._mask, this.refs) : runEnds = [], runMasks = [] {
    for (var i = 1; i <= _mask.length; i++) {
      if (i == _mask.length || _mask[i] != _mask[i - 1]) {
        runEnds.add(i);
        runMasks.add(_mask[i - 1]);
      }
    }
  }

  _LineInfo withComposing(int from, int to) {
    final m = Uint16List.fromList(_mask);
    for (var i = from < 0 ? 0 : from; i < to && i < m.length; i++) {
      m[i] |= _composing;
    }
    return _LineInfo(m, refs);
  }

  static _LineInfo analyze(String line, Versification v) {
    final mask = Uint16List(line.length);
    void mark(int from, int to, int bit) {
      for (var i = from; i < to && i < line.length; i++) {
        mask[i] |= bit;
      }
    }

    var contentStart = 0;
    final p = _blockPrefix.firstMatch(line);
    if (p != null) {
      final pre = p[0]!;
      final end = pre.length;
      if (pre.startsWith('#')) {
        mark(0, line.length, pre.length == 2 ? _h1 : (pre.length == 3 ? _h2 : _h3));
        mark(0, end, _marker);
      } else if (pre.startsWith('- [')) {
        mark(0, end, _listMark);
        if (pre[3] != ' ') mark(end, line.length, _checked);
      } else if (pre.startsWith('>')) {
        mark(0, line.length, _quote);
        mark(0, end, _marker);
      } else {
        mark(0, end, _listMark);
      }
      contentStart = end;
    }
    final content = line.substring(contentStart);
    for (final m in _boldRe.allMatches(content)) {
      mark(contentStart + m.start, contentStart + m.end, _bold);
      mark(contentStart + m.start, contentStart + m.start + 2, _marker);
      mark(contentStart + m.end - 2, contentStart + m.end, _marker);
    }
    for (final m in _italicRe.allMatches(content)) {
      mark(contentStart + m.start, contentStart + m.end, _italic);
      mark(contentStart + m.start, contentStart + m.start + 1, _marker);
      mark(contentStart + m.end - 1, contentStart + m.end, _marker);
    }
    final refs = line.isEmpty ? const <ReferenceMatch>[] : findReferences(line, v);
    for (final r in refs) {
      mark(r.start, r.end, r.isValid ? _ref : _badRef);
    }
    return _LineInfo(mask, refs);
  }
}

/// Continues bullet, numbered and checklist lines when Enter is pressed, and ends the
/// list when Enter is pressed on an empty item.
class ListContinuationFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final sel = newValue.selection;
    if (!sel.isCollapsed || newValue.text.length != oldValue.text.length + 1 || sel.start < 1) return newValue;
    final t = newValue.text;
    if (t[sel.start - 1] != '\n') return newValue;
    final nlAt = sel.start - 1;
    final prevStart = t.lastIndexOf('\n', nlAt - 1) + 1;
    final prev = t.substring(prevStart, nlAt);
    final m = RegExp(r'^(- \[[ xX]\] |[-*•] |(\d{1,3})([.)]) |> )(.*)$').firstMatch(prev);
    if (m == null) return newValue;
    if (m[4]!.trim().isEmpty) {
      // Empty item: remove the marker and the new line, ending the list.
      final text = t.replaceRange(prevStart, nlAt + 1, '');
      return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: prevStart));
    }
    String next;
    if (m[2] != null) {
      next = '${int.parse(m[2]!) + 1}${m[3]} ';
    } else if (m[1]!.startsWith('- [')) {
      next = '- [ ] ';
    } else {
      next = m[1]!;
    }
    final text = t.replaceRange(sel.start, sel.start, next);
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: sel.start + next.length));
  }
}

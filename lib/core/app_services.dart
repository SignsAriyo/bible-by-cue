import 'package:flutter/material.dart';

import 'bible_repository.dart';
import 'user_store.dart';

/// User-adjustable preferences, persisted in the private user database.
class AppSettings extends ChangeNotifier {
  final UserStore _store;
  final Map<String, String> _p;
  AppSettings(this._store, this._p);

  String _get(String k, String d) => _p[k] ?? d;
  void _set(String k, Object v) {
    _p[k] = '$v';
    _store.setPref(k, '$v');
    notifyListeners();
  }

  ThemeMode get themeMode => ThemeMode.values.firstWhere((m) => m.name == _get('theme', 'system'), orElse: () => ThemeMode.system);
  set themeMode(ThemeMode m) => _set('theme', m.name);

  double get fontSize => double.tryParse(_get('fontSize', '19')) ?? 19;
  set fontSize(double v) => _set('fontSize', v.clamp(14, 32).toStringAsFixed(0));

  double get lineHeight => double.tryParse(_get('lineHeight', '1.65')) ?? 1.65;
  set lineHeight(double v) => _set('lineHeight', v.clamp(1.2, 2.2).toStringAsFixed(2));

  bool get verseNumbers => _get('verseNumbers', '1') == '1';
  set verseNumbers(bool v) => _set('verseNumbers', v ? 1 : 0);

  bool get versePerLine => _get('versePerLine', '0') == '1';
  set versePerLine(bool v) => _set('versePerLine', v ? 1 : 0);

  bool get autoPreview => _get('autoPreview', '0') == '1';
  set autoPreview(bool v) => _set('autoPreview', v ? 1 : 0);

  bool get onboarded => _get('onboarded', '0') == '1';
  set onboarded(bool v) => _set('onboarded', v ? 1 : 0);

  String get translation => _get('translation', 'web');
  set translation(String v) => _set('translation', v);

  bool get reminderOn => _get('reminderOn', '0') == '1';
  int get reminderMinutes => int.tryParse(_get('reminderAt', '${7 * 60}')) ?? 420;
  void setReminder(bool on, int minutes) {
    _p['reminderAt'] = '$minutes';
    _store.setPref('reminderAt', '$minutes');
    _set('reminderOn', on ? 1 : 0);
  }

  /// Last reading position as a verse id.
  int? get lastPosition => int.tryParse(_get('lastPosition', ''));
  set lastPosition(int? id) {
    if (id == null) return;
    _p['lastPosition'] = '$id';
    _store.setPref('lastPosition', '$id');
  }

  String get noteSort => _get('noteSort', 'edited');
  set noteSort(String v) => _set('noteSort', v);

  List<String> get activePlans => _get('plans', '').split(',').where((s) => s.isNotEmpty).toList();
  set activePlans(List<String> v) => _set('plans', v.join(','));
}

/// Single place holding the open databases. Created once at start-up so databases are
/// never initialised twice.
class Services {
  static late Services I;

  BibleRepository bible;
  final UserStore store;
  final AppSettings settings;
  final ValueNotifier<int> bibleChanged = ValueNotifier(0);

  Services(this.bible, this.store, this.settings);

  Future<void> switchTranslation(Translation t) async {
    if (t.code == bible.translation.code) return;
    final next = await BibleRepository.open(t);
    final old = bible;
    bible = next;
    store.versification = next;
    settings.translation = t.code;
    bibleChanged.value++;
    await old.close();
  }
}

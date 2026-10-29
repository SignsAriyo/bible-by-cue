import 'package:flutter/services.dart';

/// Thin bridge to the Android share sheet, document picker and reminder scheduler.
class PlatformBridge {
  static const _c = MethodChannel('cue/platform');

  static Future<void> shareText(String text, {String? subject}) =>
      _c.invokeMethod('shareText', {'text': text, 'subject': subject});

  static Future<void> shareImage(Uint8List png, {String? text}) =>
      _c.invokeMethod('shareImage', {'bytes': png, 'text': text, 'name': 'bible-by-cue-verse.png'});

  /// Lets the user choose where to save a new file. Returns the saved file name, or null if cancelled.
  /// The system picker never overwrites an existing file silently.
  static Future<String?> saveDocument(String name, String mime, Uint8List bytes) =>
      _c.invokeMethod<String>('saveDocument', {'name': name, 'mime': mime, 'bytes': bytes});

  /// Lets the user pick a file to read. Returns null if cancelled.
  static Future<({String name, Uint8List bytes})?> openDocument(List<String> mimes) async {
    final r = await _c.invokeMapMethod<String, Object?>('openDocument', {'mimes': mimes});
    if (r == null) return null;
    return (name: r['name'] as String, bytes: r['bytes'] as Uint8List);
  }

  /// Returns false when notification permission was refused.
  static Future<bool> setReminder(bool enabled, int minutes) async =>
      await _c.invokeMethod<bool>('setReminder', {'enabled': enabled, 'hour': minutes ~/ 60, 'minute': minutes % 60}) ??
      false;
}

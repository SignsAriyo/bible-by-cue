import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../core/platform.dart';
import '../core/reference.dart';
import 'common.dart';
import 'theme.dart';

class _Template {
  final String name;
  final Color background;
  final Color text;
  final Color accent;
  const _Template(this.name, this.background, this.text, this.accent);
}

const _templates = [
  _Template('Cream', Palette.cream, Palette.ink, Palette.forest),
  _Template('Forest', Palette.forest, Colors.white, Color(0xFFE5D7A8)),
  _Template('Night', Color(0xFF16181A), Palette.moon, Palette.sage),
  _Template('Wine', Palette.burgundy, Colors.white, Color(0xFFF2D6C2)),
];

/// Renders a verse onto a simple, light-weight card and shares it as a PNG image.
Future<void> showShareCard(BuildContext context, Reference ref, String text) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ShareCardSheet(reference: ref, text: text),
  );
}

class _ShareCardSheet extends StatefulWidget {
  final Reference reference;
  final String text;
  const _ShareCardSheet({required this.reference, required this.text});

  @override
  State<_ShareCardSheet> createState() => _ShareCardSheetState();
}

class _ShareCardSheetState extends State<_ShareCardSheet> {
  final _key = GlobalKey();
  int _t = 0;
  bool _busy = false;

  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      final boundary = _key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1080 / boundary.size.width);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await PlatformBridge.shareImage(data!.buffer.asUint8List(), text: '${widget.reference.label} (${services.bible.translation.abbreviation})');
    } catch (e) {
      if (mounted) toast(context, 'Could not create the image: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _templates[_t];
    final long = widget.text.length > 280;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Share as image', style: context.text.titleLarge),
        const SizedBox(height: 12),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: RepaintBoundary(
              key: _key,
              child: AspectRatio(
                aspectRatio: 4 / 5,
                child: Container(
                  color: t.background,
                  padding: const EdgeInsets.fromLTRB(28, 32, 28, 22),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(width: 28, height: 3, color: t.accent),
                    const SizedBox(height: 18),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.topLeft,
                        child: SizedBox(
                          width: 304,
                          child: Text('“${widget.text}”',
                              style: TextStyle(fontFamily: readingFont, fontSize: long ? 17 : 22, height: 1.5, color: t.text)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(widget.reference.label,
                        style: TextStyle(color: t.accent, fontWeight: FontWeight.w700, fontSize: 15, letterSpacing: 0.3)),
                    const SizedBox(height: 10),
                    Text('${services.bible.translation.abbreviation} · Bible by Cue',
                        style: TextStyle(color: t.text.withValues(alpha: 0.6), fontSize: 10, letterSpacing: 1)),
                  ]),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(alignment: WrapAlignment.center, spacing: 8, children: [
          for (var i = 0; i < _templates.length; i++)
            ChoiceChip(
              avatar: CircleAvatar(backgroundColor: _templates[i].background, radius: 8),
              label: Text(_templates[i].name),
              selected: _t == i,
              onSelected: (_) => setState(() => _t = i),
            ),
        ]),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _busy ? null : _share,
          icon: const Icon(Icons.ios_share),
          label: const Text('Share image'),
        ),
      ]),
    );
  }
}

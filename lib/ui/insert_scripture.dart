import 'dart:async';

import 'package:flutter/material.dart';

import '../core/bible_repository.dart';
import '../core/reference.dart';
import 'common.dart';
import 'theme.dart';

class InsertChoice {
  final Reference reference;
  final String text;
  final bool withText;
  const InsertChoice(this.reference, this.text, this.withText);
}

/// Finds a passage by reference or by words, then inserts the reference alone or with its text.
Future<InsertChoice?> showInsertScripture(BuildContext context) {
  return showModalBottomSheet<InsertChoice>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: const _InsertSheet(),
    ),
  );
}

class _InsertSheet extends StatefulWidget {
  const _InsertSheet();
  @override
  State<_InsertSheet> createState() => _InsertSheetState();
}

class _InsertSheetState extends State<_InsertSheet> {
  final _ctl = TextEditingController();
  Timer? _debounce;
  QueryParse _parse = const QueryParse();
  Reference? _selected;
  List<Verse> _verses = const [];
  List<Verse> _results = const [];

  @override
  void dispose() {
    _debounce?.cancel();
    _ctl.dispose();
    super.dispose();
  }

  void _changed(String q) {
    setState(() => _parse = parseQuery(q, services.bible));
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _lookup);
  }

  Future<void> _lookup() async {
    final r = _parse.reference;
    if (r != null) {
      final vs = await services.bible.passage(r);
      if (mounted) {
        setState(() {
          _selected = r;
          _verses = vs;
          _results = const [];
        });
      }
      return;
    }
    final q = _ctl.text.trim();
    final res = q.length >= 3 && _parse.book == null ? await services.bible.search(q, limit: 30) : null;
    if (mounted) {
      setState(() {
        _selected = null;
        _verses = const [];
        _results = res?.verses ?? const [];
      });
    }
  }

  void _pick(Verse v) {
    final r = Reference.fromIds(v.id, v.id);
    _ctl.text = r.label;
    setState(() {
      _parse = QueryParse(reference: r);
      _selected = r;
      _verses = [v];
      _results = const [];
    });
  }

  @override
  Widget build(BuildContext context) {
    final sel = _selected;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Insert Scripture', style: context.text.titleLarge),
          const SizedBox(height: 12),
          TextField(
            controller: _ctl,
            autofocus: true,
            onChanged: _changed,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Reference or words, e.g. Rom 8:28 or “peace”'),
          ),
          if (_parse.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_parse.error!, style: TextStyle(color: context.colors.error)),
            ),
          if (_parse.reference == null && _parse.book != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Add a chapter and verse, e.g. ${_parse.book!.name} 1:1', style: TextStyle(color: context.muted)),
            ),
          const SizedBox(height: 8),
          if (sel != null && _verses.isNotEmpty) ...[
            Flexible(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: context.colors.surface, borderRadius: BorderRadius.circular(14)),
                child: SingleChildScrollView(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(sel.label, style: TextStyle(fontWeight: FontWeight.w700, color: context.colors.primary)),
                    const SizedBox(height: 6),
                    Text(passagePlain(_verses), style: const TextStyle(fontFamily: readingFont, fontSize: 16, height: 1.5)),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, InsertChoice(sel, passagePlain(_verses), false)),
                  child: const Text('Reference only'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, InsertChoice(sel, passagePlain(_verses), true)),
                  child: const Text('With verse text'),
                ),
              ),
            ]),
          ] else if (_results.isNotEmpty)
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _results.length,
                itemBuilder: (context, i) {
                  final v = _results[i];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(Reference.fromIds(v.id, v.id).label, style: TextStyle(fontWeight: FontWeight.w700, color: context.colors.primary)),
                    subtitle: Text(v.text, maxLines: 2, overflow: TextOverflow.ellipsis),
                    onTap: () => _pick(v),
                  );
                },
              ),
            )
          else if (_ctl.text.trim().length >= 3 && _parse.book == null)
            Padding(padding: const EdgeInsets.all(12), child: Text('No matches', style: TextStyle(color: context.muted))),
        ]),
      ),
    );
  }
}

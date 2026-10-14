/// Complete Staff webforms_delta.py equivalent. Dart indices count UTF-16 units.
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

List<(String, String, String)> parseStaffDelta(String text) {
  var pos = 0;
  final records = <(String, String, String)>[];
  while (pos < text.length) {
    final headers = <String>[];
    for (var i = 0; i < 3; i++) {
      final end = text.indexOf('|', pos);
      if (end < 0) throw const FormatException('Truncated delta header');
      headers.add(text.substring(pos, end));
      pos = end + 1;
    }
    if (!RegExp(r'^\d+$').hasMatch(headers[0]))
      throw const FormatException('Invalid delta length');
    final end = pos + int.parse(headers[0]);
    if (end >= text.length || text[end] != '|')
      throw const FormatException('Truncated delta payload');
    records.add((headers[1], headers[2], text.substring(pos, end)));
    pos = end + 1;
  }
  return records;
}

Document applyStaffDelta(Document previous, String text) {
  final records = parseStaffDelta(text), doc = html.parse(previous.outerHtml);
  var updated = false;
  for (final (kind, ident, content) in records) {
    if (kind == 'error' || kind == 'pageRedirect')
      throw const FormatException('Delta error or redirect');
    if (kind == 'updatePanel') {
      final panel = doc.getElementById(ident);
      if (panel == null) throw const FormatException('Unknown UpdatePanel');
      panel.nodes.clear();
      panel.nodes.addAll(html.parseFragment(content).nodes.toList());
      updated = true;
    } else if (kind == 'hiddenField') {
      final form = doc.querySelector('form');
      if (form == null)
        throw const FormatException('No form for delta hidden fields');
      var field = form
          .querySelectorAll('input')
          .where((e) => e.attributes['name'] == ident)
          .firstOrNull;
      if (field == null) {
        field = Element.tag('input')
          ..attributes.addAll({'type': 'hidden', 'name': ident, 'id': ident});
        form.append(field);
      }
      field.attributes['value'] = content;
    }
  }
  if (!updated) throw const FormatException('No panel in delta');
  return doc;
}

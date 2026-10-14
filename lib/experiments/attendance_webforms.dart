// Pure, offline-testable WebForms helpers. No HTTP or attendance mutation APIs.
import 'package:html/dom.dart' as dom;

class AttendanceWebForms {
  static const gridId = 'ContentPlaceHolder1_grd_Student';
  static const dateId = 'ContentPlaceHolder1_txtdate';
  static const showId = 'ContentPlaceHolder1_btn_Show';

  static String value(dom.Element e) => e.attributes['value'] ?? e.text.trim();

  static bool sessionExpired(Uri url, dom.Document doc) {
    final path = url.path.toLowerCase();
    return path.contains('officelogin') || path.contains('/public') ||
        path.contains('default.aspx') || path.contains('login.aspx') ||
        doc.getElementById('bodyContent_txtUName') != null ||
        doc.getElementById('txtUserId') != null;
  }

  static Map<String, String> successfulFields(dom.Element form) {
    final fields = <String, String>{};
    for (final el in form.querySelectorAll('input[name],select[name],textarea[name]')) {
      if (el.attributes.containsKey('disabled')) continue;
      final name = el.attributes['name'];
      if (name == null || name.isEmpty) continue;
      if (el.localName == 'input') {
        final kind = (el.attributes['type'] ?? 'text').toLowerCase();
        if (['submit', 'button', 'image', 'reset', 'file'].contains(kind)) continue;
        if (['checkbox', 'radio'].contains(kind) && !el.attributes.containsKey('checked')) continue;
        fields[name] = el.attributes['value'] ??
            (['checkbox', 'radio'].contains(kind) ? 'on' : '');
      } else if (el.localName == 'textarea') {
        fields[name] = el.text;
      } else {
        final options = el.querySelectorAll('option');
        if (options.isEmpty) continue;
        final selected = options.where((e) => e.attributes.containsKey('selected')).toList();
        fields[name] = value(selected.isNotEmpty ? selected.first : options.first);
      }
    }
    fields['__EVENTTARGET'] = '';
    fields['__EVENTARGUMENT'] = '';
    fields.remove('__ASYNCPOST');
    return fields;
  }

  static Map<String, String> navigation(dom.Element control, String action) {
    dom.Element? form = control;
    while (form != null && form.localName != 'form') {
      form = form.parent;
    }
    if (form == null) throw StateError('Attendance form missing');
    final fields = successfulFields(form);
    final name = control.attributes['name'];
    final kind = (control.attributes['type'] ?? 'submit').toLowerCase();
    if (action == 'SHOW') {
      if (control.id != showId) throw StateError('Unapproved Show control');
      if (name == null) throw StateError('Show name missing');
      if (kind == 'submit') {
        fields[name] = value(control);
      } else if (kind == 'image') {
        fields['$name.x'] = '0';
        fields['$name.y'] = '0';
      } else {
        throw StateError('Unexpected Show button type');
      }
    } else if (action == 'CLASS_ENTRY') {
      if (!RegExp(r'^ContentPlaceHolder1_grd_Student_btn_Entry_\d+$').hasMatch(control.id)) {
        throw StateError('Unapproved class link');
      }
      final script = '${control.attributes['href'] ?? ''} ${control.attributes['onclick'] ?? ''}';
      final match = RegExp(r'''(?:__doPostBack\s*\(|WebForm_PostBackOptions\s*\()\s*['"]([^'"]+)['"]''').firstMatch(script);
      if (match == null) throw StateError('Class entry postback target missing');
      fields['__EVENTTARGET'] = match.group(1)!;
    } else {
      throw StateError('Navigation action blocked');
    }
    fields['__READ_ONLY_ACTION'] = action;
    return fields;
  }

  static List<dom.Element> classEntries(dom.Document doc) {
    final grid = doc.getElementById(gridId);
    if (grid == null) throw StateError('Class summary grid missing');
    final pattern = RegExp(r'^ContentPlaceHolder1_grd_Student_hdn_ClassID_(\d+)$');
    final links = <dom.Element>[];
    for (final hidden in grid.querySelectorAll('input[id]')) {
      final match = pattern.firstMatch(hidden.id);
      if (match == null) continue;
      final entry = doc.getElementById('${gridId}_btn_Entry_${match.group(1)}');
      if (entry != null) links.add(entry);
    }
    return links;
  }

  static int classRowCount(dom.Document doc) {
    final grid = doc.getElementById(gridId);
    if (grid == null) throw StateError('Class summary grid missing');
    final pattern = RegExp(r'^ContentPlaceHolder1_grd_Student_hdn_ClassID_\d+$');
    return grid.querySelectorAll('input[id]').where((e) => pattern.hasMatch(e.id)).length;
  }

  static bool _hasAncestorId(dom.Element element, String id) {
    dom.Element? parent = element.parent;
    while (parent != null) {
      if (parent.id == id) return true;
      parent = parent.parent;
    }
    return false;
  }

  static dom.Element? _nearestTable(dom.Element element) {
    dom.Element? parent = element.parent;
    while (parent != null) {
      if (parent.localName == 'table') return parent;
      parent = parent.parent;
    }
    return null;
  }

  static int studentRowCount(dom.Document doc) {
    var best = 0;
    for (final table in doc.querySelectorAll('table')) {
      if (table.id == 'divStreamnotmapp_pop' ||
          _hasAncestorId(table, 'divStreamnotmapp_pop')) {
        continue;
      }
      final rows = table.querySelectorAll('tr').where((tr) {
        return _nearestTable(tr) == table &&
            tr.querySelector('input[type="radio"],input[type="checkbox"]') != null;
      }).length;
      if (rows > best) best = rows;
    }
    return best;
  }
}

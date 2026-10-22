/// Shared portal message extraction, retained from the HTTPX Incharge conversion.
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

String _text(dom.Node node) {
  final parts = <String>[];
  void visit(dom.Node n) {
    if (n is dom.Text) {
      final t = n.data.trim();
      if (t.isNotEmpty) parts.add(t);
    } else {
      if (n is dom.Element &&
          ['script', 'style', 'template'].contains(n.localName))
        return;
      for (final child in n.nodes) {
        visit(child);
      }
    }
  }

  visit(node);
  return parts.join(' ');
}

class SchoolPortalMessages {
  static final _confirm = RegExp(
    r'are\s+you\s+sure|do\s+you\s+want\s+to|क्या\s+आप\s+सुनिश्चित|क्या\s+आप\s+चाहते',
    caseSensitive: false,
  );
  static String _unescape(String text) => text.replaceAllMapped(
    RegExp(r'&(?:#[xX][a-fA-F\d]+|#\d+|[A-Za-z][A-Za-z\d]+);?'),
    (m) => html.parseFragment(m[0]!).text ?? m[0]!,
  );
  static String _js(String body) {
    try {
      return body.replaceAllMapped(
        RegExp(
          r'''\\(?:u[0-9a-fA-F]{4}|U[0-9a-fA-F]{8}|x[0-9a-fA-F]{2}|[0-7]{1,3}|[\s\S])''',
        ),
        (m) {
          final token = m[0]!.substring(1);
          if (token.startsWith('u') && token.length == 5)
            return String.fromCharCode(
              int.parse(token.substring(1), radix: 16),
            );
          if (token.startsWith('U') && token.length == 9)
            return String.fromCharCode(
              int.parse(token.substring(1), radix: 16),
            );
          if (token.startsWith('x') && token.length == 3)
            return String.fromCharCode(
              int.parse(token.substring(1), radix: 16),
            );
          if (RegExp(r'^[0-7]{1,3}$').hasMatch(token))
            return String.fromCharCode(int.parse(token, radix: 8));
          return {
                'n': '\n',
                'r': '\r',
                't': '\t',
                'b': '\b',
                'f': '\f',
                'a': '\u0007',
                'v': '\u000b',
                '\\': '\\',
                "'": "'",
                '"': '"',
                '\n': '',
              }[token] ??
              m[0]!;
        },
      );
    } catch (_) {
      return body;
    }
  }

  static List<String> parse(String document) =>
      document.isEmpty ? [] : fromDocument(html.parse(document));

  static List<String> fromDocument(dom.Document soup) {
    final found = <String>[];
    void add(String raw) {
      final message = _unescape(raw).trim();
      if (message.runes.length < 2 ||
          message.runes.length > 500 ||
          _confirm.hasMatch(message))
        return;
      if (!found.contains(message)) found.add(message);
    }

    for (final selector in [
      '[id\$="_lblMessage"]',
      '[id\$="_lblMsg"]',
      '[id\$="_lblError"]',
      '[id\$="_lblSuccess"]',
      '[id\$="_lblResult"]',
      '[id\$="_msg"]',
      '#msgDiv',
      '#msg_Success',
      '#MsgPopup',
      '#lblMsg',
      '.alert-success',
      '.alert-danger',
      '.alert-warning',
      '.toast-message',
      '.swal2-html-container',
    ]) {
      for (final node in soup.querySelectorAll(selector)) {
        if (node.attributes.containsKey('hidden') ||
            RegExp(
              r'display\s*:\s*none',
              caseSensitive: false,
            ).hasMatch(node.attributes['style'] ?? ''))
          continue;
        add(_text(node));
      }
    }
    final alert = RegExp(
      r'''(?<![\w.])(?:window\.)?alert\s*\(\s*(['"])((?:\\.|(?!\1).)*?)\1\s*\)''',
      caseSensitive: false,
      dotAll: true,
    );
    for (final script in soup.querySelectorAll('script')) {
      for (final match in alert.allMatches(script.text)) {
        add(_js(match.group(2)!));
      }
    }
    return found;
  }
}

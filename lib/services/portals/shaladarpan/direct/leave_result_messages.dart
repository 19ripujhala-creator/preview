/// Keeps native portal text separate from application verification results.
class LeaveResultMessages {
  static List<String> portalTexts(Map result) {
    final explicit = result['portal_message'];
    if (explicit is String && explicit.trim().isNotEmpty) return [explicit];
    final messages = result['portalMessages'];
    if (messages is List) {
      final texts = messages
          .whereType<String>()
          .where((s) => s.trim().isNotEmpty)
          .toList();
      if (texts.isNotEmpty) return texts;
    }
    final message = result['message'];
    return result['message_source'] == 'portal' &&
            message is String &&
            message.trim().isNotEmpty
        ? [message]
        : [];
  }

  static Map<String, dynamic> attach(
    Map<String, dynamic> result,
    Iterable<String> messages,
  ) {
    final texts = <String>[];
    for (final message in messages) {
      if (message.trim().isNotEmpty && !texts.contains(message))
        texts.add(message);
    }
    if (texts.isEmpty)
      return {...result, 'message_source': result['message_source'] ?? 'app'};
    final message = texts.join('\n');
    return {
      ...result,
      'message': message,
      'message_source': 'portal',
      'portal_message': message,
      'portalMessages': texts,
      if (result['success'] != true &&
          result['message'] != null &&
          result['message'] != message)
        'verification_message': result['message'],
    };
  }

  static String display(
    Map result, {
    String fallback = 'Leave action result is not confirmed.',
  }) {
    final portal = portalTexts(result);
    if (portal.isNotEmpty) {
      final native = portal.join('\n');
      final note = result['verification_message'];
      return note is String && note.trim().isNotEmpty
          ? '$native\n\nApp verification: $note'
          : native;
    }
    final raw = result['message'];
    final message = raw is String && raw.trim().isNotEmpty ? raw : fallback;
    return 'App: $message';
  }
}

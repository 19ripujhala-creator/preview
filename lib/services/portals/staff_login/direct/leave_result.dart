/// Preserve a completed/uncertain leave response when the saved account changes.
Map<String, dynamic> staffLeaveAccountChanged(Map<String, dynamic> result) {
  final upstream = result['upstream_response'];
  final original = upstream is Map ? upstream : result;
  final attempted =
      result['submission_attempted'] == true ||
      original['submission_attempted'] == true ||
      result['submitted'] == true ||
      result['success'] == true ||
      result['code'] == 'MUTATION_AMBIGUOUS' ||
      result['code'] == 'SAVE_UNCONFIRMED';
  final portal = result['message_source'] == 'portal'
      ? result
      : original['message_source'] == 'portal'
      ? original
      : null;
  final portalMessage = portal?['message'];
  final hasPortalMessage =
      portalMessage is String && portalMessage.trim().isNotEmpty;
  final message = attempted
      ? 'Staff login changed. Verify leave history for the submitting account before retrying.'
      : 'Staff login changed. No leave was submitted.';
  return {
    'success': false,
    'code': attempted ? 'SAVE_UNCONFIRMED' : 'ACCOUNT_CHANGED',
    'submission_attempted': attempted,
    'submitted': attempted
        ? result['submitted'] ?? original['submitted']
        : false,
    'message': hasPortalMessage ? portalMessage : message,
    if (hasPortalMessage) ...{
      'message_source': 'portal',
      'portal_message': portalMessage,
      'backend_message': message,
    },
    'upstream_response': result,
  };
}

/// Portal wording stays intact; local verification details are labelled separately.
String staffLeaveDisplayMessage(Map<String, dynamic> result) {
  final message = result['message']?.toString().trim() ?? '';
  final detail = result['backend_message']?.toString().trim() ?? '';
  if (result['message_source'] != 'portal') {
    return 'App: ${message.isEmpty ? 'Leave result could not be confirmed. Refresh history before retrying.' : message}';
  }
  return detail.isEmpty ? message : '$message\nApp: $detail';
}

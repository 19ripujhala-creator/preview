/// Display categories only. Portal option codes and submitted labels stay exact.
String staffAttendanceCategory(
  Object? label, {
  bool approvedLeave = false,
  bool selectionPending = false,
}) {
  final text = (label?.toString() ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
  bool matches(String pattern) =>
      RegExp(pattern, caseSensitive: false).hasMatch(text);
  if (selectionPending) return 'pending';
  // Check the negative label before the positive word it contains.
  if (matches(r'\babsent\b|\bnot[\s-]+present\b|अनुपस्थित')) return 'absent';
  if (approvedLeave ||
      matches(r'\bleave\b|अवकाश|^(?:cl|hcl|ml|pl|hpl|el)(?:\b|$)'))
    return 'leave';
  if (text.isEmpty ||
      matches(
        r'^(?:[-–—]\s*)*(?:please\s+)?(?:select|choose)(?:\s+(?:status|attendance|an?\s+option))?(?:\s*[-–—])*$|^चयन(?:\s+करें)?$',
      ))
    return 'pending';
  if (matches(r'\bpresent\b|(?:^|\s)उपस्थित(?:\s|$)')) return 'present';
  return 'other';
}

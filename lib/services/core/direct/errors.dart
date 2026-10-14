/// Error codes, response classification and HTTP mapping from core/errors.py.
import 'dart:async';
import 'dart:io';

import 'async_primitives.dart';

enum ErrorKind {
  sessionExpired('SESSION_EXPIRED', 401),
  notAuthenticated('NOT_AUTHENTICATED', 401),
  sessionUnverified('SESSION_UNVERIFIED', 503),
  authInProgress('AUTH_IN_PROGRESS', 503),
  recoveryInProgress('RECOVERY_IN_PROGRESS', 503),
  pageBusy('PAGE_BUSY', 503),
  pageNotReady('PAGE_NOT_READY', 503),
  navigationRace('NAVIGATION_RACE', 503),
  networkError('NETWORK_ERROR', 502),
  browserError('BROWSER_ERROR', 503),
  serverError('SERVER_ERROR', 500),
  mutationAmbiguous('MUTATION_AMBIGUOUS', 409),
  validationError('VALIDATION_ERROR', 400),
  portalSlow('PORTAL_SLOW', 504);

  const ErrorKind(this.code, this.httpStatus);
  final String code;
  final int httpStatus;
  static ErrorKind? fromCode(String code) {
    for (final kind in values) {
      if (kind.code == code) return kind;
    }
    return null;
  }
}

class CoordinatorError implements Exception {
  CoordinatorError(this.kind, this.message, [Map<String, dynamic>? extra])
    : extra = extra ?? {};
  final ErrorKind kind;
  final String message;
  final Map<String, dynamic> extra;
  int get httpStatus => kind.httpStatus;
  Map<String, dynamic> asDetail() => {
    ...extra,
    'success': false,
    'code': kind.code,
    'message': message,
  };
  @override
  String toString() => message;
}

const businessStatus = <String, int>{
  'ACCESS_DENIED': 403,
  'RATE_LIMITED': 429,
  'PORTAL_RESPONSE_ERROR': 502,
  'BAD_DATE': 400,
  'BAD_CLASS': 400,
  'AMBIGUOUS_SECTION': 400,
  'RADIO_FAILED': 400,
  'NO_SAVE_BUTTON': 400,
  'MATCH_MISMATCH': 400,
  'NO_CLASSES': 400,
  'NO_STUDENT_TABLE': 502,
  'NO_ENTRY_LINK': 502,
  'SAVE_NOT_APPLIED': 409,
  'SAVE_UNCONFIRMED': 409,
  'ALREADY_MARKED': 409,
  'PARTIAL_REPORT': 502,
  'PORTAL_ERROR': 502,
  'INVALID_RESULT': 502,
  'NO_CREDENTIALS': 400,
  'INVALID_CREDENTIALS': 401,
  'BUSY': 503,
};
int businessFailureStatus(Map<String, dynamic> result) {
  final code = result['code']?.toString() ?? '';
  return ErrorKind.fromCode(code)?.httpStatus ?? businessStatus[code] ?? 500;
}

const _closedMarkers = [
  'has been closed',
  'target closed',
  'target page, context or browser',
  'browser has been closed',
  'connection closed',
];
const _navMarkers = [
  'execution context was destroyed',
  'frame was detached',
  'because of a navigation',
];

ErrorKind? classifyResult(Map<String, dynamic> result) {
  if (result['success'] == true) return null;
  if (result.containsKey('success') && result['success'] != false) {
    return ErrorKind.serverError;
  }
  final code = result['code']?.toString() ?? '';
  final message = (result['message']?.toString() ?? '').toLowerCase();
  final exact = ErrorKind.fromCode(code);
  if (exact != null) return exact;
  if (code == 'PORTAL_ERROR') return ErrorKind.pageNotReady;
  if (const {'PORTAL_SLOW', 'SHOW_TIMEOUT', 'ENTRY_TIMEOUT'}.contains(code)) {
    return ErrorKind.portalSlow;
  }
  if (_closedMarkers.any(message.contains)) return ErrorKind.browserError;
  if (code.isEmpty || code == 'UNEXPECTED') {
    if (_navMarkers.any(message.contains)) return ErrorKind.navigationRace;
    return ErrorKind.serverError;
  }
  return ErrorKind.validationError;
}

ErrorKind classifyException(Object error) {
  if (error is CoordinatorError) return error.kind;
  if (error is TimeoutException || error is OperationCancelled) {
    return ErrorKind.portalSlow;
  }
  if (error is SocketException ||
      error is HandshakeException ||
      error is HttpException)
    return ErrorKind.networkError;
  final text = error.toString().toLowerCase();
  if (_closedMarkers.any(text.contains)) return ErrorKind.browserError;
  if (_navMarkers.any(text.contains)) return ErrorKind.navigationRace;
  return ErrorKind.serverError;
}

ErrorKind? classifyWorkerResult(Map<String, dynamic> result) {
  if (result['success'] != true &&
      (result['code'] == 'SAVE_UNCONFIRMED' ||
          result['submission_attempted'] == true))
    return ErrorKind.mutationAmbiguous;
  return classifyResult(result);
}

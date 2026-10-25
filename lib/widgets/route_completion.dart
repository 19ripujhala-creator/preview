import 'package:flutter/widgets.dart';

/// Keep return-side rebuilds and reads outside the page's exit animation.
/// Navigator.push completes on pop; TransitionRoute.completed waits until
/// the transition has finished and its overlay entries have been removed.
Future<T?> pushPageAndWaitForExit<T>(
  BuildContext context,
  TransitionRoute<T> route,
) async {
  final result = await Navigator.of(context).push<T>(route);
  await route.completed;
  return result;
}

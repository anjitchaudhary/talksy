import 'package:flutter/cupertino.dart';

final class NavigationHelper {
  NavigationHelper._();

  static Future<T?> navigateTo<T>(BuildContext context, Widget page) {
    if (!context.mounted) return Future<T?>.value(null);
    return Navigator.of(context)
        .push<T>(CupertinoPageRoute<T>(builder: (_) => page));
  }

  static Future<T?> replaceWith<T, TO>(
    BuildContext context,
    Widget page, {
    TO? result,
  }) {
    if (!context.mounted) return Future<T?>.value(null);
    return Navigator.of(context).pushReplacement<T, TO>(
      CupertinoPageRoute<T>(builder: (_) => page),
      result: result,
    );
  }
}

import 'package:flutter/cupertino.dart';

class NavigationHelper {
  static Future<void> navigateTo(BuildContext context, Widget page) {
    return Navigator.of(context).push(
      CupertinoPageRoute(builder: (_) => page),
    );
  }

  static Future<void> replaceWith(BuildContext context, Widget page) {
    return Navigator.of(context).pushReplacement(
      CupertinoPageRoute(builder: (_) => page),
    );
  }
}

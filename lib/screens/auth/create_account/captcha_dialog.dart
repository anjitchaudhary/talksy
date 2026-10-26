import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class CaptchaDialog extends StatefulWidget {
  const CaptchaDialog({super.key, required this.email});

  final String email;

  static const String siteKey = String.fromEnvironment('TURNSTILE_SITE_KEY');
  static const String origin = String.fromEnvironment('TURNSTILE_ORIGIN');

  static Future<String?> show(BuildContext context, {required String email}) {
    return showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (_) => CaptchaDialog(email: email),
    );
  }

  @override
  State<CaptchaDialog> createState() => _CaptchaDialogState();
}

class _CaptchaDialogState extends State<CaptchaDialog> {
  static const String action = 'signup';

  String get _page {
    final siteKey = _jsLiteral(CaptchaDialog.siteKey);
    final cData = _jsLiteral(
      base64Url.encode(utf8.encode(widget.email)).replaceAll('=', ''),
    );
    return '''
<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
<style>
html, body { margin: 0; width: 100%; height: 100%; overflow: hidden; background: transparent; }
body { display: flex; align-items: center; }
#box { width: 100%; }
</style>
<script>
function initCaptcha() {
  try {
    turnstile.render('#box', {
      sitekey: $siteKey,
      action: '$action',
      cData: $cData,
      size: 'flexible',
      theme: 'auto',
      callback: function (token) { Captcha.postMessage('token:' + token); },
      'error-callback': function () { Captcha.postMessage('error'); }
    });
  } catch (e) {
    Captcha.postMessage('error');
  }
}
</script>
<script src="https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit&onload=initCaptcha"
  async defer onerror="Captcha.postMessage('error')"></script>
</head>
<body><div id="box"></div></body>
</html>
''';
  }

  static String _jsLiteral(String value) {
    return jsonEncode(value).replaceAll('<', r'\u003c');
  }

  late final WebViewController _controller;
  bool _loading = true;
  bool _failed = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..addJavaScriptChannel('Captcha', onMessageReceived: _onMessage)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame == false || !mounted) return;
            setState(() {
              _failed = true;
              _loading = false;
            });
          },
        ),
      )
      ..loadHtmlString(_page, baseUrl: CaptchaDialog.origin);
  }

  void _onMessage(JavaScriptMessage message) {
    if (_done || !mounted) return;
    final data = message.message;
    if (data.startsWith('token:')) {
      _done = true;
      final token = data.substring(6);
      Future.delayed(const Duration(milliseconds: 700), () {
        if (mounted) Navigator.of(context).pop(token);
      });
    } else if (data == 'error') {
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  void _retry() {
    setState(() {
      _failed = false;
      _loading = true;
    });
    _controller.loadHtmlString(_page, baseUrl: CaptchaDialog.origin);
  }

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6);
    return Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SizedBox(
          width: double.infinity,
          height: _failed ? null : 65 * textScale,
          child: _failed ? _errorCard(context) : _widget(),
        ),
      ),
    );
  }

  Widget _widget() {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: WebViewWidget(controller: _controller),
        ),
        if (_loading)
          const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2.5,
              ),
            ),
          ),
      ],
    );
  }

  Widget _errorCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Could not load the verification. Check your internet and try again.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: _retry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

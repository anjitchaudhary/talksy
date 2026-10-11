import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HomeScreen extends StatefulWidget {
  final bool showSuccessPopup;

  const HomeScreen({super.key, this.showSuccessPopup = false});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const Color _silverColor = Color(0xFFC0C0C0);

  @override
  void initState() {
    super.initState();
    if (widget.showSuccessPopup) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showSuccessPopup();
      });
    }
  }

  void _showSuccessPopup() {
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Account Created!'),
        content: const Text(
          'You have successfully created a Talksy account. Thanks for choosing us!',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('I understand'),
          ),
        ],
      ),
    );
  }

  Widget _buildIconButton(IconData icon, VoidCallback onTap, bool isDark) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size(28, 28),
      onPressed: onTap,
      child: Icon(
        icon,
        size: 24,
        color: isDark ? Colors.white : Colors.black87,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user = Supabase.instance.client.auth.currentUser;
    final profileUrl = user?.userMetadata?['profile_image'] as String? ??
                       user?.userMetadata?['avatar_url'] as String?;

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(48),
        child: SafeArea(
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: _silverColor, width: 0.5),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Talksy',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black,
                    letterSpacing: -0.5,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildIconButton(Icons.notifications_none, () {}, isDark),
                    const SizedBox(width: 8),
                    _buildIconButton(Icons.search, () {}, isDark),
                    const SizedBox(width: 10),
                    _UserAvatar(url: profileUrl, isDark: isDark),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      body: const SizedBox.expand(),
    );
  }
}

class _UserAvatar extends StatefulWidget {
  final String? url;
  final bool isDark;

  const _UserAvatar({this.url, required this.isDark});

  @override
  State<_UserAvatar> createState() => _UserAvatarState();
}

class _UserAvatarState extends State<_UserAvatar> {
  static const Color _silverColor = Color(0xFFC0C0C0);
  static final Map<String, File> _memoryCache = {};

  File? _cachedFile;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _initAvatar();
  }

  @override
  void didUpdateWidget(covariant _UserAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _initAvatar();
    }
  }

  void _initAvatar() {
    final url = widget.url?.trim();
    if (url == null || url.isEmpty) {
      _cachedFile = null;
      _isLoading = false;
      return;
    }

    if (_memoryCache.containsKey(url)) {
      _cachedFile = _memoryCache[url];
      _isLoading = false;
      return;
    }

    _cachedFile = null;
    _isLoading = true;
    _fetchAndCache(url);
  }

  Future<void> _fetchAndCache(String url) async {
    try {
      final dir = await getTemporaryDirectory();
      final key = url.hashCode.abs().toString();
      final file = File('${dir.path}/avatar_$key.png');

      if (await file.exists()) {
        _memoryCache[url] = file;
        if (mounted && widget.url?.trim() == url) {
          setState(() {
            _cachedFile = file;
            _isLoading = false;
          });
        }
        return;
      }

      final request = await HttpClient().getUrl(Uri.parse(url));
      final response = await request.close();

      if (response.statusCode == 200) {
        final bytes = await response.fold<List<int>>(
          <int>[],
          (buffer, data) => buffer..addAll(data),
        );
        await file.writeAsBytes(bytes);
        _memoryCache[url] = file;
        if (mounted && widget.url?.trim() == url) {
          setState(() {
            _cachedFile = file;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bgBase = widget.isDark
        ? const Color(0xFF222222)
        : const Color(0xFFECECEC);

    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: bgBase,
        border: Border.all(
          color: widget.isDark
              ? _silverColor.withValues(alpha: 0.5)
              : _silverColor,
          width: 1,
        ),
      ),
      child: ClipOval(child: _buildAvatarContent()),
    );
  }

  Widget _buildAvatarContent() {
    if (_cachedFile != null) {
      return Image.file(_cachedFile!, width: 32, height: 32, fit: BoxFit.cover);
    }

    if (_isLoading) {
      return const Center(child: CupertinoActivityIndicator(radius: 7));
    }

    return Icon(
      Icons.person,
      size: 18,
      color: widget.isDark ? Colors.white70 : Colors.black54,
    );
  }
}

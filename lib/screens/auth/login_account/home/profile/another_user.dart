import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../chat.dart';

class AnotherUserProfileScreen extends StatefulWidget {
  final Map<String, dynamic> user;

  const AnotherUserProfileScreen({super.key, required this.user});

  @override
  State<AnotherUserProfileScreen> createState() =>
      _AnotherUserProfileScreenState();
}

class _AnotherUserProfileScreenState extends State<AnotherUserProfileScreen> {
  bool _isConnected = false;

  @override
  void initState() {
    super.initState();
    _checkConnectionStatus();
  }

  Future<void> _checkConnectionStatus() async {
    try {
      final currentUserId = Supabase.instance.client.auth.currentUser?.id;
      final targetUserId = widget.user['id'];

      if (currentUserId == null || targetUserId == null) return;

      final response = await Supabase.instance.client
          .from('connections')
          .select()
          .eq('user_id', currentUserId)
          .eq('connected_user_id', targetUserId)
          .maybeSingle();

      if (mounted) {
        setState(() {
          _isConnected = response != null;
        });
      }
    } catch (_) {}
  }

  Future<void> _toggleConnect() async {
    final previousState = _isConnected;

    setState(() {
      _isConnected = !_isConnected;
    });

    try {
      final currentUserId = Supabase.instance.client.auth.currentUser?.id;
      final targetUserId = widget.user['id'];

      if (currentUserId == null || targetUserId == null) {
        setState(() => _isConnected = previousState);
        return;
      }

      if (previousState) {
        await Supabase.instance.client
            .from('connections')
            .delete()
            .eq('user_id', currentUserId)
            .eq('connected_user_id', targetUserId);
      } else {
        await Supabase.instance.client.from('connections').insert({
          'user_id': currentUserId,
          'connected_user_id': targetUserId,
          'created_at': DateTime.now().toIso8601String(),
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isConnected = previousState;
        });
      }
    }
  }

  String _resolveUrl(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.startsWith('/') || trimmed.contains('data/user')) return '';
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    try {
      return Supabase.instance.client.storage
          .from('avatars')
          .getPublicUrl(trimmed);
    } catch (_) {
      return trimmed;
    }
  }

  void _handleMessage() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => ChatScreen(user: widget.user)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final firstName = widget.user['first_name'] ?? '';
    final lastName = widget.user['last_name'] ?? '';
    final displayName = widget.user['display_name'] ?? '';
    final email = widget.user['email'] ?? '';

    String fullName = '$firstName $lastName'.trim();
    if (fullName.isEmpty) {
      fullName = displayName.isNotEmpty
          ? displayName
          : (email.isNotEmpty ? email.split('@').first : 'User');
    }

    final rawAvatarUrl = widget.user['avatar_url'] as String?;
    final profileUrl = rawAvatarUrl != null ? _resolveUrl(rawAvatarUrl) : '';

    final bgColor = isDark ? const Color(0xFF121212) : Colors.white;
    final gridLineColor = isDark
        ? const Color(0xFF1E1E1E)
        : const Color(0xFFF2F2F2);
    final textMutedColor = isDark
        ? const Color(0xFF8E8E93)
        : const Color(0xFF8E8E93);

    final List<String> userReels = [];

    return Scaffold(
      backgroundColor: bgColor,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(40),
        child: AppBar(
          backgroundColor: bgColor,
          elevation: 0,
          automaticallyImplyLeading: false,
          titleSpacing: 0,
          title: SafeArea(
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(32, 32),
                    onPressed: () => Navigator.pop(context),
                    child: Icon(
                      Icons.arrow_back_ios_new,
                      size: 20,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      "$firstName's profile",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                  const SizedBox(width: 32),
                ],
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _LargeUserAvatar(url: profileUrl, isDark: isDark),
                  const SizedBox(height: 14),
                  Text(
                    fullName,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: CupertinoButton(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          color: CupertinoColors.activeBlue,
                          pressedOpacity: 1.0,
                          borderRadius: BorderRadius.circular(8),
                          onPressed: _toggleConnect,
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.person_add_alt_1_outlined,
                                size: 18,
                                color: CupertinoColors.white,
                              ),
                              SizedBox(width: 6),
                              Text(
                                'Connect',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: CupertinoColors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: CupertinoButton(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          color: isDark
                              ? const Color(0xFF2C2C2C)
                              : const Color(0xFFE5E5E5),
                          pressedOpacity: 1.0,
                          borderRadius: BorderRadius.circular(8),
                          onPressed: _handleMessage,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.chat_bubble_outline,
                                size: 18,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Message',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Divider(height: 0.5, thickness: 0.5, color: gridLineColor),
            Expanded(
              child: userReels.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isDark ? Colors.white24 : Colors.black26,
                                width: 1.5,
                              ),
                            ),
                            child: Icon(
                              Icons.movie_creation_outlined,
                              size: 30,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No reels',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'When you share reels, they will appear here.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: textMutedColor,
                            ),
                          ),
                        ],
                      ),
                    )
                  : GridView.builder(
                      padding: EdgeInsets.zero,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 0.5,
                            mainAxisSpacing: 0.5,
                            childAspectRatio: 9 / 16,
                          ),
                      itemCount: userReels.length,
                      itemBuilder: (context, index) {
                        return Container(
                          color: isDark
                              ? const Color(0xFF1E1E1E)
                              : const Color(0xFFF0F0F0),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LargeUserAvatar extends StatefulWidget {
  final String? url;
  final bool isDark;

  const _LargeUserAvatar({this.url, required this.isDark});

  @override
  State<_LargeUserAvatar> createState() => _LargeUserAvatarState();
}

class _LargeUserAvatarState extends State<_LargeUserAvatar> {
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
  void didUpdateWidget(covariant _LargeUserAvatar oldWidget) {
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
      final file = File('${dir.path}/avatar_large_$key.png');

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
      width: 76,
      height: 76,
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
      return Image.file(_cachedFile!, width: 76, height: 76, fit: BoxFit.cover);
    }

    if (_isLoading) {
      return const Center(child: CupertinoActivityIndicator(radius: 10));
    }

    return Icon(
      Icons.person,
      size: 40,
      color: widget.isDark ? Colors.white70 : Colors.black54,
    );
  }
}

import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'setting.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user = Supabase.instance.client.auth.currentUser;
    final profileUrl =
        user?.userMetadata?['profile_image'] as String? ??
        user?.userMetadata?['avatar_url'] as String?;

    final fullName =
        user?.userMetadata?['full_name'] as String? ??
        user?.userMetadata?['name'] as String? ??
        '';
    final firstName =
        user?.userMetadata?['first_name'] as String? ??
        (fullName.isNotEmpty ? fullName.split(' ').first : 'User');
    final lastName =
        user?.userMetadata?['last_name'] as String? ??
        (fullName.split(' ').length > 1
            ? fullName.split(' ').skip(1).join(' ')
            : '');

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
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(32, 32),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const SettingScreen(),
                        ),
                      );
                    },
                    child: Icon(
                      Icons.settings_outlined,
                      size: 22,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
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
                    '$firstName $lastName'.trim(),
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
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

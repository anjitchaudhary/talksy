import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'profile/profile.dart';

class HomeScreen extends StatefulWidget {
  final bool showSuccessPopup;

  const HomeScreen({super.key, this.showSuccessPopup = false});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

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
    final profileUrl =
        user?.userMetadata?['profile_image'] as String? ??
        user?.userMetadata?['avatar_url'] as String?;

    final bgColor = isDark ? const Color(0xFF121212) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF2C2C2C)
        : const Color(0xFFE5E5E5);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(48.5),
        child: AppBar(
          backgroundColor: bgColor,
          elevation: 0,
          automaticallyImplyLeading: false,
          titleSpacing: 0,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(0.5),
            child: Container(height: 0.5, color: borderColor),
          ),
          title: SafeArea(
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              color: bgColor,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Talksy',
                    style: TextStyle(
                      fontSize: 28,
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
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(32, 32),
                        onPressed: () {
                          Navigator.push(
                            context,
                            CupertinoPageRoute(
                              builder: (context) => const ProfileScreen(),
                            ),
                          );
                        },
                        child: _UserAvatar(url: profileUrl, isDark: isDark),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: const SizedBox.expand(),
      bottomNavigationBar: BottomNavTitle(
        isDark: isDark,
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
      ),
    );
  }
}

class BottomNavTitle extends StatelessWidget {
  final bool isDark;
  final int currentIndex;
  final ValueChanged<int> onTap;

  const BottomNavTitle({
    super.key,
    required this.isDark,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = isDark ? const Color(0xFF121212) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF2C2C2C)
        : const Color(0xFFE5E5E5);

    return Container(
      color: bgColor,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(height: 0.5, color: borderColor),
          SizedBox(
            height: 48,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(0, Icons.chat_bubble_outline, 'Chats'),
                _buildNavItem(1, Icons.group_outlined, 'Groups'),
                _buildNavItem(2, Icons.movie_outlined, 'Reels'),
                _buildNavItem(3, Icons.work_outline, 'Jobs'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = currentIndex == index;
    final activeColor = isDark ? Colors.white : Colors.black;
    final inactiveColor = isDark ? Colors.grey : Colors.black54;

    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: () => onTap(index),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 22, color: isSelected ? activeColor : inactiveColor),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              color: isSelected ? activeColor : inactiveColor,
            ),
          ),
        ],
      ),
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

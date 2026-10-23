import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:talksy/api_gateway.dart';
import 'package:talksy/local_db.dart';

import 'profile/another_user.dart';

class SearchUserScreen extends StatefulWidget {
  const SearchUserScreen({super.key});

  @override
  State<SearchUserScreen> createState() => _SearchUserScreenState();
}

class _SearchUserScreenState extends State<SearchUserScreen> {
  final ApiGateway _gateway = ApiGateway.instance;
  final LocalDb _db = LocalDb.instance;
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  List<Map<String, dynamic>> _searchHistory = [];
  bool _isSearching = false;
  Timer? _debounce;

  String get _owner => _gateway.currentUser?.id ?? 'guest';

  @override
  void initState() {
    super.initState();
    _loadSearchHistory();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }
    setState(() => _isSearching = true);
    _debounce = Timer(
      const Duration(milliseconds: 300),
      () => _performSearch(query),
    );
  }

  Future<void> _loadSearchHistory() async {
    try {
      final rows = await _db.searchHistory(_owner);
      if (mounted) setState(() => _searchHistory = rows);
    } catch (_) {}
  }

  Future<void> _addToHistory(Map<String, dynamic> user) async {
    try {
      await _db.addSearch(_owner, user);
      await _loadSearchHistory();
    } catch (_) {}
  }

  Future<bool> _confirm() async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Are you sure to apply this action?'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _removeHistoryItem(String id) async {
    if (!await _confirm()) return;
    try {
      await _db.removeSearch(_owner, id);
      await _loadSearchHistory();
    } catch (_) {}
  }

  Future<void> _clearAllHistory() async {
    if (!await _confirm()) return;
    try {
      await _db.clearSearches(_owner);
      await _loadSearchHistory();
    } catch (_) {}
  }

  Future<void> _performSearch(String query) async {
    List<Map<String, dynamic>> rows = [];
    try {
      rows = await _gateway.searchProfiles(query);
    } catch (_) {}

    if (!mounted || query != _searchController.text.trim()) return;
    setState(() {
      _searchResults = rows;
      _isSearching = false;
    });
  }

  void _navigateToProfile(Map<String, dynamic> user) {
    _addToHistory(user);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AnotherUserProfileScreen(user: user),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF121212) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF2C2C2C)
        : const Color(0xFFE5E5E5);
    final textColor = isDark ? Colors.white : Colors.black;
    final subtitleColor = isDark ? Colors.grey : Colors.black54;

    final displayList = _searchController.text.trim().isEmpty
        ? _searchHistory
        : _searchResults;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(48.5),
        child: AppBar(
          backgroundColor: bgColor,
          elevation: 0,
          automaticallyImplyLeading: false,
          centerTitle: true,
          titleSpacing: 0,
          leading: Center(
            child: CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(32, 32),
              onPressed: () => Navigator.pop(context),
              child: Icon(
                Icons.arrow_back_ios_new,
                size: 20,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(0.5),
            child: Container(height: 0.5, color: borderColor),
          ),
          title: Text(
            'Search users to connect',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.normal,
              color: textColor,
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            child: CupertinoSearchTextField(
              controller: _searchController,
              placeholder: 'Search by name...',
              backgroundColor: isDark
                  ? const Color(0xFF222222)
                  : const Color(0xFFF0F0F0),
              prefixIcon: Icon(Icons.search, color: subtitleColor, size: 20),
              suffixIcon: Icon(Icons.clear, color: subtitleColor, size: 20),
              style: TextStyle(color: textColor),
              placeholderStyle: TextStyle(color: subtitleColor),
            ),
          ),
          if (_searchController.text.trim().isEmpty &&
              _searchHistory.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Recent Searches',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: subtitleColor,
                    ),
                  ),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(30, 30),
                    onPressed: _clearAllHistory,
                    child: Text(
                      'Clear All',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: CupertinoColors.activeBlue,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (_isSearching)
            const Expanded(child: Center(child: CupertinoActivityIndicator()))
          else if (displayList.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isDark
                            ? const Color(0xFF1E1E1E)
                            : const Color(0xFFF4F4F4),
                        border: Border.all(color: borderColor, width: 1),
                      ),
                      child: Icon(Icons.search, size: 26, color: subtitleColor),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'No users searched',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: subtitleColor,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                itemCount: displayList.length,
                separatorBuilder: (context, index) =>
                    Container(height: 0.5, color: borderColor),
                itemBuilder: (context, index) {
                  final user = displayList[index];
                  final firstName = user['first_name'] ?? '';
                  final lastName = user['last_name'] ?? '';
                  final displayName = user['display_name'] ?? '';
                  final email = user['email'] ?? '';

                  String fullName = '$firstName $lastName'.trim();
                  if (fullName.isEmpty) {
                    fullName = displayName.isNotEmpty
                        ? displayName
                        : (email.isNotEmpty
                              ? email.split('@').first
                              : 'Unknown User');
                  }

                  final avatarUrl = user['avatar_url'] as String?;

                  return CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () => _navigateToProfile(user),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      color: Colors.transparent,
                      child: Row(
                        children: [
                          _UserAvatar(url: avatarUrl, isDark: isDark),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              fullName,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: textColor,
                              ),
                            ),
                          ),
                          if (_searchController.text.trim().isEmpty)
                            CupertinoButton(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(24, 24),
                              onPressed: () => _removeHistoryItem(user['id']),
                              child: Icon(
                                Icons.close,
                                size: 18,
                                color: subtitleColor,
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _UserAvatar extends StatelessWidget {
  final String? url;
  final bool isDark;

  const _UserAvatar({this.url, required this.isDark});

  @override
  Widget build(BuildContext context) {
    const Color silverColor = Color(0xFFC0C0C0);
    final bgBase = isDark ? const Color(0xFF222222) : const Color(0xFFECECEC);
    final resolvedUrl = ApiGateway.instance.avatarUrl(url);

    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: bgBase,
        border: Border.all(
          color: isDark ? silverColor.withValues(alpha: 0.5) : silverColor,
          width: 1,
        ),
      ),
      child: ClipOval(
        child: resolvedUrl.isEmpty
            ? Icon(
                Icons.person,
                size: 18,
                color: isDark ? Colors.white70 : Colors.black54,
              )
            : Image.network(
                resolvedUrl,
                width: 32,
                height: 32,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Icon(
                  Icons.person,
                  size: 18,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return const Center(
                    child: CupertinoActivityIndicator(radius: 7),
                  );
                },
              ),
      ),
    );
  }
}

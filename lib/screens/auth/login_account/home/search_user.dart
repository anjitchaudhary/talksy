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
  static const int _maxQueryLength = 50;

  final ApiGateway _gateway = ApiGateway.instance;
  final LocalDb _db = LocalDb.instance;
  final TextEditingController _controller = TextEditingController();

  List<Map<String, dynamic>> _results = [];
  List<Map<String, dynamic>> _history = [];
  bool _isSearching = false;
  bool _hasError = false;
  bool _rateLimited = false;
  String _submitted = '';

  String get _owner => _gateway.currentUser?.id ?? 'guest';

  String get _query {
    final text = _controller.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    return String.fromCharCodes(text.runes.take(_maxQueryLength)).trim();
  }

  bool get _isServerView => _query.isNotEmpty && _query == _submitted;

  List<Map<String, dynamic>> get _localMatches {
    final needle = _query.toLowerCase();
    return _history
        .where((user) => _nameOf(user).toLowerCase().contains(needle))
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onQueryChanged);
    _loadHistory();
  }

  @override
  void dispose() {
    _controller.removeListener(_onQueryChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged() => setState(() {});

  Future<void> _submit() async {
    final query = _query;
    if (query.isEmpty) return;
    FocusScope.of(context).unfocus();
    if (query == _submitted && (_isSearching || !_hasError)) return;

    setState(() {
      _submitted = query;
      _results = [];
      _isSearching = true;
      _hasError = false;
      _rateLimited = false;
    });

    var rows = <Map<String, dynamic>>[];
    var failed = false;
    var limited = false;
    try {
      rows = await _gateway.searchProfiles(query);
    } on GatewayException catch (e) {
      failed = true;
      limited = e.code == 'rate_limited';
    } catch (_) {
      failed = true;
    }
    if (!mounted || query != _submitted) return;
    setState(() {
      _results = rows;
      _hasError = failed;
      _rateLimited = limited;
      _isSearching = false;
    });
  }

  Future<void> _loadHistory() async {
    try {
      final rows = await _db.searchHistory(_owner);
      if (mounted) setState(() => _history = rows);
    } catch (_) {}
  }

  Future<void> _saveToHistory(Map<String, dynamic> user) async {
    try {
      await _db.addSearch(_owner, user);
      await _loadHistory();
    } catch (_) {}
  }

  Future<void> _removeFromHistory(String id) async {
    if (!await _confirm()) return;
    try {
      await _db.removeSearch(_owner, id);
      await _loadHistory();
    } catch (_) {}
  }

  Future<void> _clearHistory() async {
    if (!await _confirm()) return;
    try {
      await _db.clearSearches(_owner);
      await _loadHistory();
    } catch (_) {}
  }

  Future<bool> _confirm() async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text(
          'Are you sure to apply this action?',
          style: TextStyle(fontWeight: FontWeight.normal, fontSize: 14.0),
        ),
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

  void _openProfile(Map<String, dynamic> user) {
    FocusScope.of(context).unfocus();
    _saveToHistory(user);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AnotherUserProfileScreen(user: user),
      ),
    );
  }

  String _nameOf(Map<String, dynamic> user) {
    final first = (user['first_name'] ?? '').toString().trim();
    final last = (user['last_name'] ?? '').toString().trim();
    final display = (user['display_name'] ?? '').toString().trim();
    final email = (user['email'] ?? '').toString().trim();

    final full = '$first $last'.trim();
    if (full.isNotEmpty) return full;
    if (display.isNotEmpty) return display;
    if (email.isNotEmpty) return email.split('@').first;
    return 'Unknown User';
  }

  String get _emptyMessage {
    if (_query.isEmpty) return 'No recent searches';
    if (!_isServerView) return 'Press enter to search';
    if (_rateLimited) return 'Too many searches. Try again in a minute';
    return _hasError ? 'Could not search right now' : 'No users found';
  }

  @override
  Widget build(BuildContext context) {
    final palette = _Palette.of(
      Theme.of(context).brightness == Brightness.dark,
    );
    final showingHistory = _query.isEmpty;
    final items = showingHistory
        ? _history
        : _isServerView
        ? _results
        : _localMatches;

    return Scaffold(
      backgroundColor: palette.background,
      appBar: _buildAppBar(palette),
      body: Column(
        children: [
          _buildSearchField(palette),
          if (showingHistory && _history.isNotEmpty)
            _buildHistoryHeader(palette),
          Expanded(child: _buildBody(palette, items, showingHistory)),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(_Palette palette) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(48.5),
      child: AppBar(
        backgroundColor: palette.background,
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
              color: palette.icon,
            ),
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(height: 0.5, color: palette.border),
        ),
        title: Text(
          'Search users to connect',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.normal,
            color: palette.text,
          ),
        ),
      ),
    );
  }

  Widget _buildSearchField(_Palette palette) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: CupertinoSearchTextField(
        controller: _controller,
        placeholder: 'Search by name...',
        autocorrect: false,
        onSubmitted: (_) => _submit(),
        backgroundColor: palette.field,
        prefixIcon: Icon(Icons.search, color: palette.subtitle, size: 20),
        suffixIcon: Icon(Icons.clear, color: palette.subtitle, size: 20),
        style: TextStyle(color: palette.text),
        placeholderStyle: TextStyle(color: palette.subtitle),
      ),
    );
  }

  Widget _buildHistoryHeader(_Palette palette) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Recent Searches',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: palette.subtitle,
            ),
          ),
          CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: const Size(30, 30),
            onPressed: _clearHistory,
            child: const Text(
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
    );
  }

  Widget _buildBody(
    _Palette palette,
    List<Map<String, dynamic>> items,
    bool showingHistory,
  ) {
    if (_isSearching && _isServerView) {
      return const Center(child: CupertinoActivityIndicator());
    }
    if (items.isEmpty) return _buildEmpty(palette);

    return ListView.separated(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: items.length,
      separatorBuilder: (context, index) =>
          Container(height: 0.5, color: palette.border),
      itemBuilder: (context, index) {
        final user = items[index];
        return _UserTile(
          name: _nameOf(user),
          avatarUrl: user['avatar_url'] as String?,
          palette: palette,
          onTap: () => _openProfile(user),
          onRemove: showingHistory
              ? () => _removeFromHistory(user['id'].toString())
              : null,
        );
      },
    );
  }

  Widget _buildEmpty(_Palette palette) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: palette.emptyBadge,
              border: Border.all(color: palette.border, width: 1),
            ),
            child: Icon(Icons.search, size: 26, color: palette.subtitle),
          ),
          const SizedBox(height: 10),
          Text(
            _emptyMessage,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: palette.subtitle,
            ),
          ),
        ],
      ),
    );
  }
}

class _Palette {
  final Color background;
  final Color border;
  final Color text;
  final Color subtitle;
  final Color icon;
  final Color field;
  final Color emptyBadge;
  final Color avatarBackground;
  final Color avatarBorder;
  final Color avatarIcon;

  const _Palette({
    required this.background,
    required this.border,
    required this.text,
    required this.subtitle,
    required this.icon,
    required this.field,
    required this.emptyBadge,
    required this.avatarBackground,
    required this.avatarBorder,
    required this.avatarIcon,
  });

  factory _Palette.of(bool isDark) {
    const silver = Color(0xFFC0C0C0);
    return isDark
        ? _Palette(
            background: const Color(0xFF121212),
            border: const Color(0xFF2C2C2C),
            text: Colors.white,
            subtitle: Colors.grey,
            icon: Colors.white,
            field: const Color(0xFF222222),
            emptyBadge: const Color(0xFF1E1E1E),
            avatarBackground: const Color(0xFF222222),
            avatarBorder: silver.withValues(alpha: 0.5),
            avatarIcon: Colors.white70,
          )
        : const _Palette(
            background: Colors.white,
            border: Color(0xFFE5E5E5),
            text: Colors.black,
            subtitle: Colors.black54,
            icon: Colors.black87,
            field: Color(0xFFF0F0F0),
            emptyBadge: Color(0xFFF4F4F4),
            avatarBackground: Color(0xFFECECEC),
            avatarBorder: silver,
            avatarIcon: Colors.black54,
          );
  }
}

class _UserTile extends StatelessWidget {
  final String name;
  final String? avatarUrl;
  final _Palette palette;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  const _UserTile({
    required this.name,
    required this.avatarUrl,
    required this.palette,
    required this.onTap,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: Colors.transparent,
        child: Row(
          children: [
            _UserAvatar(url: avatarUrl, palette: palette),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: palette.text,
                ),
              ),
            ),
            if (onRemove != null)
              CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: const Size(24, 24),
                onPressed: onRemove,
                child: Icon(Icons.close, size: 18, color: palette.subtitle),
              ),
          ],
        ),
      ),
    );
  }
}

class _UserAvatar extends StatelessWidget {
  static const double _size = 32;

  final String? url;
  final _Palette palette;

  const _UserAvatar({required this.url, required this.palette});

  @override
  Widget build(BuildContext context) {
    final resolved = ApiGateway.instance.avatarUrl(url);
    final placeholder = Icon(Icons.person, size: 18, color: palette.avatarIcon);

    return Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: palette.avatarBackground,
        border: Border.all(color: palette.avatarBorder, width: 1),
      ),
      child: ClipOval(
        child: resolved.isEmpty
            ? placeholder
            : Image.network(
                resolved,
                width: _size,
                height: _size,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => placeholder,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return const Center(
                    child: CupertinoActivityIndicator(radius: 7),
                  );
                },
              ),
      ),
    );
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../main.dart';

class ChatScreen extends StatefulWidget {
  final Map<String, dynamic> user;

  const ChatScreen({super.key, required this.user});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const List<String> _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static const TextStyle _subStyle = TextStyle(
    fontSize: 10,
    height: 1.1,
    color: Color(0xFF8E8E93),
  );

  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final SupabaseClient _supabase = Supabase.instance.client;
  final PresenceService _presence = PresenceService.instance;

  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  DateTime? _lastSeen;
  StreamSubscription? _messageSubscription;
  StreamSubscription? _profileSubscription;

  String get _currentUserId => _supabase.auth.currentUser?.id ?? '';
  String get _targetUserId => widget.user['id'] ?? '';

  @override
  void initState() {
    super.initState();
    _lastSeen = _parseTime(widget.user['last_seen']);
    _initChat();
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    _profileSubscription?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initChat() async {
    await _loadLocalMessages();
    _listenMessages();
    _listenProfile();
    await _fetchRemoteMessages();
  }

  Future<File> _getLocalFile() async {
    final dir = await getApplicationDocumentsDirectory();
    final filename = 'chat_${_currentUserId}_$_targetUserId.json';
    return File('${dir.path}/$filename');
  }

  Future<void> _loadLocalMessages() async {
    try {
      final file = await _getLocalFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        final List<dynamic> jsonList = jsonDecode(content);
        if (mounted) {
          setState(() {
            _messages = List<Map<String, dynamic>>.from(jsonList);
            _isLoading = false;
          });
          _scrollToBottom();
        }
      }
    } catch (_) {}
  }

  Future<void> _saveLocalMessages() async {
    try {
      final file = await _getLocalFile();
      await file.writeAsString(jsonEncode(_messages));
    } catch (_) {}
  }

  void _listenMessages() {
    _messageSubscription = _supabase
        .from('messages')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: true)
        .listen((data) {
          _processIncomingMessages(data);
        });
  }

  void _listenProfile() {
    if (_targetUserId.isEmpty) return;

    _profileSubscription = _supabase
        .from('profiles')
        .stream(primaryKey: ['id'])
        .eq('id', _targetUserId)
        .listen((rows) {
          if (rows.isEmpty || !mounted) return;
          setState(() => _lastSeen = _parseTime(rows.first['last_seen']));
        });
  }

  DateTime? _parseTime(dynamic raw) {
    if (raw is! String || raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toLocal();
  }

  Future<void> _markSeen() async {
    try {
      await _supabase.rpc('mark_seen', params: {'p_sender': _targetUserId});
    } catch (_) {}
  }

  Future<void> _processIncomingMessages(List<Map<String, dynamic>> data) async {
    final filtered = data.where((msg) {
      final s = msg['sender_id'];
      final r = msg['receiver_id'];
      return (s == _currentUserId && r == _targetUserId) ||
          (s == _targetUserId && r == _currentUserId);
    }).toList();

    final hasUnseen = filtered.any(
      (msg) => msg['receiver_id'] == _currentUserId && msg['status'] != 'seen',
    );
    if (hasUnseen) _markSeen();

    if (mounted) {
      setState(() {
        _messages = filtered;
        _isLoading = false;
      });
      _saveLocalMessages();
      _scrollToBottom();
    }
  }

  Future<void> _fetchRemoteMessages() async {
    try {
      final response = await _supabase
          .from('messages')
          .select()
          .or(
            'and(sender_id.eq.$_currentUserId,receiver_id.eq.$_targetUserId),and(sender_id.eq.$_targetUserId,receiver_id.eq.$_currentUserId)',
          )
          .order('created_at', ascending: true);

      final List<Map<String, dynamic>> fetched =
          List<Map<String, dynamic>>.from(response);
      _processIncomingMessages(fetched);
    } catch (_) {
      if (mounted && _messages.isNotEmpty) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _encryptMessage(String text) {
    try {
      return base64Encode(utf8.encode(text));
    } catch (_) {
      return text;
    }
  }

  String _decryptMessage(String encoded) {
    try {
      return utf8.decode(base64Decode(encoded));
    } catch (_) {
      return encoded;
    }
  }

  String _formatDate(String? isoString) {
    if (isoString == null || isoString.isEmpty) return '';
    try {
      final dt = DateTime.parse(isoString).toLocal();
      return '${dt.day} ${_months[dt.month - 1]} ${dt.year}';
    } catch (_) {
      return '';
    }
  }

  String _formatSeen(DateTime dt) {
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final min = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    final year = dt.year == DateTime.now().year ? '' : ' ${dt.year}';
    return '${dt.day} ${_months[dt.month - 1]}$year, $hour:$min $period';
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _currentUserId.isEmpty || _targetUserId.isEmpty) return;

    _messageController.clear();

    final encryptedText = _encryptMessage(text);
    final initialStatus = _presence.onlineIds.value.contains(_targetUserId)
        ? 'delivered'
        : 'sent';
    final tempId = DateTime.now().microsecondsSinceEpoch.toString();

    setState(() {
      _messages.add({
        'id': tempId,
        'sender_id': _currentUserId,
        'receiver_id': _targetUserId,
        'message': encryptedText,
        'status': initialStatus,
        'created_at': DateTime.now().toIso8601String(),
      });
    });
    _saveLocalMessages();
    _scrollToBottom();

    try {
      final row = await _supabase
          .from('messages')
          .insert({
            'sender_id': _currentUserId,
            'receiver_id': _targetUserId,
            'message': encryptedText,
            'status': initialStatus,
          })
          .select()
          .single();

      if (!mounted) return;
      setState(() {
        _messages.removeWhere((m) => m['id'] == tempId);
        if (!_messages.any((m) => m['id'] == row['id'])) _messages.add(row);
      });
      _saveLocalMessages();
    } catch (_) {
      if (!mounted) return;
      setState(() => _messages.removeWhere((m) => m['id'] == tempId));
      _messageController.text = text;
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
      return _supabase.storage.from('avatars').getPublicUrl(trimmed);
    } catch (_) {
      return trimmed;
    }
  }

  Widget _buildStatus() {
    return ListenableBuilder(
      listenable: Listenable.merge([_presence.connected, _presence.onlineIds]),
      builder: (context, _) {
        if (!_presence.connected.value) {
          return const Text('No connection!', style: _subStyle);
        }

        if (_presence.onlineIds.value.contains(_targetUserId)) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('online', style: _subStyle),
              const SizedBox(width: 4),
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: Color(0xFF34C759),
                  shape: BoxShape.circle,
                ),
              ),
            ],
          );
        }

        final seen = _lastSeen;
        return Text(
          seen == null ? 'offline' : 'Last seen at ${_formatSeen(seen)}',
          style: _subStyle,
        );
      },
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
    final dividerColor = isDark
        ? const Color(0xFF2C2C2C)
        : const Color(0xFFE5E5E5);
    final textColor = isDark ? Colors.white : Colors.black87;
    final inputBgColor = isDark
        ? const Color(0xFF1E1E1E)
        : const Color(0xFFF0F0F0);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(44),
        child: AppBar(
          backgroundColor: bgColor,
          elevation: 0,
          automaticallyImplyLeading: false,
          titleSpacing: 0,
          title: SafeArea(
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(32, 32),
                    onPressed: () => Navigator.pop(context),
                    child: Icon(
                      Icons.arrow_back_ios_new,
                      size: 20,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _ChatUserAvatar(url: profileUrl, isDark: isDark),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fullName,
                          style: TextStyle(
                            fontSize: 16,
                            height: 1.15,
                            fontWeight: FontWeight.w600,
                            color: textColor,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 1),
                        _buildStatus(),
                      ],
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
          children: [
            Divider(height: 0.5, thickness: 0.5, color: dividerColor),
            Expanded(
              child: Container(
                color: bgColor,
                child: _isLoading
                    ? const ChatSkeletonLoader()
                    : _messages.isEmpty
                    ? Center(
                        child: Text(
                          'No messages yet',
                          style: TextStyle(
                            fontSize: 14,
                            color: isDark
                                ? const Color(0xFF8E8E93)
                                : const Color(0xFF8E8E93),
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final msg = _messages[index];
                          final isMe = msg['sender_id'] == _currentUserId;
                          final decryptedText = _decryptMessage(
                            msg['message'] ?? '',
                          );
                          final dateStr = _formatDate(msg['created_at']);
                          final status = msg['status'] ?? 'sent';

                          return MessageBubble(
                            message: decryptedText,
                            date: dateStr,
                            isMe: isMe,
                            isDark: isDark,
                            status: status,
                          );
                        },
                      ),
              ),
            ),
            Divider(height: 0.5, thickness: 0.5, color: dividerColor),
            Container(
              color: bgColor,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.add,
                    size: 24,
                    color: isDark
                        ? const Color(0xFF8E8E93)
                        : const Color(0xFF8E8E93),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: inputBgColor,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: TextField(
                        controller: _messageController,
                        maxLines: null,
                        keyboardType: TextInputType.multiline,
                        style: TextStyle(fontSize: 15, color: textColor),
                        decoration: InputDecoration(
                          hintText: 'Message...',
                          hintStyle: TextStyle(
                            fontSize: 14,
                            color: isDark
                                ? const Color(0xFF8E8E93)
                                : const Color(0xFF8E8E93),
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 10,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(36, 36),
                    onPressed: _sendMessage,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: const BoxDecoration(
                        color: CupertinoColors.activeBlue,
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.send_rounded,
                          size: 18,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MessageBubble extends StatelessWidget {
  final String message;
  final String date;
  final bool isMe;
  final bool isDark;
  final String status;

  const MessageBubble({
    super.key,
    required this.message,
    required this.date,
    required this.isMe,
    required this.isDark,
    required this.status,
  });

  Widget _buildStatusIcon() {
    if (!isMe) return const SizedBox.shrink();

    final statusColor = isDark
        ? const Color(0xFF8E8E93)
        : const Color(0xFF8E8E93);

    if (status == 'sent') {
      return Icon(Icons.check, size: 12, color: statusColor);
    } else if (status == 'delivered') {
      return Icon(Icons.done_all, size: 12, color: statusColor);
    } else if (status == 'seen') {
      return const Icon(
        Icons.done_all,
        size: 12,
        color: CupertinoColors.activeBlue,
      );
    }
    return Icon(Icons.check, size: 12, color: statusColor);
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: BoxConstraints(maxWidth: screenWidth * 0.70),
        child: Column(
          crossAxisAlignment: isMe
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isMe
                    ? CupertinoColors.activeBlue
                    : (isDark
                          ? const Color(0xFF262626)
                          : const Color(0xFFE4E6EB)),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Text(
                message,
                style: TextStyle(
                  fontSize: 15,
                  color: isMe
                      ? Colors.white
                      : (isDark ? Colors.white : Colors.black87),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 2, left: 4, right: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (date.isNotEmpty)
                    Text(
                      date,
                      style: TextStyle(
                        fontSize: 8,
                        color: isDark
                            ? const Color(0xFF8E8E93)
                            : const Color(0xFF8E8E93),
                      ),
                    ),
                  if (isMe && date.isNotEmpty) const SizedBox(width: 4),
                  if (isMe) _buildStatusIcon(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ChatSkeletonLoader extends StatefulWidget {
  const ChatSkeletonLoader({super.key});

  @override
  State<ChatSkeletonLoader> createState() => _ChatSkeletonLoaderState();
}

class _ChatSkeletonLoaderState extends State<ChatSkeletonLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark
        ? const Color(0xFF222222)
        : const Color(0xFFE0E0E0);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: 6,
          itemBuilder: (context, index) {
            final isRight = index % 2 == 0;
            return Align(
              alignment: isRight ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 6),
                width: 140.0 + (index * 15 % 60),
                height: 36,
                decoration: BoxDecoration(
                  color: baseColor.withValues(
                    alpha: 0.3 + (_controller.value * 0.4),
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _ChatUserAvatar extends StatefulWidget {
  final String? url;
  final bool isDark;

  const _ChatUserAvatar({this.url, required this.isDark});

  @override
  State<_ChatUserAvatar> createState() => _ChatUserAvatarState();
}

class _ChatUserAvatarState extends State<_ChatUserAvatar> {
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
  void didUpdateWidget(covariant _ChatUserAvatar oldWidget) {
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
      final file = File('${dir.path}/avatar_chat_$key.png');

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
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: bgBase,
        border: Border.all(
          color: widget.isDark
              ? _silverColor.withValues(alpha: 0.5)
              : _silverColor,
          width: 0.8,
        ),
      ),
      child: ClipOval(child: _buildAvatarContent()),
    );
  }

  Widget _buildAvatarContent() {
    if (_cachedFile != null) {
      return Image.file(_cachedFile!, width: 34, height: 34, fit: BoxFit.cover);
    }

    if (_isLoading) {
      return const Center(child: CupertinoActivityIndicator(radius: 6));
    }

    return Icon(
      Icons.person,
      size: 18,
      color: widget.isDark ? Colors.white70 : Colors.black54,
    );
  }
}

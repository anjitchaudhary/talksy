import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../api_gateway.dart';
import '../../../../main.dart';

const _months = [
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

const _grey = Color(0xFF8E8E93);
const _subStyle = TextStyle(fontSize: 10, height: 1.1, color: _grey);
const _noNetMsg = 'Your connection is either slow or no connection!';

const unsentLabel = 'Message is unsent';
const _reactions = ['😡', '😩', '😭', '😅', '❤️', '👍'];
const _holdTime = Duration(milliseconds: 500);
const _editWindow = Duration(minutes: 30);
const _sliderGap = 6.0;
const _sliderRoom = 220.0;

String _fmtTime(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  final dt = DateTime.tryParse(iso)?.toLocal();
  if (dt == null) return '';
  final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
  final m = dt.minute.toString().padLeft(2, '0');
  final ampm = dt.hour >= 12 ? 'PM' : 'AM';
  return '$h:$m $ampm';
}

String _fmtFullDate(String? iso) {
  if (iso == null || iso.isEmpty) return 'Unknown Date';
  final dt = DateTime.tryParse(iso)?.toLocal();
  if (dt == null) return 'Unknown Date';
  final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
  final m = dt.minute.toString().padLeft(2, '0');
  final ampm = dt.hour >= 12 ? 'PM' : 'AM';
  return '${dt.day} ${_months[dt.month - 1]} ${dt.year} at $h:$m $ampm';
}

String _fmtSeen(DateTime dt) {
  final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
  final m = dt.minute.toString().padLeft(2, '0');
  final ampm = dt.hour >= 12 ? 'PM' : 'AM';
  final yr = dt.year == DateTime.now().year ? '' : ' ${dt.year}';
  return '${dt.day} ${_months[dt.month - 1]}$yr $h:$m $ampm';
}

DateTime? _parseTime(dynamic raw) {
  if (raw is! String || raw.isEmpty) return null;
  return DateTime.tryParse(raw)?.toLocal();
}

String _encode(String text) => base64Encode(utf8.encode(text));

String _decode(String text) {
  try {
    return utf8.decode(base64Decode(text));
  } catch (_) {
    return text;
  }
}

String _nameOf(Map<String, dynamic> u) {
  final full = '${u['first_name'] ?? ''} ${u['last_name'] ?? ''}'.trim();
  if (full.isNotEmpty) return full;
  final disp = (u['display_name'] ?? '').toString();
  if (disp.isNotEmpty) return disp;
  final mail = (u['email'] ?? '').toString();
  return mail.isNotEmpty ? mail.split('@').first : 'User';
}

String _avatarOf(Map<String, dynamic> u) {
  final raw = u['avatar_url'];
  if (raw is! String) return '';
  final url = raw.trim();
  if (url.isEmpty || url.startsWith('/') || url.contains('data/user')) {
    return '';
  }
  if (url.startsWith('http://') || url.startsWith('https://')) return url;
  try {
    return Supabase.instance.client.storage.from('avatars').getPublicUrl(url);
  } catch (_) {
    return url;
  }
}

bool _isUnsent(Map<String, dynamic> m) => m['is_unsent'] == true;

Rect _rectOf(BuildContext context) {
  final box = context.findRenderObject() as RenderBox;
  return box.localToGlobal(Offset.zero) & box.size;
}

class ChatScreen extends StatefulWidget {
  final Map<String, dynamic> user;

  const ChatScreen({super.key, required this.user});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  final _gateway = ApiGateway.instance;
  final _presence = PresenceService.instance;
  final _lastSeen = ValueNotifier<DateTime?>(null);
  final _notice = ValueNotifier<bool>(false);
  final _pending = <String>{};

  List<Map<String, dynamic>> _msgs = [];
  Map<String, dynamic> _meProfile = {};
  Map<String, dynamic>? _replying;
  Map<String, dynamic>? _editing;
  bool _loading = true;
  Timer? _noticeTimer;
  StreamSubscription? _msgSub;
  StreamSubscription? _profileSub;

  String get _me => _gateway.currentUser?.id ?? '';
  String get _other => (widget.user['id'] ?? '').toString();

  Map<String, dynamic> get _meUser {
    if (_meProfile.isNotEmpty) return _meProfile;
    final auth = _gateway.currentUser;
    return {...?auth?.userMetadata, 'email': auth?.email};
  }

  @override
  void initState() {
    super.initState();
    _lastSeen.value = _parseTime(widget.user['last_seen']);
    _presence.connected.addListener(_onNetChange);
    _init();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    precacheImage(const AssetImage('assets/images/light_doodle.png'), context);
    precacheImage(const AssetImage('assets/images/dark_doodle.png'), context);
  }

  @override
  void dispose() {
    _presence.connected.removeListener(_onNetChange);
    _noticeTimer?.cancel();
    _msgSub?.cancel();
    _profileSub?.cancel();
    _lastSeen.dispose();
    _notice.dispose();
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    unawaited(_loadMe());
    await _loadLocal();
    _listenMessages();
    _listenProfile();
    await _fetchRemote();
  }

  void _onNetChange() {
    if (!_presence.connected.value) return;
    _listenMessages();
    _listenProfile();
    _fetchRemote();
  }

  Future<File> _localFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/chat_${_me}_$_other.json');
  }

  Future<File> _meFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/profile_$_me.json');
  }

  Future<void> _loadLocal() async {
    try {
      final file = await _localFile();
      if (!await file.exists()) return;
      final list = jsonDecode(await file.readAsString()) as List;
      if (!mounted) return;
      setState(() {
        _msgs = List<Map<String, dynamic>>.from(list);
        _loading = false;
      });
    } catch (_) {}
  }

  Future<void> _saveLocal() async {
    try {
      final file = await _localFile();
      final saved = _msgs.where((m) => !_pending.contains(m['id'])).toList();
      await file.writeAsString(jsonEncode(saved));
    } catch (_) {}
  }

  Future<void> _loadMe() async {
    if (_me.isEmpty) return;
    try {
      final file = await _meFile();
      if (await file.exists()) {
        final saved = jsonDecode(await file.readAsString()) as Map;
        if (mounted) {
          setState(() => _meProfile = Map<String, dynamic>.from(saved));
        }
      }
      unawaited(_ChatUserAvatar.fetch(_avatarOf(_meUser)));

      final row = await _gateway.fetchProfile(_me);
      if (row == null) return;
      await file.writeAsString(jsonEncode(row));
      if (mounted) setState(() => _meProfile = row);
      unawaited(_ChatUserAvatar.fetch(_avatarOf(row)));
    } catch (_) {}
  }

  void _listenMessages() {
    _msgSub?.cancel();
    _msgSub = _gateway
        .streamMessages(_me, _other)
        .listen(_onMessages, onError: (_) => _streamFailed());
  }

  void _streamFailed() {
    if (mounted && _loading) setState(() => _loading = false);
  }

  void _listenProfile() {
    if (_other.isEmpty) return;
    _profileSub?.cancel();
    _profileSub = _gateway.streamProfile(_other).listen((rows) {
      if (rows.isEmpty) return;
      _lastSeen.value = _parseTime(rows.first['last_seen']);
    }, onError: (_) {});
  }

  Future<void> _fetchRemote() async {
    try {
      final res = await _gateway.fetchMessages(_me, _other);
      _onMessages(res);
    } catch (_) {
      if (mounted && _loading) setState(() => _loading = false);
    }
  }

  Future<void> _markSeen() async {
    try {
      await _gateway.markSeen(_other);
    } catch (_) {}
  }

  void _onMessages(List<Map<String, dynamic>> data) {
    if (data.any((m) => m['receiver_id'] == _me && m['status'] != 'seen')) {
      _markSeen();
    }
    if (!mounted) return;

    final queued = _msgs.where((m) => _pending.contains(m['id'])).toList();
    final known = _msgs.map((m) => m['id']).toSet();
    for (final row in data) {
      if (known.contains(row['id']) || row['sender_id'] != _me) continue;
      final i = queued.indexWhere((q) => q['message'] == row['message']);
      if (i == -1) continue;
      _pending.remove(queued[i]['id']);
      queued.removeAt(i);
    }

    setState(() {
      _msgs = [...data, ...queued];
      _loading = false;
    });
    _saveLocal();
  }

  void _toBottom() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      0,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  void _flashNotice() {
    _noticeTimer?.cancel();
    _notice.value = true;
    _noticeTimer = Timer(const Duration(seconds: 2), () {
      _notice.value = false;
    });
  }

  Map<String, dynamic>? _find(dynamic id) {
    if (id == null) return null;
    for (final m in _msgs) {
      if (m['id'] == id) return m;
    }
    return null;
  }

  String _who(Map<String, dynamic> m) {
    return m['sender_id'] == _me ? 'You' : _nameOf(widget.user);
  }

  String _preview(Map<String, dynamic> m) {
    return _isUnsent(m) ? unsentLabel : _decode(m['message'] ?? '');
  }

  bool _canEdit(Map<String, dynamic> m) {
    final at = _parseTime(m['created_at']);
    return at != null && DateTime.now().difference(at) <= _editWindow;
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _me.isEmpty || _other.isEmpty) return;

    if (!_presence.connected.value) {
      _flashNotice();
      return;
    }

    if (_editing != null) {
      await _commitEdit(text);
      return;
    }

    _input.clear();

    final reply = _replying;
    final replyId = reply?['id'];
    final body = _encode(text);
    final status = _presence.onlineIds.value.contains(_other)
        ? 'delivered'
        : 'sent';
    final tempId = 'tmp_${DateTime.now().microsecondsSinceEpoch}';

    _pending.add(tempId);
    setState(() {
      _replying = null;
      _msgs.add({
        'id': tempId,
        'sender_id': _me,
        'receiver_id': _other,
        'message': body,
        'status': status,
        'reply_to': replyId,
        'is_unsent': false,
        'created_at': DateTime.now().toIso8601String(),
      });
    });
    _toBottom();

    try {
      final row = await _gateway.sendMessage(
        senderId: _me,
        receiverId: _other,
        message: body,
        status: status,
        replyTo: replyId,
      );

      _pending.remove(tempId);
      if (!mounted) return;
      setState(() {
        _msgs.removeWhere((m) => m['id'] == tempId);
        if (!_msgs.any((m) => m['id'] == row['id'])) _msgs.add(row);
      });
      _saveLocal();
    } catch (_) {
      _pending.remove(tempId);
      if (!mounted) return;
      setState(() {
        _msgs.removeWhere((m) => m['id'] == tempId);
        _replying ??= reply;
      });
      _input.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
      _flashNotice();
    }
  }

  Future<void> _mutate(
    String id,
    Map<String, dynamic> changes,
    Future<bool> Function() action,
  ) async {
    if (!_presence.connected.value) {
      _flashNotice();
      return;
    }

    final i = _msgs.indexWhere((m) => m['id'] == id);
    if (i == -1) return;
    final before = _msgs[i];
    setState(() => _msgs[i] = {...before, ...changes});
    _saveLocal();

    try {
      final ok = await action();
      if (!ok) throw StateError('rejected');
    } catch (_) {
      if (!mounted) return;
      final j = _msgs.indexWhere((m) => m['id'] == id);
      if (j != -1) setState(() => _msgs[j] = before);
      _saveLocal();
      _flashNotice();
    }
  }

  void _react(Map<String, dynamic> m, String? emoji) {
    _mutate(m['id'], {
      'reaction': emoji,
      'reacted_at': emoji == null
          ? null
          : DateTime.now().toUtc().toIso8601String(),
    }, () => _gateway.reactMessage(m['id'], emoji));
  }

  void _unsend(Map<String, dynamic> m) {
    if (_editing?['id'] == m['id'] || _replying?['id'] == m['id']) {
      _cancelCompose();
    }
    _mutate(m['id'], {
      'is_unsent': true,
      'message': '',
      'reaction': null,
      'reacted_at': null,
    }, () => _gateway.unsendMessage(m['id']));
  }

  Future<void> _commitEdit(String text) async {
    final target = _editing;
    if (target == null) return;

    final unchanged = text == _decode(target['message'] ?? '');
    if (unchanged || !_canEdit(target)) {
      _cancelCompose();
      return;
    }

    final body = _encode(text);
    _cancelCompose();
    await _mutate(target['id'], {
      'message': body,
      'is_edited': true,
    }, () => _gateway.editMessage(target['id'], body));
  }

  void _startEdit(Map<String, dynamic> m) {
    _cancelCompose();
    final text = _decode(m['message'] ?? '');
    setState(() => _editing = m);
    _input.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _focus.requestFocus();
  }

  void _startReply(Map<String, dynamic> m) {
    _cancelCompose();
    setState(() => _replying = m);
    _focus.requestFocus();
  }

  void _cancelCompose() {
    final wasEditing = _editing != null;
    setState(() {
      _editing = null;
      _replying = null;
    });
    if (wasEditing) _input.clear();
  }

  void _showMessageDetails(Map<String, dynamic> m) {
    final isMine = m['sender_id'] == _me;
    final formatted = _fmtFullDate(m['created_at']);

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black45,
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (context, anim, secAnim) => const SizedBox.shrink(),
      transitionBuilder: (context, anim, secAnim, child) {
        final dark = Theme.of(context).brightness == Brightness.dark;
        final curved = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(curved),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                margin: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 24,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: dark ? const Color(0xFF1E1E1E) : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 16,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isMine ? 'Sent Message Info' : 'Received Message Info',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: dark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        formatted,
                        style: const TextStyle(fontSize: 11, color: _grey),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _onHold(Map<String, dynamic> m, Rect anchor) {
    if (_pending.contains(m['id']) || _isUnsent(m)) return;
    HapticFeedback.mediumImpact();

    final mine = m['sender_id'] == _me;
    final text = _decode(m['message'] ?? '');
    void copy() => Clipboard.setData(ClipboardData(text: text));

    showSlider(
      context: context,
      anchor: anchor,
      alignRight: mine,
      child: mine
          ? SentSlider(
              canEdit: _canEdit(m),
              onCopy: copy,
              onEdit: () => _startEdit(m),
              onReply: () => _startReply(m),
              onUnsend: () => _unsend(m),
            )
          : ReceivedSlider(
              current: (m['reaction'] ?? '').toString(),
              onReact: (e) => _react(m, e == m['reaction'] ? null : e),
              onCopy: copy,
              onReply: () => _startReply(m),
            ),
    );
  }

  void _showReactor(Map<String, dynamic> m, Rect anchor) {
    final byMe = m['sender_id'] != _me;
    final user = byMe ? _meUser : widget.user;

    showSlider(
      context: context,
      anchor: anchor,
      alignRight: !byMe,
      child: ReactSlider(
        name: _nameOf(user),
        avatarUrl: _avatarOf(user),
        emoji: (m['reaction'] ?? '').toString(),
        removable: byMe,
        onRemove: () => _react(m, null),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = dark ? const Color(0xFF121212) : Colors.white;
    final line = dark ? const Color(0xFF2C2C2C) : const Color(0xFFE5E5E5);
    final txt = dark ? Colors.white : Colors.black87;
    final field = dark ? const Color(0xFF1E1E1E) : const Color(0xFFF0F0F0);
    final doodle = dark
        ? 'assets/images/dark_doodle.png'
        : 'assets/images/light_doodle.png';

    return RepaintBoundary(
      child: Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          backgroundColor: bg,
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          automaticallyImplyLeading: false,
          titleSpacing: 0,
          toolbarHeight: 44,
          title: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(32, 32),
                  onPressed: () => Navigator.pop(context),
                  child: Icon(Icons.arrow_back_ios_new, size: 20, color: txt),
                ),
                const SizedBox(width: 8),
                _ChatUserAvatar(url: _avatarOf(widget.user), isDark: dark),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _nameOf(widget.user),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          height: 1.15,
                          fontWeight: FontWeight.w600,
                          color: txt,
                        ),
                      ),
                      const SizedBox(height: 1),
                      _PresenceLine(uid: _other, lastSeen: _lastSeen),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              Divider(height: 0.5, thickness: 0.5, color: line),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    image: DecorationImage(
                      image: AssetImage(doodle),
                      fit: BoxFit.cover,
                    ),
                  ),
                  child: Stack(
                    children: [
                      _buildList(dark),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 10,
                        child: _Notice(show: _notice),
                      ),
                    ],
                  ),
                ),
              ),
              Divider(height: 0.5, thickness: 0.5, color: line),
              Container(
                color: bg,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [_buildComposeBar(), _buildInput(txt, field)],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList(bool dark) {
    if (_loading) return const ChatSkeletonLoader();

    if (_msgs.isEmpty) {
      final borderColor = dark
          ? const Color(0xFF2C2C2C)
          : const Color(0xFFE5E5E5);
      final containerBg = dark
          ? const Color(0xFF1E1E1E)
          : const Color(0xFFF4F4F4);

      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: containerBg,
                border: Border.all(color: borderColor, width: 1),
              ),
              child: const Icon(
                Icons.chat_bubble_outline_rounded,
                size: 26,
                color: _grey,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'No messages yet.',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: _grey,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scroll,
      reverse: true,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      itemCount: _msgs.length,
      itemBuilder: (context, i) {
        final m = _msgs[_msgs.length - 1 - i];
        final replied = _find(m['reply_to']);
        return MessageBubble(
          key: ValueKey(m['id']),
          message: _decode(m['message'] ?? ''),
          date: _fmtTime(m['created_at']),
          isMe: m['sender_id'] == _me,
          isDark: dark,
          status: m['status'] ?? 'sent',
          unsent: _isUnsent(m),
          edited: m['is_edited'] == true,
          reaction: (m['reaction'] ?? '').toString(),
          replyWho: replied == null ? null : _who(replied),
          replyText: replied == null ? null : _preview(replied),
          onTap: () => _showMessageDetails(m),
          onHold: (rect) => _onHold(m, rect),
          onReactionTap: (rect) => _showReactor(m, rect),
        );
      },
    );
  }

  Widget _buildComposeBar() {
    final target = _editing ?? _replying;
    if (target == null) return const SizedBox.shrink();

    final title = _editing != null
        ? 'Edit message'
        : target['sender_id'] == _me
        ? 'Replying to yourself'
        : 'Replying to ${_nameOf(widget.user)}';

    return Padding(
      padding: const EdgeInsets.only(left: 12, right: 4, top: 8),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 34,
            decoration: BoxDecoration(
              color: CupertinoColors.activeBlue,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: CupertinoColors.activeBlue,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _preview(target),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: _grey),
                ),
              ],
            ),
          ),
          CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: const Size(36, 36),
            onPressed: _cancelCompose,
            child: const Icon(Icons.close, size: 20, color: _grey),
          ),
        ],
      ),
    );
  }

  Widget _buildInput(Color txt, Color field) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Icon(Icons.add, size: 24, color: _grey),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              decoration: BoxDecoration(
                color: field,
                borderRadius: BorderRadius.circular(20),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 80),
                child: SingleChildScrollView(
                  reverse: true,
                  child: TextField(
                    controller: _input,
                    focusNode: _focus,
                    maxLines: null,
                    keyboardType: TextInputType.multiline,
                    style: TextStyle(fontSize: 15, color: txt),
                    decoration: const InputDecoration(
                      hintText: 'Message...',
                      hintStyle: TextStyle(fontSize: 14, color: _grey),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(36, 36),
              onPressed: _send,
              child: Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  color: CupertinoColors.activeBlue,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _editing != null ? Icons.check_rounded : Icons.send_rounded,
                  size: 18,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PresenceLine extends StatelessWidget {
  final String uid;
  final ValueListenable<DateTime?> lastSeen;

  const _PresenceLine({required this.uid, required this.lastSeen});

  @override
  Widget build(BuildContext context) {
    final p = PresenceService.instance;

    return ListenableBuilder(
      listenable: Listenable.merge([p.connected, p.onlineIds, lastSeen]),
      builder: (context, _) {
        if (!p.connected.value) {
          return const Text('No connection!', style: _subStyle);
        }

        if (p.onlineIds.value.contains(uid)) {
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

        final seen = lastSeen.value;
        return Text(
          seen == null ? 'offline' : 'Last online at ${_fmtSeen(seen)}',
          style: _subStyle,
        );
      },
    );
  }
}

class _Notice extends StatelessWidget {
  final ValueListenable<bool> show;

  const _Notice({required this.show});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: show,
      builder: (context, on, child) {
        return IgnorePointer(
          child: AnimatedOpacity(
            opacity: on ? 1 : 0,
            duration: const Duration(milliseconds: 180),
            child: child,
          ),
        );
      },
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xE62C2C2E),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Text(
            _noNetMsg,
            style: TextStyle(fontSize: 11, color: Colors.white),
          ),
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
  final bool unsent;
  final bool edited;
  final String reaction;
  final String? replyWho;
  final String? replyText;
  final VoidCallback onTap;
  final ValueChanged<Rect> onHold;
  final ValueChanged<Rect> onReactionTap;

  const MessageBubble({
    super.key,
    required this.message,
    required this.date,
    required this.isMe,
    required this.isDark,
    required this.status,
    required this.unsent,
    required this.edited,
    required this.reaction,
    required this.onTap,
    required this.onHold,
    required this.onReactionTap,
    this.replyWho,
    this.replyText,
  });

  Widget _tick() {
    switch (status) {
      case 'seen':
        return const Icon(
          Icons.done_all,
          size: 12,
          color: CupertinoColors.activeBlue,
        );
      case 'delivered':
        return const Icon(Icons.done_all, size: 12, color: _grey);
      default:
        return const Icon(Icons.check, size: 12, color: _grey);
    }
  }

  Widget _quote(Color fg) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
          decoration: BoxDecoration(
            color: fg.withValues(alpha: 0.14),
            border: Border(
              left: BorderSide(
                color: isMe ? Colors.white : CupertinoColors.activeBlue,
                width: 3,
              ),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                replyWho ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
              Text(
                replyText ?? '',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: fg.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(Color bg, Color fg) {
    final quoted = !unsent && replyText != null;
    final text = Text(
      unsent ? unsentLabel : message,
      style: TextStyle(
        fontSize: 15,
        color: unsent ? fg.withValues(alpha: 0.7) : fg,
        fontStyle: unsent ? FontStyle.italic : FontStyle.normal,
      ),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(18),
      ),
      child: quoted
          ? IntrinsicWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [_quote(fg), text],
              ),
            )
          : text,
    );
  }

  Widget _chip() {
    return Builder(
      builder: (context) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onReactionTap(_rectOf(context)),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE9E9EB),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? const Color(0xFF121212) : Colors.white,
                width: 1.5,
              ),
            ),
            child: Text(reaction, style: const TextStyle(fontSize: 12)),
          ),
        );
      },
    );
  }

  Widget _meta() {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.only(top: 2, left: 4, right: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (edited && !unsent) ...[
              const Text('Edited', style: TextStyle(fontSize: 8, color: _grey)),
              const SizedBox(width: 4),
            ],
            if (date.isNotEmpty)
              Text(date, style: const TextStyle(fontSize: 8, color: _grey)),
            if (isMe && date.isNotEmpty) const SizedBox(width: 4),
            if (isMe) _tick(),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxW = MediaQuery.of(context).size.width * 0.70;
    final theirBg = isDark ? const Color(0xFF262626) : const Color(0xFFE4E6EB);
    final theirTxt = isDark ? Colors.white : Colors.black87;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: BoxConstraints(maxWidth: maxW),
        child: Column(
          crossAxisAlignment: isMe
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Padding(
                  padding: EdgeInsets.only(bottom: reaction.isEmpty ? 0 : 10),
                  child: Builder(
                    builder: (context) {
                      return _HoldDetector(
                        onHold: () => onHold(_rectOf(context)),
                        child: GestureDetector(
                          onTap: onTap,
                          child: _body(
                            isMe ? CupertinoColors.activeBlue : theirBg,
                            isMe ? Colors.white : theirTxt,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (reaction.isNotEmpty)
                  Positioned(
                    bottom: 0,
                    left: isMe ? null : 8,
                    right: isMe ? 8 : null,
                    child: _chip(),
                  ),
              ],
            ),
            _meta(),
          ],
        ),
      ),
    );
  }
}

class _HoldDetector extends StatefulWidget {
  final VoidCallback onHold;
  final Widget child;

  const _HoldDetector({required this.onHold, required this.child});

  @override
  State<_HoldDetector> createState() => _HoldDetectorState();
}

class _HoldDetectorState extends State<_HoldDetector> {
  Timer? _timer;
  Offset _start = Offset.zero;

  void _begin(PointerDownEvent e) {
    _start = e.position;
    _timer?.cancel();
    _timer = Timer(_holdTime, widget.onHold);
  }

  void _move(PointerMoveEvent e) {
    if ((e.position - _start).distance > 12) _cancel();
  }

  void _cancel() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _begin,
      onPointerMove: _move,
      onPointerUp: (_) => _cancel(),
      onPointerCancel: (_) => _cancel(),
      child: widget.child,
    );
  }
}

Future<void> showSlider({
  required BuildContext context,
  required Rect anchor,
  required bool alignRight,
  required Widget child,
}) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: const Color(0x14000000),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (context, animation, secondary) {
      return _SliderPlacement(
        anchor: anchor,
        alignRight: alignRight,
        child: child,
      );
    },
    transitionBuilder: (context, animation, secondary, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, -0.08),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _SliderPlacement extends StatelessWidget {
  final Rect anchor;
  final bool alignRight;
  final Widget child;

  const _SliderPlacement({
    required this.anchor,
    required this.alignRight,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final bottomGap =
        MediaQuery.paddingOf(context).bottom +
        MediaQuery.viewInsetsOf(context).bottom;
    final below = size.height - bottomGap - anchor.bottom > _sliderRoom;
    final edge = alignRight ? size.width - anchor.right : anchor.left;
    final side = edge < 12 ? 12.0 : edge;

    return Stack(
      children: [
        Positioned(
          left: alignRight ? null : side,
          right: alignRight ? side : null,
          top: below ? anchor.bottom + _sliderGap : null,
          bottom: below ? null : size.height - anchor.top + _sliderGap,
          child: child,
        ),
      ],
    );
  }
}

class _SliderBox extends StatelessWidget {
  final double width;
  final Widget child;

  const _SliderBox({required this.width, required this.child});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      type: MaterialType.transparency,
      child: Container(
        width: width,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 24,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: ColoredBox(
              color: dark ? const Color(0xE62C2C2E) : const Color(0xE6F7F7F7),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool danger;

  const _SliderRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tap = onTap;
    final color = tap == null
        ? _grey.withValues(alpha: 0.6)
        : danger
        ? CupertinoColors.systemRed
        : (dark ? Colors.white : Colors.black87);

    return InkWell(
      onTap: tap == null
          ? null
          : () {
              Navigator.pop(context);
              tap();
            },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 19, color: color),
            const SizedBox(width: 12),
            Text(label, style: TextStyle(fontSize: 15, color: color)),
          ],
        ),
      ),
    );
  }
}

class _SliderDivider extends StatelessWidget {
  const _SliderDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(height: 0.3, thickness: 0.3, color: Color(0x598E8E93));
  }
}

class SentSlider extends StatelessWidget {
  final bool canEdit;
  final VoidCallback onCopy;
  final VoidCallback onEdit;
  final VoidCallback onReply;
  final VoidCallback onUnsend;

  const SentSlider({
    super.key,
    required this.canEdit,
    required this.onCopy,
    required this.onEdit,
    required this.onReply,
    required this.onUnsend,
  });

  @override
  Widget build(BuildContext context) {
    return _SliderBox(
      width: 210,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SliderRow(
            icon: Icons.content_copy_rounded,
            label: 'Copy',
            onTap: onCopy,
          ),
          const _SliderDivider(),
          _SliderRow(
            icon: Icons.edit_outlined,
            label: 'Edit',
            onTap: canEdit ? onEdit : null,
          ),
          const _SliderDivider(),
          _SliderRow(icon: Icons.reply_rounded, label: 'Reply', onTap: onReply),
          const _SliderDivider(),
          _SliderRow(
            icon: Icons.undo_rounded,
            label: 'Unsent',
            onTap: onUnsend,
            danger: true,
          ),
        ],
      ),
    );
  }
}

class ReceivedSlider extends StatelessWidget {
  final String current;
  final ValueChanged<String> onReact;
  final VoidCallback onCopy;
  final VoidCallback onReply;

  const ReceivedSlider({
    super.key,
    required this.current,
    required this.onReact,
    required this.onCopy,
    required this.onReply,
  });

  @override
  Widget build(BuildContext context) {
    return _SliderBox(
      width: 256,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final e in _reactions)
                  _EmojiButton(
                    emoji: e,
                    selected: e == current,
                    onTap: () {
                      Navigator.pop(context);
                      onReact(e);
                    },
                  ),
              ],
            ),
          ),
          const _SliderDivider(),
          _SliderRow(
            icon: Icons.content_copy_rounded,
            label: 'Copy',
            onTap: onCopy,
          ),
          const _SliderDivider(),
          _SliderRow(icon: Icons.reply_rounded, label: 'Reply', onTap: onReply),
        ],
      ),
    );
  }
}

class _EmojiButton extends StatelessWidget {
  final String emoji;
  final bool selected;
  final VoidCallback onTap;

  const _EmojiButton({
    required this.emoji,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? _grey.withValues(alpha: 0.28) : null,
        ),
        child: Text(emoji, style: const TextStyle(fontSize: 24)),
      ),
    );
  }
}

class ReactSlider extends StatelessWidget {
  final String name;
  final String avatarUrl;
  final String emoji;
  final bool removable;
  final VoidCallback onRemove;

  const ReactSlider({
    super.key,
    required this.name,
    required this.avatarUrl,
    required this.emoji,
    required this.removable,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    return _SliderBox(
      width: 230,
      child: InkWell(
        onTap: removable
            ? () {
                Navigator.pop(context);
                onRemove();
              }
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              _ChatUserAvatar(url: avatarUrl, isDark: dark, size: 30),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: dark ? Colors.white : Colors.black87,
                      ),
                    ),
                    if (removable)
                      const Text('Tap to remove', style: _subStyle),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(emoji, style: const TextStyle(fontSize: 22)),
            ],
          ),
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
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final base = dark ? const Color(0xFF222222) : const Color(0xFFE0E0E0);

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: 6,
          itemBuilder: (context, i) {
            return Align(
              alignment: i % 2 == 0
                  ? Alignment.centerRight
                  : Alignment.centerLeft,
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 6),
                width: 140.0 + (i * 15 % 60),
                height: 36,
                decoration: BoxDecoration(
                  color: base.withValues(alpha: 0.3 + (_ctrl.value * 0.4)),
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
  final String url;
  final bool isDark;
  final double size;

  const _ChatUserAvatar({
    required this.url,
    required this.isDark,
    this.size = 34,
  });

  static final _cache = <String, File>{};

  static Future<File?> fetch(String url) async {
    final key = url.trim();
    if (key.isEmpty) return null;

    final known = _cache[key];
    if (known != null) return known;

    final client = HttpClient();
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/avatar_chat_${key.hashCode.abs()}.png');

      if (await file.exists() && await file.length() > 0) {
        return _cache[key] = file;
      }

      final req = await client.getUrl(Uri.parse(key));
      final res = await req.close();
      if (res.statusCode != 200) return null;

      await file.writeAsBytes(await consolidateHttpClientResponseBytes(res));
      return _cache[key] = file;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  @override
  State<_ChatUserAvatar> createState() => _ChatUserAvatarState();
}

class _ChatUserAvatarState extends State<_ChatUserAvatar> {
  static const _silver = Color(0xFFC0C0C0);

  File? _file;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _ChatUserAvatar old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) _load();
  }

  void _load() {
    final url = widget.url.trim();
    if (url.isEmpty) {
      _file = null;
      _busy = false;
      return;
    }

    final known = _ChatUserAvatar._cache[url];
    if (known != null) {
      _file = known;
      _busy = false;
      return;
    }

    _file = null;
    _busy = true;
    _ChatUserAvatar.fetch(url).then((file) => _done(url, file));
  }

  void _done(String url, File? file) {
    if (!mounted || widget.url.trim() != url) return;
    setState(() {
      _file = file;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final dark = widget.isDark;
    final size = widget.size;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: dark ? const Color(0xFF222222) : const Color(0xFFECECEC),
        border: Border.all(
          color: dark ? _silver.withValues(alpha: 0.5) : _silver,
          width: 0.8,
        ),
      ),
      child: ClipOval(child: _content(dark, size)),
    );
  }

  Widget _content(bool dark, double size) {
    final icon = Icon(
      Icons.person,
      size: size * 0.53,
      color: dark ? Colors.white70 : Colors.black54,
    );

    if (_file != null) {
      return Image.file(
        _file!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stack) => icon,
      );
    }
    if (_busy) {
      return const Center(child: CupertinoActivityIndicator(radius: 6));
    }
    return icon;
  }
}

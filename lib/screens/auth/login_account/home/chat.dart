import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

String _fmtDate(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  final dt = DateTime.tryParse(iso)?.toLocal();
  if (dt == null) return '';
  return '${dt.day} ${_months[dt.month - 1]} ${dt.year}';
}

String _fmtSeen(DateTime dt) {
  final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
  final m = dt.minute.toString().padLeft(2, '0');
  final ampm = dt.hour >= 12 ? 'PM' : 'AM';
  final yr = dt.year == DateTime.now().year ? '' : ' ${dt.year}';
  return '${dt.day} ${_months[dt.month - 1]}$yr, $h:$m $ampm';
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

class ChatScreen extends StatefulWidget {
  final Map<String, dynamic> user;

  const ChatScreen({super.key, required this.user});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _db = Supabase.instance.client;
  final _presence = PresenceService.instance;
  final _lastSeen = ValueNotifier<DateTime?>(null);
  final _notice = ValueNotifier<bool>(false);
  final _pending = <String>{};

  List<Map<String, dynamic>> _msgs = [];
  bool _loading = true;
  Timer? _noticeTimer;
  StreamSubscription? _msgSub;
  StreamSubscription? _profileSub;

  String get _me => _db.auth.currentUser?.id ?? '';
  String get _other => (widget.user['id'] ?? '').toString();

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
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _init() async {
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

  void _listenMessages() {
    _msgSub?.cancel();
    _msgSub = _db
        .from('messages')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: true)
        .listen(_onMessages, onError: (_) => _streamFailed());
  }

  void _streamFailed() {
    if (mounted && _loading) setState(() => _loading = false);
  }

  void _listenProfile() {
    if (_other.isEmpty) return;
    _profileSub?.cancel();
    _profileSub = _db
        .from('profiles')
        .stream(primaryKey: ['id'])
        .eq('id', _other)
        .listen((rows) {
          if (rows.isEmpty) return;
          _lastSeen.value = _parseTime(rows.first['last_seen']);
        }, onError: (_) {});
  }

  Future<void> _fetchRemote() async {
    try {
      final res = await _db
          .from('messages')
          .select()
          .or(
            'and(sender_id.eq.$_me,receiver_id.eq.$_other),'
            'and(sender_id.eq.$_other,receiver_id.eq.$_me)',
          )
          .order('created_at', ascending: true);
      _onMessages(List<Map<String, dynamic>>.from(res));
    } catch (_) {
      if (mounted && _loading) setState(() => _loading = false);
    }
  }

  Future<void> _markSeen() async {
    try {
      await _db.rpc('mark_seen', params: {'p_sender': _other});
    } catch (_) {}
  }

  void _onMessages(List<Map<String, dynamic>> data) {
    final rows = data.where((m) {
      final s = m['sender_id'];
      final r = m['receiver_id'];
      return (s == _me && r == _other) || (s == _other && r == _me);
    }).toList();

    if (rows.any((m) => m['receiver_id'] == _me && m['status'] != 'seen')) {
      _markSeen();
    }
    if (!mounted) return;

    final queued = _msgs.where((m) => _pending.contains(m['id'])).toList();
    final known = _msgs.map((m) => m['id']).toSet();
    for (final row in rows) {
      if (known.contains(row['id']) || row['sender_id'] != _me) continue;
      final i = queued.indexWhere((q) => q['message'] == row['message']);
      if (i == -1) continue;
      _pending.remove(queued[i]['id']);
      queued.removeAt(i);
    }

    setState(() {
      _msgs = [...rows, ...queued];
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

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _me.isEmpty || _other.isEmpty) return;

    if (!_presence.connected.value) {
      _flashNotice();
      return;
    }

    _input.clear();

    final body = _encode(text);
    final status = _presence.onlineIds.value.contains(_other)
        ? 'delivered'
        : 'sent';
    final tempId = 'tmp_${DateTime.now().microsecondsSinceEpoch}';

    _pending.add(tempId);
    setState(() {
      _msgs.add({
        'id': tempId,
        'sender_id': _me,
        'receiver_id': _other,
        'message': body,
        'status': status,
        'created_at': DateTime.now().toIso8601String(),
      });
    });
    _toBottom();

    try {
      final row = await _db
          .from('messages')
          .insert({
            'sender_id': _me,
            'receiver_id': _other,
            'message': body,
            'status': status,
          })
          .select()
          .single();

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
      setState(() => _msgs.removeWhere((m) => m['id'] == tempId));
      _input.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
      _flashNotice();
    }
  }

  String _avatarUrl() {
    final raw = widget.user['avatar_url'];
    if (raw is! String) return '';
    final url = raw.trim();
    if (url.isEmpty || url.startsWith('/') || url.contains('data/user')) {
      return '';
    }
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    try {
      return _db.storage.from('avatars').getPublicUrl(url);
    } catch (_) {
      return url;
    }
  }

  String _title() {
    final u = widget.user;
    final full = '${u['first_name'] ?? ''} ${u['last_name'] ?? ''}'.trim();
    if (full.isNotEmpty) return full;
    final disp = (u['display_name'] ?? '').toString();
    if (disp.isNotEmpty) return disp;
    final mail = (u['email'] ?? '').toString();
    return mail.isNotEmpty ? mail.split('@').first : 'User';
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
                _ChatUserAvatar(url: _avatarUrl(), isDark: dark),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _title(),
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
              Container(color: bg, child: _buildInput(txt, field)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList(bool dark) {
    if (_loading) return const ChatSkeletonLoader();

    if (_msgs.isEmpty) {
      return const Center(
        child: Text(
          'No messages yet',
          style: TextStyle(fontSize: 14, color: _grey),
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
        return MessageBubble(
          key: ValueKey(m['id']),
          message: _decode(m['message'] ?? ''),
          date: _fmtDate(m['created_at']),
          isMe: m['sender_id'] == _me,
          isDark: dark,
          status: m['status'] ?? 'sent',
        );
      },
    );
  }

  Widget _buildInput(Color txt, Color field) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.add, size: 24, color: _grey),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: field,
                borderRadius: BorderRadius.circular(20),
              ),
              child: TextField(
                controller: _input,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                style: TextStyle(fontSize: 15, color: txt),
                decoration: const InputDecoration(
                  hintText: 'Message...',
                  hintStyle: TextStyle(fontSize: 14, color: _grey),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          CupertinoButton(
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
              child: const Icon(
                Icons.send_rounded,
                size: 18,
                color: Colors.white,
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
          seen == null ? 'offline' : 'Last seen at ${_fmtSeen(seen)}',
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

  const MessageBubble({
    super.key,
    required this.message,
    required this.date,
    required this.isMe,
    required this.isDark,
    required this.status,
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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isMe ? CupertinoColors.activeBlue : theirBg,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Text(
                message,
                style: TextStyle(
                  fontSize: 15,
                  color: isMe ? Colors.white : theirTxt,
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
                      style: const TextStyle(fontSize: 8, color: _grey),
                    ),
                  if (isMe && date.isNotEmpty) const SizedBox(width: 4),
                  if (isMe) _tick(),
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

  const _ChatUserAvatar({required this.url, required this.isDark});

  @override
  State<_ChatUserAvatar> createState() => _ChatUserAvatarState();
}

class _ChatUserAvatarState extends State<_ChatUserAvatar> {
  static const _silver = Color(0xFFC0C0C0);
  static final _cache = <String, File>{};

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
    if (_cache.containsKey(url)) {
      _file = _cache[url];
      _busy = false;
      return;
    }
    _file = null;
    _busy = true;
    _download(url);
  }

  void _done(String url, File? file) {
    if (file != null) _cache[url] = file;
    if (!mounted || widget.url.trim() != url) return;
    setState(() {
      _file = file;
      _busy = false;
    });
  }

  Future<void> _download(String url) async {
    final client = HttpClient();
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/avatar_chat_${url.hashCode.abs()}.png');

      if (await file.exists()) {
        _done(url, file);
        return;
      }

      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close();
      if (res.statusCode != 200) {
        _done(url, null);
        return;
      }

      final bytes = await res.fold<List<int>>(
        [],
        (all, part) => all..addAll(part),
      );
      await file.writeAsBytes(bytes);
      _done(url, file);
    } catch (_) {
      _done(url, null);
    } finally {
      client.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = widget.isDark;

    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: dark ? const Color(0xFF222222) : const Color(0xFFECECEC),
        border: Border.all(
          color: dark ? _silver.withValues(alpha: 0.5) : _silver,
          width: 0.8,
        ),
      ),
      child: ClipOval(child: _content(dark)),
    );
  }

  Widget _content(bool dark) {
    if (_file != null) {
      return Image.file(_file!, width: 34, height: 34, fit: BoxFit.cover);
    }
    if (_busy) {
      return const Center(child: CupertinoActivityIndicator(radius: 6));
    }
    return Icon(
      Icons.person,
      size: 18,
      color: dark ? Colors.white70 : Colors.black54,
    );
  }
}

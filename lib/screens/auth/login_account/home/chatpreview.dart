import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../main.dart';
import 'chat.dart';
import 'profile/another_user.dart';

const _grey = Color(0xFF8E8E93);
const _avatarSize = 50.0;

String _decode(String text) {
  try {
    return utf8.decode(base64Decode(text));
  } catch (_) {
    return text;
  }
}

String _fmtTime(DateTime? dt) {
  if (dt == null) return '';
  final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
  final m = dt.minute.toString().padLeft(2, '0');
  return '$h:$m ${dt.hour >= 12 ? 'PM' : 'AM'}';
}

String _hash(String text) {
  var h = 0x811C9DC5;
  for (final c in text.codeUnits) {
    h = ((h ^ c) * 0x01000193) & 0xFFFFFFFF;
  }
  return h.toRadixString(16);
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

class _Preview {
  final Map<String, dynamic> raw;
  final String id;
  final String name;
  final String avatar;
  final String text;
  final String status;
  final bool mine;
  final int unread;
  final DateTime? at;

  String get line => mine ? 'You: $text' : text;

  const _Preview({
    required this.raw,
    required this.id,
    required this.name,
    required this.avatar,
    required this.text,
    required this.status,
    required this.mine,
    required this.unread,
    required this.at,
  });

  factory _Preview.from(Map<String, dynamic> r, String me) {
    final time = r['last_at'];
    return _Preview(
      raw: r,
      id: (r['id'] ?? '').toString(),
      name: _nameOf(r),
      avatar: _avatarOf(r),
      text: _decode((r['last_message'] ?? '').toString()),
      status: (r['last_status'] ?? 'sent').toString(),
      mine: r['last_sender_id'] == me,
      unread: (r['unread_count'] as num?)?.toInt() ?? 0,
      at: time is String ? DateTime.tryParse(time)?.toLocal() : null,
    );
  }
}

class ChatPreviewScreen extends StatefulWidget {
  const ChatPreviewScreen({super.key});

  @override
  State<ChatPreviewScreen> createState() => _ChatPreviewScreenState();
}

class _ChatPreviewScreenState extends State<ChatPreviewScreen> {
  final _db = Supabase.instance.client;
  final _presence = PresenceService.instance;
  final _search = TextEditingController();
  final _focus = FocusNode();

  List<_Preview> _chats = [];
  bool _loading = true;
  bool _busy = false;
  bool _queued = false;
  bool _covered = false;
  Timer? _debounce;
  Timer? _unlock;
  RealtimeChannel? _channel;

  String get _me => _db.auth.currentUser?.id ?? '';

  @override
  void initState() {
    super.initState();
    _presence.connected.addListener(_onNetChange);
    _init();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible =
        // ignore: deprecated_member_use
        (ModalRoute.of(context)?.isCurrent ?? true) && TickerMode.of(context);
    if (_covered == !visible) return;
    _covered = !visible;
    _unlock?.cancel();
    if (_covered) {
      _focus.unfocus();
      _focus.canRequestFocus = false;
    } else {
      _unlock = Timer(const Duration(milliseconds: 400), () {
        if (mounted && !_covered) _focus.canRequestFocus = true;
      });
    }
  }

  @override
  void dispose() {
    _presence.connected.removeListener(_onNetChange);
    _debounce?.cancel();
    _unlock?.cancel();
    final ch = _channel;
    if (ch != null) unawaited(_db.removeChannel(ch));
    _focus.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    await _loadLocal();
    _listen();
    await _fetch();
  }

  void _onNetChange() {
    if (_presence.connected.value) _fetch();
  }

  Future<File> _localFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/chatpreview_$_me.json');
  }

  Future<void> _loadLocal() async {
    if (_me.isEmpty) return;
    try {
      final file = await _localFile();
      if (!await file.exists()) return;
      final rows = List<Map<String, dynamic>>.from(
        jsonDecode(await file.readAsString()) as List,
      );
      if (!mounted) return;
      setState(() {
        _chats = rows.map((r) => _Preview.from(r, _me)).toList();
        _loading = false;
      });
    } catch (_) {}
  }

  Future<void> _saveLocal(List<Map<String, dynamic>> rows) async {
    try {
      final file = await _localFile();
      await file.writeAsString(jsonEncode(rows), flush: true);
    } catch (_) {}
  }

  void _listen() {
    if (_me.isEmpty || _channel != null) return;
    _channel = _db
        .channel('preview_$_me')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'messages',
          callback: (_) => _schedule(),
        )
        .subscribe();
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _fetch);
  }

  Future<void> _fetch() async {
    if (_me.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (_busy) {
      _queued = true;
      return;
    }

    _busy = true;
    try {
      final res = await _db.rpc('get_chat_previews');
      final rows = List<Map<String, dynamic>>.from(res as List);
      if (!mounted) return;
      setState(() {
        _chats = rows.map((r) => _Preview.from(r, _me)).toList();
        _loading = false;
      });
      _saveLocal(rows);
    } catch (_) {
      if (mounted && _loading) setState(() => _loading = false);
    } finally {
      _busy = false;
      if (_queued && mounted) {
        _queued = false;
        _fetch();
      }
    }
  }

  Future<void> _open(_Preview chat) async {
    await Navigator.push(
      context,
      CupertinoPageRoute(builder: (context) => ChatScreen(user: chat.raw)),
    );
    _fetch();
  }

  Future<void> _openProfile(_Preview chat) async {
    await Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (context) => AnotherUserProfileScreen(user: chat.raw),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final noUsers = !_loading && _chats.isEmpty;

    return Column(
      children: [
        if (!noUsers) _buildSearch(dark),
        Expanded(child: _buildList(dark)),
      ],
    );
  }

  Widget _buildSearch(bool dark) {
    final field = dark ? const Color(0xFF1E1E1E) : const Color(0xFFF0F0F0);
    final txt = dark ? Colors.white : Colors.black87;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: field,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            const Icon(Icons.search, size: 20, color: _grey),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _search,
                focusNode: _focus,
                onChanged: (_) => setState(() {}),
                textInputAction: TextInputAction.search,
                style: TextStyle(fontSize: 15, color: txt),
                decoration: const InputDecoration(
                  hintText: 'Search',
                  hintStyle: TextStyle(fontSize: 14, color: _grey),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
            if (_search.text.isNotEmpty)
              GestureDetector(
                onTap: () {
                  _search.clear();
                  setState(() {});
                },
                child: const Icon(Icons.cancel, size: 18, color: _grey),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(bool dark) {
    if (_loading) return const PreviewSkeleton();

    final q = _search.text.trim().toLowerCase();
    final list = q.isEmpty
        ? _chats
        : _chats.where((c) => c.name.toLowerCase().contains(q)).toList();

    if (list.isEmpty) {
      return _buildEmpty(
        _chats.isEmpty ? 'No users yet' : 'No user found.',
        dark,
      );
    }

    final line = _grey.withValues(alpha: 0.4);

    return ListView.separated(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      itemCount: list.length,
      separatorBuilder: (context, i) {
        return Divider(height: 0.4, thickness: 0.4, indent: 78, color: line);
      },
      itemBuilder: (context, i) {
        final chat = list[i];
        return _PreviewTile(
          key: ValueKey(chat.id),
          chat: chat,
          isDark: dark,
          onTap: () => _open(chat),
          onAvatarTap: () => _openProfile(chat),
        );
      },
    );
  }

  Widget _buildEmpty(String label, bool dark) {
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
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: _grey,
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewTile extends StatelessWidget {
  final _Preview chat;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback onAvatarTap;

  const _PreviewTile({
    super.key,
    required this.chat,
    required this.isDark,
    required this.onTap,
    required this.onAvatarTap,
  });

  Widget _trailing() {
    if (chat.mine) return _StatusTick(status: chat.status);
    if (chat.unread > 0) return BubbleCount(count: chat.unread);
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final txt = isDark ? Colors.white : Colors.black87;
    final sub = isDark ? Colors.white60 : Colors.black54;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onAvatarTap,
              child: _PreviewAvatar(
                uid: chat.id,
                url: chat.avatar,
                isDark: isDark,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          chat.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            height: 1.2,
                            fontWeight: FontWeight.w600,
                            color: txt,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _fmtTime(chat.at),
                        style: const TextStyle(fontSize: 11, color: _grey),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 22,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            chat.line,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 14, color: sub),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _trailing(),
                      ],
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

class BubbleCount extends StatelessWidget {
  final int count;

  const BubbleCount({super.key, required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: CupertinoColors.activeBlue,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: const TextStyle(
          fontSize: 11,
          height: 1.1,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _StatusTick extends StatelessWidget {
  final String status;

  const _StatusTick({required this.status});

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case 'seen':
        return const Icon(
          Icons.done_all,
          size: 16,
          color: CupertinoColors.activeBlue,
        );
      case 'delivered':
        return const Icon(Icons.done_all, size: 16, color: _grey);
      default:
        return const Icon(Icons.check, size: 16, color: _grey);
    }
  }
}

abstract final class _AvatarStore {
  static final _memo = <String, File>{};
  static final _jobs = <String, Future<File?>>{};

  static File? peek(String url) => _memo[url];

  static Future<File?> get(String uid, String url) {
    return _jobs.putIfAbsent(url, () {
      return _load(uid, url).whenComplete(() {
        _jobs.remove(url);
      });
    });
  }

  static Future<File?> _load(String uid, String url) async {
    try {
      final base = await getApplicationDocumentsDirectory();
      final dir = await Directory('${base.path}/avatars')
          .create(recursive: true);
      final file = File('${dir.path}/${uid}_${_hash(url)}.img');

      if (await file.exists() && await file.length() > 0) {
        return _memo[url] = file;
      }

      final bytes = await _download(url);
      if (bytes == null || bytes.isEmpty) return null;

      final part = File('${file.path}.part');
      await part.writeAsBytes(bytes, flush: true);
      await part.rename(file.path);
      await _dropOld(dir, uid, file.path);
      return _memo[url] = file;
    } catch (_) {
      return null;
    }
  }

  static Future<List<int>?> _download(String url) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close().timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return null;
      return await consolidateHttpClientResponseBytes(res);
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  static Future<void> _dropOld(Directory dir, String uid, String keep) async {
    try {
      await for (final f in dir.list()) {
        final name = f.uri.pathSegments.last;
        if (f is File && f.path != keep && name.startsWith('${uid}_')) {
          await f.delete();
        }
      }
    } catch (_) {}
  }
}

class _PreviewAvatar extends StatefulWidget {
  final String uid;
  final String url;
  final bool isDark;

  const _PreviewAvatar({
    required this.uid,
    required this.url,
    required this.isDark,
  });

  @override
  State<_PreviewAvatar> createState() => _PreviewAvatarState();
}

class _PreviewAvatarState extends State<_PreviewAvatar> {
  static const _silver = Color(0xFFC0C0C0);

  File? _file;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant _PreviewAvatar old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) _resolve();
  }

  Future<void> _resolve() async {
    final url = widget.url;
    if (url.isEmpty) {
      _file = null;
      return;
    }

    final cached = _AvatarStore.peek(url);
    if (cached != null) {
      _file = cached;
      return;
    }

    _file = null;
    final file = await _AvatarStore.get(widget.uid, url);
    if (!mounted || widget.url != url || file == null) return;
    setState(() => _file = file);
  }

  Widget _icon() {
    return Icon(
      Icons.person,
      size: 26,
      color: widget.isDark ? Colors.white70 : Colors.black54,
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = widget.isDark;
    final file = _file;

    return Container(
      width: _avatarSize,
      height: _avatarSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: dark ? const Color(0xFF222222) : const Color(0xFFECECEC),
        border: Border.all(
          color: dark ? _silver.withValues(alpha: 0.5) : _silver,
          width: 0.8,
        ),
      ),
      child: ClipOval(
        child: file == null
            ? _icon()
            : Image.file(
                file,
                width: _avatarSize,
                height: _avatarSize,
                fit: BoxFit.cover,
                cacheWidth: 150,
                gaplessPlayback: true,
                errorBuilder: (context, error, stack) => _icon(),
              ),
      ),
    );
  }
}

class PreviewSkeleton extends StatefulWidget {
  const PreviewSkeleton({super.key});

  @override
  State<PreviewSkeleton> createState() => _PreviewSkeletonState();
}

class _PreviewSkeletonState extends State<PreviewSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _fade = Tween<double>(
      begin: 0.35,
      end: 1,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final base = dark ? const Color(0xFF2A2A2A) : const Color(0xFFE2E2E2);

    return FadeTransition(
      opacity: _fade,
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 10,
        itemBuilder: (context, i) {
          return _SkeletonRow(
            color: base,
            nameWidth: 80.0 + (i * 23 % 60),
            textWidth: 150.0 + (i * 37 % 90),
          );
        },
      ),
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  final Color color;
  final double nameWidth;
  final double textWidth;

  const _SkeletonRow({
    required this.color,
    required this.nameWidth,
    required this.textWidth,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: _avatarSize,
            height: _avatarSize,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _Bar(width: nameWidth, height: 14, color: color),
                    const Spacer(),
                    _Bar(width: 34, height: 10, color: color),
                  ],
                ),
                const SizedBox(height: 10),
                _Bar(width: textWidth, height: 12, color: color),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  final double width;
  final double height;
  final Color color;

  const _Bar({required this.width, required this.height, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }
}

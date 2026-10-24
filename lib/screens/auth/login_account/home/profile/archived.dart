import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../../api_gateway.dart';
import '../../../../../local_db.dart';
import '../../../../../main.dart';
import '../chat.dart';
import '../chatpreview.dart';
import 'another_user.dart';

const _grey = Color(0xFF8E8E93);
const _maxContentWidth = 720.0;
const _maxTextScale = 1.3;

class ArchivedScreen extends StatefulWidget {
  const ArchivedScreen({super.key});

  @override
  State<ArchivedScreen> createState() => _ArchivedScreenState();
}

class _ArchivedScreenState extends State<ArchivedScreen> {
  final _gateway = ApiGateway.instance;
  final _db = LocalDb.instance;
  final _presence = PresenceService.instance;
  final _search = TextEditingController();
  final _focus = FocusNode();

  List<ChatPreview> _chats = [];
  bool _loading = true;
  bool _busy = false;
  bool _queued = false;
  bool _covered = false;
  Timer? _debounce;
  Timer? _unlock;
  RealtimeChannel? _channel;

  String get _me => _gateway.currentUser?.id ?? '';

  @override
  void initState() {
    super.initState();
    _presence.connected.addListener(_onNetChange);
    _gateway.archiveRevision.addListener(_onArchiveChange);
    _init();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible =
        (ModalRoute.of(context)?.isCurrent ?? true) &&
        TickerMode.valuesOf(context).enabled;
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
    _gateway.archiveRevision.removeListener(_onArchiveChange);
    _debounce?.cancel();
    _unlock?.cancel();
    final ch = _channel;
    if (ch != null) unawaited(_gateway.removeChannel(ch));
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

  void _onArchiveChange() {
    _fetch();
  }

  Future<void> _loadLocal() async {
    if (_me.isEmpty) return;
    try {
      final rows = await _db.chatPreviews(_me, archived: true);
      if (!mounted) return;
      if (rows.isNotEmpty) {
        setState(() {
          _chats = rows.map((r) => ChatPreview.from(r, _me)).toList();
          _loading = false;
        });
      } else if (await _db.previewsSynced(_me, archived: true) && mounted) {
        setState(() => _loading = false);
      }
    } catch (_) {}
  }

  Future<void> _saveLocal(List<Map<String, dynamic>> rows) async {
    try {
      await _db.saveChatPreviews(_me, rows, archived: true);
    } catch (_) {}
  }

  void _listen() {
    if (_me.isEmpty || _channel != null) return;
    _channel = _gateway
        .channel('archived_$_me')
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
      final rows = await _gateway.fetchChatPreviews(archived: true);
      if (!mounted) return;
      setState(() {
        _chats = rows.map((r) => ChatPreview.from(r, _me)).toList();
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

  Future<void> _open(ChatPreview chat) async {
    await Navigator.push(
      context,
      CupertinoPageRoute(builder: (context) => ChatScreen(user: chat.raw)),
    );
    _fetch();
  }

  Future<void> _openProfile(ChatPreview chat) async {
    await Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (context) => AnotherUserProfileScreen(user: chat.raw),
      ),
    );
  }

  void _onHold(ChatPreview chat, Rect anchor) {
    HapticFeedback.mediumImpact();
    showSlider(
      context: context,
      anchor: anchor,
      alignRight: false,
      child: ArchivedSlider(onUnarchive: () => _unarchive(chat)),
    );
  }

  void _notify(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _unarchive(ChatPreview chat) async {
    setState(() => _chats = _chats.where((c) => c.id != chat.id).toList());
    try {
      await _gateway.unarchiveChat(chat.id);
      await _cacheActive(chat);
      if (mounted) _notify('User unarchived');
    } catch (_) {
      if (!mounted) return;
      _notify('Could not unarchive chat. Try again.');
      _fetch();
    }
  }

  Future<void> _cacheActive(ChatPreview chat) async {
    try {
      await _db.cachePreview(_me, chat.raw, archived: false);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = dark ? const Color(0xFF121212) : Colors.white;
    final txt = dark ? Colors.white : Colors.black87;
    final media = MediaQuery.of(context);
    final noChats = !_loading && _chats.isEmpty;

    return MediaQuery(
      data: media.copyWith(
        textScaler: media.textScaler.clamp(maxScaleFactor: _maxTextScale),
      ),
      child: Scaffold(
        backgroundColor: bg,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(40),
          child: AppBar(
            backgroundColor: bg,
            surfaceTintColor: Colors.transparent,
            scrolledUnderElevation: 0,
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
                        color: txt,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Archived chats',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: txt,
                        ),
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
              Divider(
                height: 0.3,
                thickness: 0.3,
                color: _grey.withValues(alpha: 0.5),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: _maxContentWidth,
                    ),
                    child: Column(
                      children: [
                        if (!noChats) _buildSearch(dark),
                        Expanded(child: _buildList(dark)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
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
        _chats.isEmpty ? 'No archived chats' : 'No user found.',
        dark,
      );
    }

    final line = _grey.withValues(alpha: 0.4);

    return ListView.separated(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: list.length,
      separatorBuilder: (context, i) {
        return Divider(height: 0.4, thickness: 0.4, indent: 78, color: line);
      },
      itemBuilder: (context, i) {
        final chat = list[i];
        return PreviewTile(
          key: ValueKey(chat.id),
          chat: chat,
          isDark: dark,
          onTap: () => _open(chat),
          onHold: (rect) => _onHold(chat, rect),
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

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
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
                      Icons.archive_outlined,
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
            ),
          ),
        );
      },
    );
  }
}

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class LocalDb {
  LocalDb._();

  static final LocalDb instance = LocalDb._();

  static const int _version = 1;
  static const int _historyLimit = 30;

  static const List<String> _userColumns = [
    'first_name',
    'last_name',
    'display_name',
    'email',
    'avatar_url',
  ];

  static const List<String> _previewColumns = [
    'id',
    ..._userColumns,
    'last_seen',
    'last_message',
    'last_sender_id',
    'last_status',
    'last_at',
    'last_reaction',
    'last_reaction_at',
    'last_reaction_sender_id',
    'last_reaction_message',
  ];

  Future<Database>? _opening;

  Future<Database> get _database => _opening ??= _open();

  Future<Database> _open() async {
    try {
      final dir = await getDatabasesPath();
      return await openDatabase(
        p.join(dir, 'talksy.db'),
        version: _version,
        onCreate: _create,
      );
    } catch (_) {
      _opening = null;
      rethrow;
    }
  }

  Future<void> _create(Database db, int version) async {
    await db.execute('''
      CREATE TABLE messages (
        owner TEXT NOT NULL,
        peer TEXT NOT NULL,
        id TEXT NOT NULL,
        sender_id TEXT NOT NULL,
        receiver_id TEXT NOT NULL,
        message TEXT NOT NULL,
        status TEXT NOT NULL,
        reply_to TEXT,
        is_unsent INTEGER NOT NULL DEFAULT 0,
        is_edited INTEGER NOT NULL DEFAULT 0,
        reaction TEXT,
        reacted_at TEXT,
        created_at TEXT NOT NULL,
        created_ms INTEGER NOT NULL,
        PRIMARY KEY (owner, id)
      )
    ''');
    await db.execute(
      'CREATE INDEX messages_chat_idx ON messages (owner, peer, created_ms)',
    );

    await db.execute('''
      CREATE TABLE chat_previews (
        owner TEXT NOT NULL,
        id TEXT NOT NULL,
        position INTEGER NOT NULL,
        first_name TEXT,
        last_name TEXT,
        display_name TEXT,
        email TEXT,
        avatar_url TEXT,
        last_seen TEXT,
        last_message TEXT,
        last_sender_id TEXT,
        last_status TEXT,
        last_at TEXT,
        last_unsent INTEGER NOT NULL DEFAULT 0,
        last_reaction TEXT,
        last_reaction_at TEXT,
        last_reaction_sender_id TEXT,
        last_reaction_message TEXT,
        unread_count INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (owner, id)
      )
    ''');

    await db.execute('''
      CREATE TABLE profiles (
        id TEXT PRIMARY KEY,
        first_name TEXT,
        last_name TEXT,
        display_name TEXT,
        email TEXT,
        avatar_url TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE saved_accounts (
        id TEXT PRIMARY KEY,
        email TEXT NOT NULL UNIQUE,
        provider TEXT NOT NULL,
        first_name TEXT NOT NULL DEFAULT '',
        last_name TEXT NOT NULL DEFAULT '',
        avatar_url TEXT NOT NULL DEFAULT '',
        local_avatar_path TEXT NOT NULL DEFAULT '',
        last_login INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE search_history (
        owner TEXT NOT NULL,
        id TEXT NOT NULL,
        first_name TEXT,
        last_name TEXT,
        display_name TEXT,
        email TEXT,
        avatar_url TEXT,
        searched_at INTEGER NOT NULL,
        PRIMARY KEY (owner, id)
      )
    ''');
  }

  Future<List<Map<String, dynamic>>> messages(String owner, String peer) async {
    final db = await _database;
    final rows = await db.query(
      'messages',
      where: 'owner = ? AND peer = ?',
      whereArgs: [owner, peer],
      orderBy: 'created_ms ASC, created_at ASC',
    );
    return rows.map(_readMessage).toList();
  }

  Future<void> saveMessages(
    String owner,
    String peer,
    List<Map<String, dynamic>> rows,
  ) async {
    if (rows.isEmpty) return;
    final db = await _database;
    final batch = db.batch();
    for (final m in rows) {
      final created = (m['created_at'] ?? '').toString();
      batch.insert('messages', <String, Object?>{
        'owner': owner,
        'peer': peer,
        'id': m['id'].toString(),
        'sender_id': m['sender_id'].toString(),
        'receiver_id': m['receiver_id'].toString(),
        'message': (m['message'] ?? '').toString(),
        'status': (m['status'] ?? 'sent').toString(),
        'reply_to': m['reply_to']?.toString(),
        'is_unsent': m['is_unsent'] == true ? 1 : 0,
        'is_edited': m['is_edited'] == true ? 1 : 0,
        'reaction': m['reaction']?.toString(),
        'reacted_at': m['reacted_at']?.toString(),
        'created_at': created,
        'created_ms': DateTime.tryParse(created)?.millisecondsSinceEpoch ?? 0,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Map<String, dynamic> _readMessage(Map<String, Object?> r) {
    return {
      'id': r['id'],
      'sender_id': r['sender_id'],
      'receiver_id': r['receiver_id'],
      'message': r['message'],
      'status': r['status'],
      'reply_to': r['reply_to'],
      'is_unsent': r['is_unsent'] == 1,
      'is_edited': r['is_edited'] == 1,
      'reaction': r['reaction'],
      'reacted_at': r['reacted_at'],
      'created_at': r['created_at'],
    };
  }

  Future<List<Map<String, dynamic>>> chatPreviews(String owner) async {
    final db = await _database;
    final rows = await db.query(
      'chat_previews',
      where: 'owner = ?',
      whereArgs: [owner],
      orderBy: 'position ASC',
    );
    return rows.map<Map<String, dynamic>>((r) {
      return {
        for (final c in _previewColumns) c: r[c],
        'last_unsent': r['last_unsent'] == 1,
        'unread_count': r['unread_count'],
      };
    }).toList();
  }

  Future<void> saveChatPreviews(
    String owner,
    List<Map<String, dynamic>> rows,
  ) async {
    final db = await _database;
    final batch = db.batch();
    batch.delete('chat_previews', where: 'owner = ?', whereArgs: [owner]);
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      batch.insert('chat_previews', <String, Object?>{
        'owner': owner,
        'position': i,
        for (final c in _previewColumns) c: r[c]?.toString(),
        'last_unsent': r['last_unsent'] == true ? 1 : 0,
        'unread_count': (r['unread_count'] as num?)?.toInt() ?? 0,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<Map<String, dynamic>?> profile(String id) async {
    final db = await _database;
    final rows = await db.query(
      'profiles',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Map<String, dynamic>.from(rows.first);
  }

  Future<void> saveProfile(String id, Map<String, dynamic> row) async {
    final db = await _database;
    await db.insert('profiles', <String, Object?>{
      'id': id,
      for (final c in _userColumns) c: row[c]?.toString(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> savedAccounts() async {
    final db = await _database;
    final rows = await db.query('saved_accounts', orderBy: 'last_login DESC');
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  Future<void> saveAccount(Map<String, dynamic> account) async {
    final db = await _database;
    await db.insert('saved_accounts', <String, Object?>{
      'id': account['id'],
      'email': account['email'],
      'provider': account['provider'],
      'first_name': account['first_name'] ?? '',
      'last_name': account['last_name'] ?? '',
      'avatar_url': account['avatar_url'] ?? '',
      'local_avatar_path': account['local_avatar_path'] ?? '',
      'last_login': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> touchAccount(String id) async {
    final db = await _database;
    await db.update(
      'saved_accounts',
      {'last_login': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> removeAccount(String id) async {
    final db = await _database;
    await db.delete('saved_accounts', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> searchHistory(String owner) async {
    final db = await _database;
    final rows = await db.query(
      'search_history',
      columns: ['id', ..._userColumns],
      where: 'owner = ?',
      whereArgs: [owner],
      orderBy: 'searched_at DESC',
      limit: _historyLimit,
    );
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  Future<void> addSearch(String owner, Map<String, dynamic> user) async {
    final db = await _database;
    await db.insert('search_history', <String, Object?>{
      'owner': owner,
      'id': user['id'].toString(),
      for (final c in _userColumns) c: user[c]?.toString(),
      'searched_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> removeSearch(String owner, String id) async {
    final db = await _database;
    await db.delete(
      'search_history',
      where: 'owner = ? AND id = ?',
      whereArgs: [owner, id],
    );
  }

  Future<void> clearSearches(String owner) async {
    final db = await _database;
    await db.delete('search_history', where: 'owner = ?', whereArgs: [owner]);
  }

  Future<void> wipe(String owner) async {
    final db = await _database;
    final batch = db.batch();
    for (final table in ['messages', 'chat_previews', 'search_history']) {
      batch.delete(table, where: 'owner = ?', whereArgs: [owner]);
    }
    batch.delete('profiles', where: 'id = ?', whereArgs: [owner]);
    await batch.commit(noResult: true);
  }
}

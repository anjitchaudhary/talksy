import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

// Database helper singleton class for managing local SQLite storage.
class LocalDb {
  LocalDb._();

  static final LocalDb instance = LocalDb._();

  static const int _version = 3;
  static const int _historyLimit = 30;

  // Schema for tracking sync status across owners and scopes.
  static const String _syncMarksTable = '''
    CREATE TABLE IF NOT EXISTS sync_marks (
      owner TEXT NOT NULL,
      scope TEXT NOT NULL,
      PRIMARY KEY (owner, scope)
    )
  ''';

  // Common user profile columns used in multiple database tables.
  static const List<String> _userColumns = [
    'first_name',
    'last_name',
    'display_name',
    'email',
    'avatar_url',
  ];

  // Column list used when selecting chat preview records.
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

  // Returns active database instance or triggers open on first access.
  Future<Database> get _database => _opening ??= _open();

  // Initializes database connection with path configuration and callbacks.
  Future<Database> _open() async {
    try {
      final dir = await getDatabasesPath();
      return await openDatabase(
        p.join(dir, 'talksy.db'),
        version: _version,
        onCreate: _create,
        onUpgrade: _upgrade,
      );
    } catch (_) {
      _opening = null;
      rethrow;
    }
  }

  // Handles database schema upgrades when version number increases.
  Future<void> _upgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
        'ALTER TABLE chat_previews ADD COLUMN archived INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (oldVersion < 3) {
      await db.execute(_syncMarksTable);
    }
  }

  // Creates initial database tables and indexes on fresh install.
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
        archived INTEGER NOT NULL DEFAULT 0,
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

    await db.execute(_syncMarksTable);
  }

  // Retrieves messages for a specific conversation ordered by creation time.
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

  // Inserts or updates multiple messages using a batch transaction.
  Future<void> saveMessages(
    String owner,
    String peer,
    List<Map<String, dynamic>> rows,
  ) async {
    if (rows.isEmpty) return;
    final db = await _database;
    final batch = db.batch();
    for (final m in rows) {
      batch.insert(
        'messages',
        _messageRow(owner, peer, m),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  // Deletes existing messages for a peer and inserts fresh records.
  Future<void> replaceMessages(
    String owner,
    String peer,
    List<Map<String, dynamic>> rows,
  ) async {
    final db = await _database;
    final batch = db.batch();
    batch.delete(
      'messages',
      where: 'owner = ? AND peer = ?',
      whereArgs: [owner, peer],
    );
    for (final m in rows) {
      batch.insert(
        'messages',
        _messageRow(owner, peer, m),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  // Clears chat messages and preview entry for a target peer.
  Future<void> deleteChat(String owner, String peer) async {
    final db = await _database;
    final batch = db.batch();
    batch.delete(
      'messages',
      where: 'owner = ? AND peer = ?',
      whereArgs: [owner, peer],
    );
    batch.delete(
      'chat_previews',
      where: 'owner = ? AND id = ?',
      whereArgs: [owner, peer],
    );
    await batch.commit(noResult: true);
  }

  // Maps raw message data into table column values with safe null checks.
  Map<String, Object?> _messageRow(
    String owner,
    String peer,
    Map<String, dynamic> m,
  ) {
    final created = (m['created_at'] ?? '').toString();
    return <String, Object?>{
      'owner': owner,
      'peer': peer,
      'id': m['id']?.toString() ?? '',
      'sender_id': m['sender_id']?.toString() ?? '',
      'receiver_id': m['receiver_id']?.toString() ?? '',
      'message': (m['message'] ?? '').toString(),
      'status': (m['status'] ?? 'sent').toString(),
      'reply_to': m['reply_to']?.toString(),
      'is_unsent': m['is_unsent'] == true ? 1 : 0,
      'is_edited': m['is_edited'] == true ? 1 : 0,
      'reaction': m['reaction']?.toString(),
      'reacted_at': m['reacted_at']?.toString(),
      'created_at': created,
      'created_ms': DateTime.tryParse(created)?.millisecondsSinceEpoch ?? 0,
    };
  }

  // Converts database row map back into application-layer message format.
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

  // Fetches list of chat previews filtered by archived state.
  Future<List<Map<String, dynamic>>> chatPreviews(
    String owner, {
    bool archived = false,
  }) async {
    final db = await _database;
    final rows = await db.query(
      'chat_previews',
      where: 'owner = ? AND archived = ?',
      whereArgs: [owner, archived ? 1 : 0],
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

  // Overwrites preview list and marks the scope as synced.
  Future<void> saveChatPreviews(
    String owner,
    List<Map<String, dynamic>> rows, {
    bool archived = false,
  }) async {
    final db = await _database;
    final flag = archived ? 1 : 0;
    final batch = db.batch();
    batch.delete(
      'chat_previews',
      where: 'owner = ? AND archived = ?',
      whereArgs: [owner, flag],
    );
    for (var i = 0; i < rows.length; i++) {
      batch.insert(
        'chat_previews',
        _previewRow(owner, i, rows[i], flag),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    batch.insert('sync_marks', <String, Object?>{
      'owner': owner,
      'scope': _previewScope(archived),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await batch.commit(noResult: true);
  }

  // Inserts or replaces a single chat preview while preserving its existing sort position.
  Future<void> cachePreview(
    String owner,
    Map<String, dynamic> row, {
    required bool archived,
  }) async {
    final db = await _database;
    final id = row['id']?.toString();
    if (id == null) return;

    final archivedFlag = archived ? 1 : 0;
    final existing = await db.query(
      'chat_previews',
      columns: ['position'],
      where: 'owner = ? AND id = ? AND archived = ?',
      whereArgs: [owner, id, archivedFlag],
      limit: 1,
    );

    final position = existing.isNotEmpty
        ? (existing.first['position'] as int? ?? 0)
        : 0;

    await db.insert(
      'chat_previews',
      _previewRow(owner, position, row, archivedFlag),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // Checks if initial sync mark exists for given preview scope.
  Future<bool> previewsSynced(String owner, {bool archived = false}) async {
    final db = await _database;
    final rows = await db.query(
      'sync_marks',
      where: 'owner = ? AND scope = ?',
      whereArgs: [owner, _previewScope(archived)],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  // Checks if a chat preview exists locally or if sync status is pending for the correct scope.
  Future<bool?> hasChat(
    String owner,
    String peer, {
    bool archived = false,
  }) async {
    final db = await _database;
    final archivedFlag = archived ? 1 : 0;
    final rows = await db.query(
      'chat_previews',
      columns: ['id'],
      where: 'owner = ? AND id = ? AND archived = ?',
      whereArgs: [owner, peer, archivedFlag],
      limit: 1,
    );
    if (rows.isNotEmpty) return true;
    return await previewsSynced(owner, archived: archived) ? false : null;
  }

  // Returns scope key corresponding to archive status.
  String _previewScope(bool archived) => archived ? 'archived' : 'previews';

  // Formats row values for chat preview table insertion with safe null checks.
  Map<String, Object?> _previewRow(
    String owner,
    int position,
    Map<String, dynamic> r,
    int archived,
  ) {
    return <String, Object?>{
      'owner': owner,
      'position': position,
      for (final c in _previewColumns) c: r[c]?.toString(),
      'last_unsent': r['last_unsent'] == true ? 1 : 0,
      'unread_count': (r['unread_count'] as num?)?.toInt() ?? 0,
      'archived': archived,
    };
  }

  // Fetches a profile by user ID.
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

  // Saves or updates user profile details.
  Future<void> saveProfile(String id, Map<String, dynamic> row) async {
    final db = await _database;
    await db.insert('profiles', <String, Object?>{
      'id': id,
      for (final c in _userColumns) c: row[c]?.toString(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // Retrieves saved local accounts ordered by last login time.
  Future<List<Map<String, dynamic>>> savedAccounts() async {
    final db = await _database;
    final rows = await db.query('saved_accounts', orderBy: 'last_login DESC');
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  // Saves account info and sets current timestamp as last login.
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

  // Updates last login timestamp for an existing saved account.
  Future<void> touchAccount(String id) async {
    final db = await _database;
    await db.update(
      'saved_accounts',
      {'last_login': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Removes a saved account record by ID.
  Future<void> removeAccount(String id) async {
    final db = await _database;
    await db.delete('saved_accounts', where: 'id = ?', whereArgs: [id]);
  }

  // Fetches recent search entries up to the configured limit.
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

  // Adds or updates user entry in search history with current timestamp and safe ID handling.
  Future<void> addSearch(String owner, Map<String, dynamic> user) async {
    final db = await _database;
    final userId = user['id']?.toString();
    if (userId == null) return;

    await db.insert('search_history', <String, Object?>{
      'owner': owner,
      'id': userId,
      for (final c in _userColumns) c: user[c]?.toString(),
      'searched_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // Deletes a single user record from search history.
  Future<void> removeSearch(String owner, String id) async {
    final db = await _database;
    await db.delete(
      'search_history',
      where: 'owner = ? AND id = ?',
      whereArgs: [owner, id],
    );
  }

  // Clears all search history entries for an owner.
  Future<void> clearSearches(String owner) async {
    final db = await _database;
    await db.delete('search_history', where: 'owner = ?', whereArgs: [owner]);
  }

  // Deletes all user-specific data upon sign out or account wipe.
  Future<void> wipe(String owner) async {
    final db = await _database;
    final batch = db.batch();
    for (final table in [
      'messages',
      'chat_previews',
      'search_history',
      'sync_marks',
    ]) {
      batch.delete(table, where: 'owner = ?', whereArgs: [owner]);
    }
    batch.delete('profiles', where: 'id = ?', whereArgs: [owner]);
    await batch.commit(noResult: true);
  }
}

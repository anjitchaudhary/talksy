import 'dart:async';

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GoogleIdentity {
  final String email;
  final String idToken;

  const GoogleIdentity({required this.email, required this.idToken});
}

class GatewayException implements Exception {
  final int? status;
  final String code;

  const GatewayException(this.code, {this.status});

  @override
  String toString() => 'GatewayException($code, $status)';
}

class ApiGateway {
  ApiGateway._();

  static final ApiGateway instance = ApiGateway._();

  static const Duration _timeout = Duration(seconds: 20);
  static const int _searchLimit = 20;

  final ValueNotifier<int> archiveRevision = ValueNotifier<int>(0);

  SupabaseClient get _db => Supabase.instance.client;

  User? get currentUser => _db.auth.currentUser;

  Stream<AuthState> get authChanges => _db.auth.onAuthStateChange;

  Future<dynamic> rpc(String name, {Map<String, dynamic>? params}) {
    return _db.rpc(name, params: params).timeout(_timeout);
  }

  RealtimeChannel channel(String name, {RealtimeChannelConfig? opts}) {
    return _db.channel(name, opts: opts ?? const RealtimeChannelConfig());
  }

  Future<void> removeChannel(RealtimeChannel channel) async {
    await _db.removeChannel(channel);
  }

  Future<bool> isEmailRegistered(String email) async {
    final res = await rpc(
      'is_email_registered',
      params: {'p_email': email.trim().toLowerCase()},
    );
    return res == true;
  }

  Future<bool> emailExists(String email) async {
    final res = await rpc(
      'check_email_exists',
      params: {'email_input': email.trim().toLowerCase()},
    );
    return res == true;
  }

  Future<bool> verifyCode(String email, String code) async {
    final res = await rpc(
      'verify_code_for_email',
      params: {'p_email': email.trim().toLowerCase(), 'p_code': code},
    );
    return res == true;
  }

  Future<GoogleIdentity?> pickGoogleAccount() async {
    try {
      await GoogleSignIn.instance.signOut();
      final account = await GoogleSignIn.instance.authenticate();
      final token = account.authentication.idToken;
      if (token == null || token.isEmpty) {
        throw const GatewayException('google_token_missing');
      }
      return GoogleIdentity(email: account.email, idToken: token);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled ||
          e.code == GoogleSignInExceptionCode.interrupted) {
        return null;
      }
      throw GatewayException('google_failed:${e.code.name}');
    }
  }

  Future<void> releaseGoogleAccount() async {
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
  }

  Future<void> createAccount({
    required String idToken,
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required DateTime dob,
    required String gender,
  }) async {
    try {
      await _db.functions
          .invoke(
            'google-signup',
            body: {
              'id_token': idToken,
              'email': email.trim().toLowerCase(),
              'password': password,
              'first_name': firstName.trim(),
              'last_name': lastName.trim(),
              'dob': dob.toIso8601String().substring(0, 10),
              'gender': gender,
            },
          )
          .timeout(_timeout);
    } on FunctionException catch (e) {
      final details = e.details;
      final code = details is Map ? details['error'] as String? : null;
      throw GatewayException(code ?? 'signup_failed', status: e.status);
    }
  }

  Future<User> signIn(String email, String password) async {
    final res = await _db.auth
        .signInWithPassword(
          email: email.trim().toLowerCase(),
          password: password,
        )
        .timeout(_timeout);
    final user = res.user;
    if (user == null) throw const GatewayException('signin_failed');
    return user;
  }

  Future<User> signInWithGoogle(String idToken) async {
    final res = await _db.auth
        .signInWithIdToken(provider: OAuthProvider.google, idToken: idToken)
        .timeout(_timeout);
    final user = res.user;
    if (user == null) throw const GatewayException('signin_failed');
    return user;
  }

  Future<void> linkGoogle(String idToken) async {
    await signInWithGoogle(idToken);
  }

  Future<void> signOutLocal() async {
    await _db.auth.signOut(scope: SignOutScope.local);
  }

  Future<String?> uploadImage(String dataUri) async {
    final res = await _db.functions
        .invoke('bright-function', body: {'image_base64': dataUri})
        .timeout(const Duration(seconds: 60));
    final data = res.data;
    return data is Map ? data['url'] as String? : null;
  }

  Future<void> saveAvatar(String url) async {
    final user = currentUser;
    if (user == null) throw const GatewayException('not_signed_in');

    await _db.auth
        .updateUser(
          UserAttributes(data: {'profile_image': url, 'avatar_url': url}),
        )
        .timeout(_timeout);
    await _db
        .from('profiles')
        .update({
          'avatar_url': url,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', user.id)
        .timeout(_timeout);
  }

  Future<void> signOut() async {
    await _db.auth.signOut();
  }

  Stream<List<Map<String, dynamic>>> streamMessages(String me, String other) {
    return _db
        .from('messages')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: true)
        .map(
          (rows) => rows.where((m) {
            final s = m['sender_id'];
            final r = m['receiver_id'];
            return (s == me && r == other) || (s == other && r == me);
          }).toList(),
        );
  }

  Future<List<Map<String, dynamic>>> fetchMessages(
    String me,
    String other,
  ) async {
    final res = await _db
        .from('messages')
        .select()
        .or(
          'and(sender_id.eq.$me,receiver_id.eq.$other),'
          'and(sender_id.eq.$other,receiver_id.eq.$me)',
        )
        .order('created_at', ascending: true)
        .timeout(_timeout);
    return List<Map<String, dynamic>>.from(res);
  }

  Future<Map<String, dynamic>> sendMessage({
    required String senderId,
    required String receiverId,
    required String message,
    required String status,
    String? replyTo,
  }) async {
    try {
      return await _db
          .from('messages')
          .insert({
            'sender_id': senderId,
            'receiver_id': receiverId,
            'message': message,
            'status': status,
            ...?replyTo == null ? null : {'reply_to': replyTo},
          })
          .select()
          .single()
          .timeout(_timeout);
    } on PostgrestException catch (e) {
      throw GatewayException('send_rejected:${e.code}');
    }
  }

  Future<void> markSeen(String senderId) async {
    await rpc('mark_seen', params: {'p_sender': senderId});
  }

  Future<bool> editMessage(String id, String message) async {
    final res = await rpc(
      'edit_message',
      params: {'p_id': id, 'p_message': message},
    );
    return res == true;
  }

  Future<bool> unsendMessage(String id) async {
    final res = await rpc('unsend_message', params: {'p_id': id});
    return res == true;
  }

  Future<bool> reactMessage(String id, String? emoji) async {
    final res = await rpc(
      'react_message',
      params: {'p_id': id, 'p_emoji': emoji},
    );
    return res == true;
  }

  Future<List<Map<String, dynamic>>> fetchChatPreviews({
    bool archived = false,
  }) async {
    final res = await rpc('get_chat_previews', params: {'p_archived': archived});
    return List<Map<String, dynamic>>.from(res as List);
  }

  Future<void> deleteChat(String partnerId) async {
    await rpc('delete_chat', params: {'p_partner': partnerId});
  }

  Future<void> archiveChat(String partnerId) async {
    await rpc('archive_chat', params: {'p_partner': partnerId});
    archiveRevision.value++;
  }

  Future<void> unarchiveChat(String partnerId) async {
    await rpc('unarchive_chat', params: {'p_partner': partnerId});
    archiveRevision.value++;
  }

  String avatarUrl(Object? raw) {
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

  Future<List<Map<String, dynamic>>> searchProfiles(String query) async {
    final term = query.trim();
    if (currentUser == null || term.isEmpty) return [];

    final rows = await rpc(
      'search_profiles',
      params: {'p_query': term, 'p_limit': _searchLimit},
    );
    return List<Map<String, dynamic>>.from(rows as List);
  }

  Future<Map<String, dynamic>?> fetchProfile(String userId) async {
    final row = await _db
        .from('profiles')
        .select('id, first_name, last_name, display_name, email, avatar_url')
        .eq('id', userId)
        .maybeSingle()
        .timeout(_timeout);
    return row;
  }

  Stream<List<Map<String, dynamic>>> streamProfile(String userId) {
    return _db.from('profiles').stream(primaryKey: ['id']).eq('id', userId);
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter/services.dart' show PlatformException;
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

  String get message => code;

  @override
  String toString() => 'GatewayException($code, $status)';
}

class ApiGateway {
  ApiGateway._();

  static final ApiGateway instance = ApiGateway._();

  static const Duration _timeout = Duration(seconds: 20);
  static const Duration _uploadTimeout = Duration(seconds: 60);
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

  // --- Auth & Account Lifecycle ---

  Future<bool> _guardedCheck(
    String function,
    Map<String, dynamic> body,
    String resultKey,
  ) async {
    try {
      final res = await _db.functions
          .invoke(function, body: body)
          .timeout(_timeout);
      final data = res.data;
      if (data is Map) {
        if (data['error'] != null) {
          throw GatewayException(data['error'].toString());
        }
        if (data[resultKey] is bool) {
          return data[resultKey] as bool;
        }
      }
      throw const GatewayException('request_failed');
    } on FunctionException catch (e) {
      final details = e.details;
      final code = details is Map
          ? (details['error'] ?? details['message']) as String?
          : null;
      throw GatewayException(code ?? 'request_failed', status: e.status);
    } on TimeoutException {
      throw const GatewayException('request_timeout', status: 408);
    } catch (e) {
      if (e is GatewayException) rethrow;
      throw GatewayException('network_error:$e');
    }
  }

  Future<bool> isEmailRegistered(String email) {
    final cleaned = email.trim().toLowerCase();
    if (cleaned.isEmpty) return Future.value(false);
    return _guardedCheck('check-email', {
      'email': cleaned,
      'mode': 'registered',
    }, 'exists');
  }

  Future<bool> emailExists(String email) {
    final cleaned = email.trim().toLowerCase();
    if (cleaned.isEmpty) return Future.value(false);
    return _guardedCheck('check-email', {
      'email': cleaned,
      'mode': 'exists',
    }, 'exists');
  }

  Future<bool> verifyCode(String email, String code) {
    final cleanedEmail = email.trim().toLowerCase();
    final cleanedCode = code.trim();
    if (cleanedEmail.isEmpty || cleanedCode.isEmpty) {
      return Future.value(false);
    }
    return _guardedCheck('verify-code', {
      'email': cleanedEmail,
      'code': cleanedCode,
    }, 'valid');
  }

  Future<void> verifyCaptcha(String token, {String email = ''}) async {
    final cleanedToken = token.trim();
    if (cleanedToken.isEmpty) {
      throw const GatewayException('captcha_token_missing');
    }
    final valid = await _guardedCheck('verify-captcha', {
      'captcha_token': cleanedToken,
      'email': email.trim().toLowerCase(),
    }, 'valid');
    if (!valid) throw const GatewayException('captcha_failed');
  }

  Future<GoogleIdentity?> pickGoogleAccount() async {
    try {
      await GoogleSignIn.instance.signOut();
      final account = await GoogleSignIn.instance.authenticate();
      // Null-safety check: यदि user ले sign-in cancel गर्‍यो भने null फर्काउँछ

      // Asynchronous authentication token प्राप्ति (await सहित)
      final auth = account.authentication;
      final token = auth.idToken;
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
    } on PlatformException catch (e) {
      // Android / iOS platform cancellation handling
      if (e.code == 'sign_in_canceled' ||
          e.code == 'canceled' ||
          e.code == '12501') {
        return null;
      }
      throw GatewayException('google_failed:${e.code}');
    } catch (e) {
      if (e is GatewayException) rethrow;
      throw GatewayException('google_failed:$e');
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
    required String captchaToken,
  }) async {
    final dobStr =
        '${dob.year.toString().padLeft(4, '0')}-${dob.month.toString().padLeft(2, '0')}-${dob.day.toString().padLeft(2, '0')}';

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
              'dob': dobStr,
              'gender': gender,
              'captcha_token': captchaToken,
            },
          )
          .timeout(_timeout);
    } on FunctionException catch (e) {
      final details = e.details;
      final code = details is Map
          ? (details['error'] ?? details['message']) as String?
          : null;
      throw GatewayException(code ?? 'signup_failed', status: e.status);
    } on TimeoutException {
      throw const GatewayException('signup_timeout', status: 408);
    } catch (e) {
      if (e is GatewayException) rethrow;
      throw GatewayException('signup_failed:$e');
    }
  }

  Future<User> signIn(String email, String password) async {
    try {
      final res = await _db.auth
          .signInWithPassword(
            email: email.trim().toLowerCase(),
            password: password,
          )
          .timeout(_timeout);
      final user = res.user;
      if (user == null) throw const GatewayException('signin_failed');
      return user;
    } on AuthException catch (e) {
      throw GatewayException(
        e.message.isNotEmpty ? e.message : 'signin_failed',
        status: int.tryParse(e.statusCode ?? ''),
      );
    } on TimeoutException {
      throw const GatewayException('signin_timeout', status: 408);
    } catch (e) {
      if (e is GatewayException) rethrow;
      throw GatewayException('signin_failed:$e');
    }
  }

  Future<User> signInWithGoogle(String idToken) async {
    try {
      final res = await _db.auth
          .signInWithIdToken(provider: OAuthProvider.google, idToken: idToken)
          .timeout(_timeout);
      final user = res.user;
      if (user == null) throw const GatewayException('signin_failed');
      return user;
    } on AuthException catch (e) {
      throw GatewayException(
        e.message.isNotEmpty ? e.message : 'signin_failed',
        status: int.tryParse(e.statusCode ?? ''),
      );
    } on TimeoutException {
      throw const GatewayException('signin_timeout', status: 408);
    } catch (e) {
      if (e is GatewayException) rethrow;
      throw GatewayException('signin_failed:$e');
    }
  }

  Future<void> linkGoogle(String idToken) async {
    await signInWithGoogle(idToken);
  }

  Future<void> signOutLocal() async {
    try {
      await _db.auth.signOut(scope: SignOutScope.local);
    } catch (_) {}
  }

  Future<void> signOut() async {
    try {
      await Future.wait([
        _db.auth.signOut(),
        releaseGoogleAccount(),
      ]).timeout(_timeout);
    } catch (_) {
      await signOutLocal();
    }
  }

  // --- Profile & Media ---

  Future<String?> uploadImage(String dataUri) async {
    if (dataUri.trim().isEmpty) return null;
    try {
      final res = await _db.functions
          .invoke('bright-function', body: {'image_base64': dataUri})
          .timeout(_uploadTimeout);
      final data = res.data;
      if (data is Map) {
        if (data['error'] != null) {
          throw GatewayException(data['error'].toString());
        }
        final url = data['url'] as String?;
        if (url != null && url.isNotEmpty) return url;
      }
      return null;
    } on FunctionException catch (e) {
      final details = e.details;
      final code = details is Map
          ? (details['error'] ?? details['message']) as String?
          : null;
      throw GatewayException(code ?? 'upload_failed', status: e.status);
    } on TimeoutException {
      throw const GatewayException('upload_timeout', status: 408);
    } catch (e) {
      if (e is GatewayException) rethrow;
      throw GatewayException('upload_failed:$e');
    }
  }

  Future<void> saveAvatar(String url) async {
    final user = currentUser;
    if (user == null) throw const GatewayException('not_signed_in');

    final cleanUrl = url.trim();
    if (cleanUrl.isEmpty) {
      throw const GatewayException('invalid_avatar_url');
    }

    try {
      // 1. Database table लाई पहिलो priority मा update गर्ने
      await _db
          .from('profiles')
          .update({
            'avatar_url': cleanUrl,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', user.id)
          .timeout(_timeout);

      // 2. Auth user metadata लाई secondary रूपमा sync गर्ने
      try {
        await _db.auth
            .updateUser(
              UserAttributes(
                data: {'profile_image': cleanUrl, 'avatar_url': cleanUrl},
              ),
            )
            .timeout(_timeout);
      } catch (_) {
        // Database update भइसकेकोले metadata sync failure ले operation रोक्दैन
      }
    } on PostgrestException catch (e) {
      throw GatewayException('avatar_update_failed:${e.code}');
    } on TimeoutException {
      throw const GatewayException('avatar_update_timeout', status: 408);
    } catch (e) {
      if (e is GatewayException) rethrow;
      throw GatewayException('avatar_update_failed:$e');
    }
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

    try {
      final rows = await rpc(
        'search_profiles',
        params: {'p_query': term, 'p_limit': _searchLimit},
      );
      if (rows is! List) return [];
      return rows.map((r) => Map<String, dynamic>.from(r as Map)).toList();
    } on PostgrestException catch (e) {
      if (e.code == 'PT429' || e.code == '429') {
        throw const GatewayException('rate_limited', status: 429);
      }
      throw GatewayException('search_failed:${e.code}');
    } on TimeoutException {
      throw const GatewayException('request_timeout', status: 408);
    } catch (e) {
      if (e is GatewayException) rethrow;
      throw GatewayException('search_failed:$e');
    }
  }

  Future<Map<String, dynamic>?> fetchProfile(String userId) async {
    final cleanId = userId.trim();
    if (cleanId.isEmpty) return null;

    try {
      final row = await _db
          .from('profiles')
          .select('id, first_name, last_name, display_name, email, avatar_url')
          .eq('id', cleanId)
          .maybeSingle()
          .timeout(_timeout);
      return row;
    } on PostgrestException catch (e) {
      throw GatewayException('profile_fetch_failed:${e.code}');
    } on TimeoutException {
      throw const GatewayException('request_timeout', status: 408);
    } catch (e) {
      if (e is GatewayException) rethrow;
      throw GatewayException('profile_fetch_failed:$e');
    }
  }

  Stream<List<Map<String, dynamic>>> streamProfile(String userId) {
    final cleanId = userId.trim();
    if (cleanId.isEmpty) return const Stream.empty();
    return _db.from('profiles').stream(primaryKey: ['id']).eq('id', cleanId);
  }

  // --- Messages & Chat ---

  Stream<List<Map<String, dynamic>>> streamMessages(String me, String other) {
    final myId = me.trim();
    final otherId = other.trim();
    if (myId.isEmpty || otherId.isEmpty) return const Stream.empty();

    return _db
        .from('messages')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: true)
        .map(
          (rows) => rows.where((m) {
            final s = m['sender_id'];
            final r = m['receiver_id'];
            return (s == myId && r == otherId) || (s == otherId && r == myId);
          }).toList(),
        );
  }

  Future<List<Map<String, dynamic>>> fetchMessages(
    String me,
    String other,
  ) async {
    final myId = me.trim();
    final otherId = other.trim();
    if (myId.isEmpty || otherId.isEmpty) return [];

    try {
      final res = await _db
          .from('messages')
          .select()
          .or(
            'and(sender_id.eq.$myId,receiver_id.eq.$otherId),'
            'and(sender_id.eq.$otherId,receiver_id.eq.$myId)',
          )
          .order('created_at', ascending: true)
          .timeout(_timeout);
      return res.map((m) => Map<String, dynamic>.from(m as Map)).toList();
    } on PostgrestException catch (e) {
      throw GatewayException('fetch_messages_failed:${e.code}');
    } on TimeoutException {
      throw const GatewayException('request_timeout', status: 408);
    } catch (e) {
      if (e is GatewayException) rethrow;
      throw GatewayException('fetch_messages_failed:$e');
    }
  }

  Future<Map<String, dynamic>> sendMessage({
    required String senderId,
    required String receiverId,
    required String message,
    required String status,
    String? replyTo,
  }) async {
    final cleanSender = senderId.trim();
    final cleanReceiver = receiverId.trim();
    final cleanMessage = message.trim();
    final cleanReply = replyTo?.trim();

    if (cleanSender.isEmpty || cleanReceiver.isEmpty) {
      throw const GatewayException('invalid_recipient');
    }
    if (cleanMessage.isEmpty) {
      throw const GatewayException('empty_message');
    }

    try {
      return await _db
          .from('messages')
          .insert({
            'sender_id': cleanSender,
            'receiver_id': cleanReceiver,
            'message': cleanMessage,
            'status': status,
            if (cleanReply != null && cleanReply.isNotEmpty)
              'reply_to': cleanReply,
          })
          .select()
          .single()
          .timeout(_timeout);
    } on PostgrestException catch (e) {
      throw GatewayException('send_rejected:${e.code}');
    } on TimeoutException {
      throw const GatewayException('send_timeout', status: 408);
    } catch (e) {
      if (e is GatewayException) rethrow;
      throw GatewayException('send_failed:$e');
    }
  }

  Future<void> markSeen(String senderId) async {
    final cleanId = senderId.trim();
    if (cleanId.isEmpty) return;
    try {
      await rpc('mark_seen', params: {'p_sender': cleanId});
    } on PostgrestException catch (e) {
      throw GatewayException('mark_seen_failed:${e.code}');
    } on TimeoutException {
      throw const GatewayException('request_timeout', status: 408);
    } catch (e) {
      if (e is GatewayException) rethrow;
      throw GatewayException('mark_seen_failed:$e');
    }
  }

  Future<bool> editMessage(String id, String message) async {
    final cleanId = id.trim();
    if (cleanId.isEmpty) return false;
    try {
      final res = await rpc(
        'edit_message',
        params: {'p_id': cleanId, 'p_message': message},
      );
      return res == true;
    } on PostgrestException catch (e) {
      throw GatewayException('edit_failed:${e.code}');
    } on TimeoutException {
      throw const GatewayException('request_timeout', status: 408);
    } catch (e) {
      if (e is GatewayException) rethrow;
      throw GatewayException('edit_failed:$e');
    }
  }

  Future<bool> unsendMessage(String id) async {
    final cleanId = id.trim();
    if (cleanId.isEmpty) return false;
    try {
      final res = await rpc('unsend_message', params: {'p_id': cleanId});
      return res == true;
    } on PostgrestException catch (e) {
      throw GatewayException('unsend_failed:${e.code}');
    } on TimeoutException {
      throw const GatewayException('request_timeout', status: 408);
    } catch (e) {
      if (e is GatewayException) rethrow;
      throw GatewayException('unsend_failed:$e');
    }
  }

  Future<bool> reactMessage(String id, String? emoji) async {
    final cleanId = id.trim();
    if (cleanId.isEmpty) return false;
    try {
      final res = await rpc(
        'react_message',
        params: {'p_id': cleanId, 'p_emoji': emoji},
      );
      return res == true;
    } on PostgrestException catch (e) {
      throw GatewayException('react_failed:${e.code}');
    } on TimeoutException {
      throw const GatewayException('request_timeout', status: 408);
    } catch (e) {
      if (e is GatewayException) rethrow;
      throw GatewayException('react_failed:$e');
    }
  }

  Future<List<Map<String, dynamic>>> fetchChatPreviews({
    bool archived = false,
  }) async {
    try {
      final res = await rpc(
        'get_chat_previews',
        params: {'p_archived': archived},
      );
      if (res is! List) return [];
      return res.map((r) => Map<String, dynamic>.from(r as Map)).toList();
    } on PostgrestException catch (e) {
      throw GatewayException('fetch_previews_failed:${e.code}');
    } on TimeoutException {
      throw const GatewayException('request_timeout', status: 408);
    } catch (e) {
      if (e is GatewayException) rethrow;
      throw GatewayException('fetch_previews_failed:$e');
    }
  }

  Future<void> deleteChat(String partnerId) async {
    final cleanId = partnerId.trim();
    if (cleanId.isEmpty) return;
    try {
      await rpc('delete_chat', params: {'p_partner': cleanId});
      archiveRevision.value++;
    } on PostgrestException catch (e) {
      throw GatewayException('delete_chat_failed:${e.code}');
    } on TimeoutException {
      throw const GatewayException('request_timeout', status: 408);
    } catch (e) {
      if (e is GatewayException) rethrow;
      throw GatewayException('delete_chat_failed:$e');
    }
  }

  Future<void> archiveChat(String partnerId) async {
    final cleanId = partnerId.trim();
    if (cleanId.isEmpty) return;
    try {
      await rpc('archive_chat', params: {'p_partner': cleanId});
      archiveRevision.value++;
    } on PostgrestException catch (e) {
      throw GatewayException('archive_chat_failed:${e.code}');
    } on TimeoutException {
      throw const GatewayException('request_timeout', status: 408);
    } catch (e) {
      if (e is GatewayException) rethrow;
      throw GatewayException('archive_chat_failed:$e');
    }
  }

  Future<void> unarchiveChat(String partnerId) async {
    final cleanId = partnerId.trim();
    if (cleanId.isEmpty) return;
    try {
      await rpc('unarchive_chat', params: {'p_partner': cleanId});
      archiveRevision.value++;
    } on PostgrestException catch (e) {
      throw GatewayException('unarchive_chat_failed:${e.code}');
    } on TimeoutException {
      throw const GatewayException('request_timeout', status: 408);
    } catch (e) {
      if (e is GatewayException) rethrow;
      throw GatewayException('unarchive_chat_failed:$e');
    }
  }
}

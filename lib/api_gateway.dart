import 'dart:async';

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
      await _db.functions.invoke(
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
      ).timeout(_timeout);
    } on FunctionException catch (e) {
      final details = e.details;
      final code = details is Map ? details['error'] as String? : null;
      throw GatewayException(code ?? 'signup_failed', status: e.status);
    }
  }

  Future<User> signIn(String email, String password) async {
    final res = await _db.auth
        .signInWithPassword(email: email.trim().toLowerCase(), password: password)
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
        .updateUser(UserAttributes(data: {'profile_image': url, 'avatar_url': url}))
        .timeout(_timeout);
    await _db
        .from('profiles')
        .update({'avatar_url': url, 'updated_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', user.id)
        .timeout(_timeout);
  }

  Future<void> signOut() async {
    await _db.auth.signOut();
  }
}

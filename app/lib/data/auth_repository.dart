import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_error.dart';
import '../core/env.dart';
import 'supabase.dart';

/// 로그인·가입·탈퇴. 토큰은 supabase_flutter 가 보안 저장소에 넣고 자동 갱신한다.
class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  GoTrueClient get _auth => _client.auth;

  Session? get session => _auth.currentSession;
  User? get user => _auth.currentUser;

  /// 이메일 가입. 인증 메일을 보내고, 확인 전까지는 세션이 없다.
  Future<void> signUpWithEmail({required String email, required String password}) async {
    try {
      await _auth.signUp(
        email: email.trim(),
        password: password,
        emailRedirectTo: '${Env.appScheme}://login-callback',
      );
    } catch (e, st) {
      throw mapSupabaseError(e, st);
    }
  }

  Future<void> signInWithEmail({required String email, required String password}) async {
    try {
      await _auth.signInWithPassword(email: email.trim(), password: password);
    } catch (e, st) {
      throw mapSupabaseError(e, st);
    }
  }

  /// 휴대폰 인증번호 발송. 재전송도 같은 함수를 쓴다(쿨다운은 화면이 센다).
  Future<void> sendPhoneOtp(String phone) async {
    try {
      await _auth.signInWithOtp(phone: _normalizePhone(phone));
    } catch (e, st) {
      throw mapSupabaseError(e, st);
    }
  }

  Future<void> verifyPhoneOtp({required String phone, required String token}) async {
    try {
      await _auth.verifyOTP(
        phone: _normalizePhone(phone),
        token: token,
        type: OtpType.sms,
      );
    } catch (e, st) {
      throw mapSupabaseError(e, st);
    }
  }

  /// Apple 로그인. iOS 심사에서 다른 소셜 로그인이 있으면 사실상 필수다.
  Future<void> signInWithApple() async {
    try {
      final raw = _nonce();
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName],
        nonce: _sha256(raw),
      );
      final idToken = credential.identityToken;
      if (idToken == null) {
        throw AppError.of(AppErrorKind.unknown, message: 'Apple 로그인에서 토큰을 받지 못했어요.');
      }
      await _auth.signInWithIdToken(
        provider: OAuthProvider.apple,
        idToken: idToken,
        nonce: raw,
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      // 사용자가 창을 닫은 것은 오류가 아니다. 오류 화면을 띄우면 안 된다.
      if (e.code == AuthorizationErrorCode.canceled) {
        throw AppError.of(AppErrorKind.cancelled, cause: e);
      }
      throw mapSupabaseError(e);
    } catch (e, st) {
      throw mapSupabaseError(e, st);
    }
  }

  Future<void> signInWithGoogle({required String? iosClientId, required String? serverClientId}) async {
    try {
      final google = GoogleSignIn(clientId: iosClientId, serverClientId: serverClientId);
      final account = await google.signIn();
      if (account == null) throw AppError.of(AppErrorKind.cancelled);
      final auth = await account.authentication;
      final idToken = auth.idToken;
      if (idToken == null) {
        throw AppError.of(AppErrorKind.unknown, message: 'Google 로그인에서 토큰을 받지 못했어요.');
      }
      await _auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: auth.accessToken,
      );
    } catch (e, st) {
      throw mapSupabaseError(e, st);
    }
  }

  /// 이메일 인증 메일 재전송. 가입은 됐는데 메일을 못 받은 사람이 막히는 자리다.
  Future<void> resendEmailVerification(String email) async {
    try {
      await _auth.resend(
        type: OtpType.signup,
        email: email.trim(),
        emailRedirectTo: '${Env.appScheme}://login-callback',
      );
    } catch (e, st) {
      throw mapSupabaseError(e, st);
    }
  }

  /// 비밀번호 재설정 메일. 메일 존재 여부를 응답으로 알려주지 않는다(계정 존재 노출 방지).
  Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.resetPasswordForEmail(
        email.trim(),
        redirectTo: '${Env.appScheme}://reset-password',
      );
    } catch (e, st) {
      throw mapSupabaseError(e, st);
    }
  }

  Future<void> updatePassword(String newPassword) async {
    try {
      await _auth.updateUser(UserAttributes(password: newPassword));
    } catch (e, st) {
      throw mapSupabaseError(e, st);
    }
  }

  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (e, st) {
      throw mapSupabaseError(e, st);
    }
  }

  /// 회원탈퇴. 계정 삭제는 서비스 롤이 필요해서 Edge Function 이 한다.
  /// 앱이 직접 지울 수 있으면 남의 계정도 지울 수 있다는 뜻이다.
  Future<void> deleteAccount({required String reason, String? detail}) async {
    try {
      await _client.functions.invoke('delete-account', body: {
        'reason': reason,
        if (detail != null && detail.isNotEmpty) 'detail': detail,
      }).withTimeout(kTransferTimeout);
      await _auth.signOut();
    } catch (e, st) {
      throw mapSupabaseError(e, st);
    }
  }

  /// 한국 번호를 E.164 로. `010-1234-5678` → `+821012345678`
  static String _normalizePhone(String input) {
    final digits = input.replaceAll(RegExp(r'[^0-9+]'), '');
    if (digits.startsWith('+')) return digits;
    if (digits.startsWith('0')) return '+82${digits.substring(1)}';
    return '+$digits';
  }

  /// Apple 로그인 리플레이 공격을 막는 값이라 반드시 암호학적 난수여야 한다.
  /// 시각 기반으로 만들면 예측 가능해져서 nonce 를 두는 의미가 사라진다.
  static String _nonce([int length = 32]) {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._';
    final rnd = Random.secure();
    return List.generate(length, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  static String _sha256(String input) => sha256.convert(utf8.encode(input)).toString();
}

final authRepositoryProvider =
    Provider<AuthRepository>((ref) => AuthRepository(ref.watch(supabaseProvider)));

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_error.dart';
import '../core/env.dart';

/// Supabase 초기화. 앱 시작에서 딱 한 번.
Future<void> initSupabase() async {
  if (!Env.isConfigured) return; // 설정이 없으면 앱은 뜨되 점검 화면으로 간다
  await Supabase.initialize(
    url: Env.supabaseUrl,
    // anon(publishable) 키는 공개되어도 되는 값이다 — 실제 방어선은 RLS 다.
    // 그래도 소스에 박지 않고 --dart-define 으로 주입해 환경별로 갈아끼운다.
    publishableKey: Env.supabaseAnonKey,
    authOptions: const FlutterAuthClientOptions(
      // 토큰은 flutter_secure_storage 에 저장된다(SharedPreferences 평문이 아니라).
      localStorage: SecureSessionStorage(),
      autoRefreshToken: true,
    ),
  );
}

/// supabase_flutter 의 기본 저장소는 SharedPreferences 다 — 평문이라 토큰을 두면 안 된다.
///
/// iOS 는 Keychain, Android 는 EncryptedSharedPreferences 를 쓴다.
/// 기기 잠금 해제 뒤에만 읽히게 해서 잠긴 기기에서 백그라운드 접근을 막는다.
class SecureSessionStorage extends LocalStorage {
  const SecureSessionStorage();

  static const _key = 'sb_session';
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );

  @override
  Future<void> initialize() async {}

  @override
  Future<String?> accessToken() => _storage.read(key: _key);

  @override
  Future<bool> hasAccessToken() async => (await _storage.read(key: _key)) != null;

  @override
  Future<void> persistSession(String persistSessionString) =>
      _storage.write(key: _key, value: persistSessionString);

  @override
  Future<void> removePersistedSession() => _storage.delete(key: _key);
}

final supabaseProvider = Provider<SupabaseClient>((ref) => Supabase.instance.client);

final authStateProvider = StreamProvider<AuthState?>((ref) {
  if (!Env.isConfigured) return const Stream.empty();
  return ref.watch(supabaseProvider).auth.onAuthStateChange;
});

/// 현재 사용자. 세션이 만료되면 null 이 되고 라우터가 로그인으로 보낸다.
final currentUserProvider = Provider<User?>((ref) {
  ref.watch(authStateProvider);
  if (!Env.isConfigured) return null;
  return ref.watch(supabaseProvider).auth.currentUser;
});

/// Supabase 예외를 앱의 실패 분류로 옮긴다.
///
/// 여기서 안 옮기면 화면마다 PostgrestException 을 알아야 하고,
/// 결국 서버 원문 메시지가 사용자에게 그대로 나간다.
AppError mapSupabaseError(Object e, [StackTrace? st]) {
  if (e is AppError) return e;

  if (e is AuthApiException) {
    final code = e.code ?? '';
    if (code.contains('invalid_credentials') || e.statusCode == '400') {
      return AppError.of(AppErrorKind.validation,
          cause: e, code: code, message: '이메일이나 비밀번호가 맞지 않아요.');
    }
    if (e.statusCode == '401' || e.statusCode == '403') {
      return AppError.of(AppErrorKind.unauthorized, cause: e, code: code);
    }
    if (code.contains('over_email_send_rate_limit') || e.statusCode == '429') {
      return AppError.of(AppErrorKind.rateLimited,
          cause: e, code: code, message: '인증 메일을 너무 자주 보냈어요. 잠시 뒤에 다시 시도해 주세요.');
    }
    if (code.contains('user_already_exists') || code.contains('email_exists')) {
      return AppError.of(AppErrorKind.validation,
          cause: e, code: code, message: '이미 가입된 이메일이에요. 로그인해 주세요.');
    }
    if (code.contains('otp_expired')) {
      return AppError.of(AppErrorKind.validation,
          cause: e, code: code, message: '인증번호가 만료됐어요. 다시 받아 주세요.');
    }
    return AppError.of(AppErrorKind.unknown, cause: e, code: code);
  }

  if (e is AuthException) {
    return AppError.of(AppErrorKind.unauthorized, cause: e);
  }

  if (e is PostgrestException) {
    final status = int.tryParse(e.code ?? '') ?? 0;
    // RLS 가 막으면 42501 로 온다 — 남의 데이터에 손댄 것이므로 재시도 대상이 아니다.
    if (e.code == '42501') return AppError.of(AppErrorKind.forbidden, cause: e);
    if (e.code == 'PGRST116') return AppError.of(AppErrorKind.notFound, cause: e);
    return AppError.of(AppError.kindOfStatus(status == 0 ? 500 : status), cause: e, code: e.code);
  }

  if (e is FunctionException) {
    final detail = e.details;
    final code = detail is Map ? detail['error'] as String? : null;
    if (code == 'quota_exhausted') {
      return AppError.of(AppErrorKind.quotaExhausted, cause: e, code: code);
    }
    if (code == 'generation_in_progress') {
      return AppError.of(AppErrorKind.rateLimited,
          cause: e, code: code, message: '학습지를 만드는 중이에요. 하나가 끝나면 다음을 만들 수 있어요.');
    }
    // 하루 상한. 기본 문구("요청이 너무 빨라요")는 여기서 거짓말이 된다 —
    // 사용자는 빠르게 누른 것이 아니라 오늘 몫을 다 쓴 것이고, 기다릴 시간이 다르다.
    if (code == 'daily_limit_reached') {
      return AppError.of(AppErrorKind.rateLimited,
          cause: e, code: code,
          message: '오늘 만들 수 있는 학습지를 다 만드셨어요. 내일 다시 시도해 주세요.');
    }
    // 영수증 검증 실패. "입력을 다시 확인해 주세요" 로 뜨면 사용자는 자기가 뭘 잘못
    // 적었다고 생각한다 — 돈이 오간 자리에서 그 오해는 특히 나쁘다.
    if (code == 'invalid_receipt' || code == 'receipt_invalid') {
      return AppError.of(AppErrorKind.server,
          cause: e, code: code,
          message: '결제 확인이 안 끝났어요. 잠시 뒤에 "구매 복원"을 눌러 주세요. '
              '장수가 안 들어오면 고객센터로 알려 주세요.');
    }
    if (code == 'unknown_product' || code == 'invalid_product') {
      return AppError.of(AppErrorKind.server,
          cause: e, code: code,
          message: '지금은 이 상품을 살 수 없어요. 앱을 업데이트하거나 잠시 뒤에 다시 시도해 주세요.');
    }
    // 학습지 파일을 못 지웠다. 다시 눌러도 되는 실패라고 분명히 말해 준다.
    if (code == 'storage_failed' || code == 'delete_failed') {
      return AppError.of(AppErrorKind.server,
          cause: e, code: code,
          message: '학습지를 지우지 못했어요. 잠시 뒤에 다시 시도해 주세요.');
    }
    return AppError.of(AppError.kindOfStatus(e.status), cause: e, code: code);
  }

  if (e is StorageException) {
    return AppError.of(AppError.kindOfStatus(int.tryParse(e.statusCode ?? '') ?? 500), cause: e);
  }

  return AppError.from(e, st);
}

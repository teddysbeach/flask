import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 토큰처럼 새면 계정이 통째로 넘어가는 값만 여기 둔다.
///
/// SharedPreferences 는 평문이라 토큰을 넣으면 안 된다.
/// iOS 는 Keychain, Android 는 EncryptedSharedPreferences 를 쓴다.
/// 기기 잠금 해제 뒤에만 읽히게 해서, 잠긴 기기에서 백그라운드 접근을 막는다.
class SecureStore {
  SecureStore([FlutterSecureStorage? storage])
      : _s = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
            );

  final FlutterSecureStorage _s;

  static const kPushToken = 'push_token';
  static const kPendingDeepLink = 'pending_deep_link';

  Future<String?> read(String key) => _s.read(key: key);
  Future<void> write(String key, String? value) =>
      value == null ? _s.delete(key: key) : _s.write(key: key, value: value);

  /// 로그아웃·탈퇴에서 부른다. 하나라도 남으면 다음 사용자가 이전 사용자의 흔적을 본다.
  Future<void> clearAll() => _s.deleteAll();
}

final secureStoreProvider = Provider<SecureStore>((ref) => SecureStore());

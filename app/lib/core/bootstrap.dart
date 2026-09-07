import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models.dart';
import 'env.dart';
import 'version_gate.dart';

/// 앱을 켰을 때 어디로 보낼지 정하는 데 필요한 것들.
///
/// 순서가 중요하다: 설정 없음 → 점검 → 강제 업데이트 → 첫 실행(온보딩) → 약관 → 로그인.
/// 이 순서를 화면마다 따로 판단하면 반드시 어긋난다.
class LocalFlags {
  LocalFlags(this._prefs);
  final SharedPreferences _prefs;

  static const _kOnboarded = 'onboarded_v1';
  static const _kConsent = 'consent_v1';
  static const _kThemeMode = 'theme_mode';

  bool get onboarded => _prefs.getBool(_kOnboarded) ?? false;
  Future<void> setOnboarded(bool v) => _prefs.setBool(_kOnboarded, v);

  ConsentRecord? get consent {
    final raw = _prefs.getString(_kConsent);
    if (raw == null) return null;
    try {
      return ConsentRecord.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } catch (_) {
      return null;
    }
  }

  /// 동의 이력은 기기와 서버 양쪽에 남긴다. 기기만 두면 재설치로 사라지고,
  /// 서버만 두면 로그인 전 동의를 기록할 데가 없다.
  Future<void> setConsent(ConsentRecord c) =>
      _prefs.setString(_kConsent, jsonEncode(c.toJson()));

  String get themeMode => _prefs.getString(_kThemeMode) ?? 'system';
  Future<void> setThemeMode(String v) => _prefs.setString(_kThemeMode, v);

  Future<void> clearUserScoped() async {
    // 온보딩·약관 동의는 기기 단위라 로그아웃으로 지우지 않는다.
    // 지우면 로그아웃할 때마다 온보딩을 다시 보게 된다.
  }
}

final sharedPrefsProvider = FutureProvider<SharedPreferences>((_) => SharedPreferences.getInstance());

final localFlagsProvider = Provider<LocalFlags>((ref) {
  final prefs = ref.watch(sharedPrefsProvider).requireValue;
  return LocalFlags(prefs);
});

/// 서버가 정하는 관문(점검·강제 업데이트).
///
/// 서버를 못 부르면 **통과**시킨다. 여기서 막으면 우리 실수 하나로 앱이 통째로 안 열린다.
final appGateProvider = FutureProvider<AppGate>((ref) async {
  if (!Env.isConfigured) return AppGate.pass;
  final info = await ref.watch(appInfoProvider.future);
  try {
    // 관문은 로그인 전에도 읽혀야 해서 공개 테이블을 쓴다.
    final client = ref.watch(_gateClientProvider);
    final rows = await client();
    if (rows == null) return AppGate.pass;
    return AppGate.fromJson(rows, info.build);
  } catch (_) {
    return AppGate.pass;
  }
});

/// 실제 호출은 data 계층이 꽂는다. core 가 Supabase 를 직접 알지 않게 둔다.
final _gateClientProvider = Provider<Future<Map<String, Object?>?> Function()>(
  (ref) => () async => null,
);

/// 부팅 판정 결과.
enum BootStage { misconfigured, maintenance, forceUpdate, onboarding, consent, auth, ready }

class BootState {
  const BootState(this.stage, {this.gate});
  final BootStage stage;
  final AppGate? gate;
}

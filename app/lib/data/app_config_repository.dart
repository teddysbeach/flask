import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/logger.dart';
import 'supabase.dart';

/// 관문(점검 · 강제 업데이트) 설정을 서버에서 읽는다.
///
/// 두 가지가 이 파일의 전부다.
///
/// 1. **로그인 없이 읽힌다.** 부팅 첫 화면에서 읽는 값이라 세션이 없을 때가 정상이다.
///    supabase 클라이언트는 세션이 없으면 anon 키로 부르고, `app_config` 의 RLS 가
///    anon 에게 select 를 열어 둔다. 로그인해야 읽을 수 있게 만들면
///    정작 점검 중일 때 "점검 중" 을 못 띄운다.
///
/// 2. **오래 붙잡지 않는다.** 이 호출은 스플래시를 막는다. 서버가 느리면 앱이 안 열린 것과
///    같으므로 몇 초 뒤에는 포기하고 통과시킨다(포기 판단은 [appGateProvider] 가 한다).
class AppConfigRepository {
  AppConfigRepository(this._client, {required this.platform});

  final SupabaseClient _client;

  /// 'ios' | 'android'. 서버 행의 기본키다.
  final String platform;

  /// 부팅을 막아도 되는 시간. 이보다 오래 걸리면 관문 없이 들여보낸다.
  static const timeout = Duration(seconds: 4);

  /// 서버가 정한 관문 한 줄. 행이 없으면 null — 호출자는 이걸 "통과" 로 읽는다.
  ///
  /// 던지는 예외도 통과로 처리된다([appGateProvider] 의 try/catch).
  /// 여기서 막으면 우리 실수 하나로 앱 전체가 안 열린다.
  Future<Map<String, Object?>?> fetch() async {
    final row = await _client
        .from('app_config')
        .select('min_build, latest_build, store_url, maintenance, message, until')
        .eq('platform', platform)
        .maybeSingle()
        .timeout(timeout);
    if (row == null) {
      // 행이 없는 것은 사고가 아니다(플랫폼 행을 아직 안 넣었을 수 있다). 조용히 통과시킨다.
      AppLogger.debug('app_config: $platform 행이 없다 — 관문 통과');
    }
    return row;
  }
}

/// 앱이 도는 스토어. 테스트는 이 프로바이더만 갈아끼우면 된다.
final appPlatformProvider = Provider<String>((ref) => Platform.isIOS ? 'ios' : 'android');

final appConfigRepositoryProvider = Provider<AppConfigRepository>(
  (ref) => AppConfigRepository(
    ref.watch(supabaseProvider),
    platform: ref.watch(appPlatformProvider),
  ),
);

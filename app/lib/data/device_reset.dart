import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/bootstrap.dart';
import '../core/logger.dart';
import '../core/notifications.dart';
import '../features/home/home_prefs.dart';
import '../features/notifications/notification_prefs.dart';
import 'offline_store.dart';

/// 로그아웃·탈퇴 뒤 **이 기기에 남는 그 사람의 흔적**을 지운다.
///
/// 흔적은 세 군데에 있다. 셋 다 지워야 "로그아웃했다" 가 참이 된다.
///   1. 오프라인 학습지 본문과 못 올린 필기 (OfflineStore)
///   2. 운영체제에 예약해 둔 복습 알림 — **이건 앱 밖이라 로그아웃해도 계속 뜬다.**
///      제목에 학습지 이름이 들어 있어서, 다음 사람이 그걸 그대로 본다.
///   3. 앱 안의 받은 알림 목록 (기록에도 학습지 이름이 들어 있다)
///
/// 화면이 아니라 여기 한곳에 둔 이유: 로그아웃 길은 설정 화면과 탈퇴 화면 둘이고,
/// 한 곳만 고치면 다른 한 곳이 조용히 흔적을 남긴다.
///
/// **던지지 않는다.** 정리에 실패했다고 로그아웃을 막으면 사용자는 로그인된 채로 갇힌다.
class DeviceReset {
  DeviceReset({
    required OfflineStore offline,
    required NotificationService notifications,
    required Future<NotificationPrefs> Function() prefs,
    required Future<HomePrefs> Function() home,
  })  : _offline = offline,
        _notifications = notifications,
        _prefs = prefs,
        _home = home;

  final OfflineStore _offline;
  final NotificationService _notifications;
  final Future<NotificationPrefs> Function() _prefs;
  final Future<HomePrefs> Function() _home;

  Future<void> wipe() async {
    await _step('오프라인 학습지', _offline.clearAll);
    await _step('예약된 복습 알림', _notifications.cancelReviewNotifications);
    await _step('받은 알림 기록', () async => (await _prefs()).clear());
    // 홈이 기억하는 것 — 마지막으로 본 학습지, 닫은 공지.
    // 다음 사람의 홈에 앞사람이 보던 학습지가 "이어서 하기" 로 뜨면 안 된다.
    await _step('홈 기록', () async => (await _home()).clear());
  }

  Future<void> _step(String what, Future<void> Function() run) async {
    try {
      await run();
    } catch (e, st) {
      AppLogger.error('$what 을(를) 정리하지 못했어요', error: e, stack: st);
    }
  }
}

final deviceResetProvider = Provider<DeviceReset>((ref) {
  return DeviceReset(
    offline: ref.watch(offlineStoreProvider),
    notifications: ref.watch(notificationServiceProvider),
    // 로그아웃 시점에 읽는다. 앱을 켜자마자 로그아웃하는 사람은 없지만,
    // 프로바이더를 만드는 순간 requireValue 를 부르면 그때 죽는다.
    prefs: () async => NotificationPrefs(await ref.read(sharedPrefsProvider.future)),
    home: () async => HomePrefs(await ref.read(sharedPrefsProvider.future)),
  );
});

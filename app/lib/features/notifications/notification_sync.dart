import '../../core/app_error.dart';
import '../../core/logger.dart';
import '../../core/notifications.dart';
import '../../data/review_repository.dart';
import '../../domain/models.dart';
import 'notification_prefs.dart';

/// 로컬 알림을 서버 스케줄에 다시 맞춘다.
///
/// 앱 포그라운드 진입·복습 응답 후·학습지 생성 완료 후·알림 설정 변경 후에 부른다.
/// 화면이 아니라 여기 한곳에서 순서를 정한다 — 스위치 확인 → 서버 조회 → 재예약 → 기록.
///
/// **실패해도 던지지 않는다.** 알림은 복습의 보조 수단이고, 알림을 못 걸었다고 해서
/// 사용자가 보던 화면이 오류로 바뀌면 안 된다. 큐 자체는 앱을 열면 서버에서 복원된다.
Future<void> syncReviewNotifications({
  required NotificationService service,
  required ReviewRepository reviews,
  required NotificationPrefs prefs,
  required Profile profile,
}) async {
  if (!prefs.reviewNotificationsOn) {
    // 앱 안에서 껐으면 걸려 있던 것도 걷어낸다. 안 그러면 끈 뒤에도 며칠 동안 알림이 온다.
    await service.cancelReviewNotifications();
    return;
  }

  try {
    final upcoming = await reviews.upcoming();
    await service.syncFromServer(
      upcoming,
      reviewHour: profile.reviewHour,
      timeZone: profile.timezone,
    );
    await prefs.rememberPlanned(service.lastPlan);
  } on AppError catch (e) {
    AppLogger.error('복습 알림을 다시 예약하지 못했어요', error: e);
  } catch (e, st) {
    AppLogger.error('복습 알림을 다시 예약하지 못했어요', error: e, stack: st);
  }
}

import 'dart:async';
import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../domain/models.dart';
import 'logger.dart';
import 'routes.dart';

/// 로컬 복습 알림.
///
/// **서버의 `review_schedules` 가 스케줄의 소스 오브 트루스이고, 여기 있는 것은 파생된 캐시다.**
/// 알림이 유실되거나(기기 재부팅·OS 정리·64개 한도 초과) 사용자가 알림을 꺼도, 앱을 열면
/// 복습 큐는 서버에서 다시 정확하게 복원된다. 그래서 이 파일은 간격을 계산하지 않는다 —
/// 서버가 준 `due_at` 을 **기기 사정(하루 상한·야간 금지·슬롯 한도)에 맞춰 고르기만** 한다.

// ── 서버와 맞춰 둔 상수 ───────────────────────────────────────────────────
// server/supabase/functions/_shared/review-schedule.ts 와 같은 값이어야 한다.
// 여기 값이 서버보다 크면 서버가 의도한 것보다 많은 알림이 나간다.

/// iOS 는 앱당 대기 중인 로컬 알림을 64개까지만 유지한다. 다른 알림용 여유를 남긴다.
const int kNotificationSlots = 48;

/// 알림 피로가 이 기능을 죽이는 1번 원인이다.
const int kMaxReviewsPerDay = 3;

/// 야간 금지 구간(로컬 시각). 이 사이에 걸린 알림은 다음 발송 가능 시각으로 민다.
const int kQuietStartHour = 22;
const int kQuietEndHour = 8;

/// 복습 알림을 보낼 수 있는 시각의 범위. 사용자가 고를 수 있는 값도 이 범위다.
const int kEarliestReviewHour = kQuietEndHour; // 8
const int kLatestReviewHour = kQuietStartHour - 1; // 21

const String kReviewChannelId = 'onpar_review';
const String kReviewChannelName = '복습 알림';

/// 알림 id 규칙 — 우리가 만든 알림만 골라 지우려고 id 공간을 갈라 쓴다.
///
/// `cancelAll()` 은 다른 기능(공지·결제 등)이 나중에 걸어 둘 알림까지 지운다.
/// 그래서 복습 알림은 [kReviewIdBase] ~ [kReviewIdBase]+[kReviewIdSpan)-1 구간만 쓰고,
/// 재예약할 때는 대기 목록에서 이 구간에 드는 id 만 취소한다.
/// id 는 `schedule_id` 의 FNV-1a 해시라서 같은 회차는 언제 다시 예약해도 같은 id 가 된다(중복 방지).
const int kReviewIdBase = 0x52000000; // 'R'
const int kReviewIdSpan = 0x01000000; // 16,777,216

bool isReviewNotificationId(int id) => id >= kReviewIdBase && id < kReviewIdBase + kReviewIdSpan;

/// `schedule_id` → 안정적인 32비트 알림 id.
int reviewNotificationId(String scheduleId) {
  // FNV-1a 32bit. 해시 함수를 고르는 기준은 분포가 아니라 **재현성**이다 —
  // 앱을 다시 켜도, 다른 기기에서도 같은 schedule_id 면 같은 id 여야 중복 예약이 안 생긴다.
  var hash = 0x811c9dc5;
  for (final unit in scheduleId.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return kReviewIdBase + (hash % kReviewIdSpan);
}

/// 알림 본문은 문제 원문이다. 배너를 읽는 순간 인출(retrieval)이 시작된다.
///
/// 서버 `notificationBody` 와 **같은 규칙**이다(문장 경계 우선, 아니면 그냥 자르기).
/// 규칙이 두 벌이 되지 않도록 순수 함수로 떼어 두고 테스트로 고정한다
/// (`test/notification_schedule_test.dart`).
String notificationBody(String question, {int maxLength = 100}) {
  if (question.length <= maxLength) return question;
  final cut = question.substring(0, maxLength);
  final lastStop = [
    cut.lastIndexOf('. '),
    cut.lastIndexOf('? '),
    cut.lastIndexOf('요 '),
  ].reduce((a, b) => a > b ? a : b);
  final head = lastStop > maxLength * 0.5 ? cut.substring(0, lastStop + 1) : cut.trimRight();
  return '$head…';
}

/// 복습 알림을 받을 시각을 발송 가능한 범위로 가둔다.
///
/// 야간 금지 구간 안의 시각을 그대로 두면 "야간이면 다음 날 reviewHour 로 민다" 가
/// 영원히 반복된다. 설정 화면도 이 범위만 보여 준다.
int clampReviewHour(int hour) => hour.clamp(kEarliestReviewHour, kLatestReviewHour);

/// 야간(22시~08시)에 걸린 알림을 다음 발송 가능 시각으로 민다. 앞으로만 민다.
tz.TZDateTime shiftOutOfQuietHours(tz.TZDateTime at, int reviewHour) {
  final hour = clampReviewHour(reviewHour);
  if (at.hour >= kQuietStartHour) {
    // 밤 10시 이후 → 다음 날 복습 시각
    return _atLocalHour(at, 1, hour);
  }
  if (at.hour < kQuietEndHour) {
    // 새벽 → 같은 날 복습 시각
    return _atLocalHour(at, 0, hour);
  }
  return at;
}

/// 그 타임존 기준 `daysAhead` 일 뒤 `hour` 시. 서머타임 경계에서도 로컬 벽시계 기준을 지킨다
/// (`TZDateTime` 생성자가 그 지역의 오프셋으로 해석한다).
tz.TZDateTime _atLocalHour(tz.TZDateTime base, int daysAhead, int hour) =>
    tz.TZDateTime(base.location, base.year, base.month, base.day + daysAhead, hour);

String _dayKey(tz.TZDateTime d) => '${d.year}-${d.month}-${d.day}';

/// 알림의 종류.
enum NotificationKind {
  /// 복습 문제 하나.
  review,

  /// **돌아오라는 한 번의 신호.** 슬롯이 모자라 예약을 다 못 걸었을 때만 건다.
  ///
  /// 로컬 알림은 앱을 열어야 다시 걸린다. 슬롯 48개에 하루 3개면 약 16일치이고,
  /// 그 뒤로 앱을 안 열면 복습 제품이 조용히 죽는다 — 사용자는 우리가 포기했다고 느낀다.
  /// 원격 푸시가 없는 지금, 예약이 마르기 직전에 한 번 부르는 것이 할 수 있는 최선이다.
  returning,
}

/// 예약이 마른 뒤 부르는 알림의 고정 식별자. 복습 id 공간 안이라 기존 정리 규칙이 그대로 적용된다.
const String kReturnNudgeScheduleId = '__return__';

/// 실제로 걸 알림 하나. 순수 계산의 결과물이라 테스트에서 그대로 들여다볼 수 있다.
class PlannedNotification {
  const PlannedNotification({
    required this.id,
    required this.scheduleId,
    required this.worksheetId,
    required this.quizItemId,
    required this.title,
    required this.body,
    required this.at,
    this.kind = NotificationKind.review,
  });

  final NotificationKind kind;

  final int id;
  final String scheduleId;
  final String worksheetId;
  final String quizItemId;
  final String title;
  final String body;

  /// 발송 예정 시각(사용자 로컬).
  final tz.TZDateTime at;

  String get payload => jsonEncode({
        'type': kind.name,
        'schedule_id': scheduleId,
        'worksheet_id': worksheetId,
        'quiz_item_id': quizItemId,
      });
}

/// 서버가 준 예정 목록에서 **실제로 걸 알림**을 고른다. 순수 함수 — 여기에만 규칙이 있다.
///
/// 1. 이미 지난 것은 뺀다(지난 시각으로 예약하면 OS 가 즉시 쏘거나 조용히 버린다).
/// 2. 야간(22~08시)에 걸린 것은 발송 가능한 시각으로 민다.
/// 3. 하루 [maxPerDay] 개를 넘기면 다음 날로 민다(서버 `applyDailyCap` 과 같은 규칙).
/// 4. 임박한 것부터 [slots] 개까지만 남긴다(서버 `selectForNotifications` 과 같은 규칙).
List<PlannedNotification> planReviewNotifications({
  required List<ReviewItem> upcoming,
  required tz.Location location,
  required DateTime now,
  required int reviewHour,
  int maxPerDay = kMaxReviewsPerDay,
  int slots = kNotificationSlots,
}) {
  final nowLocal = tz.TZDateTime.from(now, location);
  final hour = clampReviewHour(reviewHour);

  final seen = <String>{};
  final candidates = <({ReviewItem item, tz.TZDateTime due})>[];
  for (final item in upcoming) {
    if (!seen.add(item.scheduleId)) continue; // 같은 회차가 두 번 오면 한 번만 건다
    final due = tz.TZDateTime.from(item.dueAt, location);
    if (!due.isAfter(nowLocal)) continue; // 이미 지난 것은 예약하지 않는다
    candidates.add((item: item, due: due));
  }
  candidates.sort((a, b) => a.due.compareTo(b.due));

  final perDay = <String, int>{};
  final placed = <({ReviewItem item, tz.TZDateTime at})>[];
  for (final c in candidates) {
    var at = shiftOutOfQuietHours(c.due, hour);
    var guard = 0;
    while ((perDay[_dayKey(at)] ?? 0) >= maxPerDay) {
      at = _atLocalHour(at, 1, hour);
      if (++guard > 365) break; // 무한 루프 방지 — 서버 applyDailyCap 과 같은 안전장치
    }
    perDay.update(_dayKey(at), (v) => v + 1, ifAbsent: () => 1);
    placed.add((item: c.item, at: at));
  }

  placed.sort((a, b) => a.at.compareTo(b.at));

  // 슬롯이 모자라 못 거는 것이 생기면, 마지막 한 자리는 "돌아오라" 에 내준다.
  // 슬롯 수는 OS 가 들고 있어 주는 대기열의 크기라서, 총합이 이 수를 넘으면 안 된다 —
  // 넘긴 알림은 조용히 버려지고 우리는 그걸 알 방법이 없다.
  final limit = slots < 0 ? 0 : slots;
  final needNudge = placed.length > limit && limit >= 2;
  final reviewSlots = needNudge ? limit - 1 : limit;

  final out = <PlannedNotification>[];
  for (final p in placed.take(reviewSlots)) {
    final title = (p.item.worksheetTitle ?? '').trim();
    out.add(PlannedNotification(
      id: reviewNotificationId(p.item.scheduleId),
      scheduleId: p.item.scheduleId,
      worksheetId: p.item.worksheetId,
      quizItemId: p.item.quizItemId,
      title: title.isEmpty ? '🧠 복습할 시간이에요' : '🧠 $title',
      body: notificationBody(p.item.question),
      at: p.at,
    ));
  }
  // 예약이 마르는 다음 날 한 번 부른다. 이게 없으면 16일 뒤부터 앱은 아무 말도 하지 않는다.
  if (needNudge && out.isNotEmpty) {
    out.add(PlannedNotification(
      kind: NotificationKind.returning,
      id: reviewNotificationId(kReturnNudgeScheduleId),
      scheduleId: kReturnNudgeScheduleId,
      // 특정 학습지를 가리키지 않는다 — 눌러서 열면 복습 큐로 간다(routeFromPayload).
      worksheetId: '',
      quizItemId: '',
      title: '🧠 복습이 밀려 있어요',
      body: '앱을 열면 다음 복습을 이어서 알려드릴게요.',
      at: _atLocalHour(out.last.at, 1, hour),
    ));
  }

  return out;
}

/// 알림 payload 에서 앱이 열어야 할 경로를 뽑는다.
///
/// 라우터가 이 문자열을 그대로 `go` 한다. 경로 문자열을 화면마다 짜맞추지 않도록
/// 여기서 [Routes] 만 쓴다. 형식: `/worksheet/<worksheet_id>?quizId=<quiz_item_id>`
String? routeFromPayload(String? payload) {
  if (payload == null || payload.isEmpty) return null;
  try {
    final decoded = jsonDecode(payload);
    if (decoded is! Map) return null;
    final worksheetId = decoded['worksheet_id'];
    final quizItemId = decoded['quiz_item_id'];
    if (worksheetId is! String || worksheetId.isEmpty) {
      // 학습지를 모르면 복습 큐로 보낸다 — 빈 화면보다 낫다.
      return Routes.reviewSession;
    }
    final base = Routes.worksheet(worksheetId);
    return quizItemId is String && quizItemId.isNotEmpty ? '$base?quizId=$quizItemId' : base;
  } catch (_) {
    return null;
  }
}

/// OS 알림 권한 상태.
///
/// `granted` 가 아니면 앱 안의 스위치를 켜도 알림은 오지 않는다. 그래서 그냥 bool 이 아니라
/// **설정으로 보내야 하는 상태([blocked])를 따로 구분**한다.
enum NotificationPermission {
  granted,

  /// 아직 안 물었거나 한 번 거절했다. 다시 물어볼 수 있다.
  denied,

  /// OS 설정에서 꺼졌다. 앱에서 다시 물을 수 없고 설정으로 보내야 한다.
  blocked,

  /// 알림을 지원하지 않는 환경(데스크톱·테스트 등).
  unsupported,
}

/// 마지막 재예약 결과. 권한이 없어 건너뛴 것도 "아무 일 없음"이 아니라 상태로 남긴다.
class NotificationSyncStatus {
  const NotificationSyncStatus({
    required this.at,
    required this.scheduled,
    required this.skippedForPermission,
  });

  final DateTime at;
  final int scheduled;
  final bool skippedForPermission;
}

class NotificationService {
  NotificationService({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  final StreamController<String> _routes = StreamController<String>.broadcast();

  bool _ready = false;

  /// 앱이 알림 탭으로 **켜진** 경우, 라우터가 구독하기 전에 이벤트가 지나가 버린다.
  /// 그래서 첫 구독자에게 한 번 흘려보낼 경로를 들고 있는다.
  String? _pendingRoute;

  List<PlannedNotification> _lastPlan = const [];
  NotificationSyncStatus? _lastSync;

  /// 마지막으로 예약한 목록. "받은 알림" 목록을 로컬에 남길 때 쓴다.
  List<PlannedNotification> get lastPlan => _lastPlan;

  NotificationSyncStatus? get lastSync => _lastSync;

  /// 알림을 눌러 열어야 할 경로. 라우터가 구독한다.
  ///
  /// 내보내는 값은 `/worksheet/<worksheet_id>?quizId=<quiz_item_id>` 형식의 앱 내부 경로다.
  Stream<String> get onOpenRoute async* {
    final pending = _pendingRoute;
    if (pending != null) {
      _pendingRoute = null;
      yield pending;
    }
    yield* _routes.stream;
  }

  /// 타임존·채널·탭 콜백을 준비한다. 앱 시작에서 한 번.
  Future<void> init() async {
    if (_ready) return;
    _ready = true;

    tzdata.initializeTimeZones();
    try {
      final name = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(name));
    } catch (e) {
      // 기기 타임존을 못 읽으면 알림을 통째로 포기하는 대신 기본값으로 간다.
      // 시차가 어긋난 알림이 없는 알림보다 낫다.
      AppLogger.error('타임존을 읽지 못했어요', error: e);
      try {
        tz.setLocalLocation(tz.getLocation('Asia/Seoul'));
      } catch (_) {
        // tz.local 기본값(UTC)을 그대로 쓴다.
      }
    }

    try {
      await _plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          // 권한은 여기서 묻지 않는다 — 가치를 보여 준 뒤(첫 학습지 완성 직후) 묻는다.
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: _onResponse,
      );

      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(const AndroidNotificationChannel(
            kReviewChannelId,
            kReviewChannelName,
            description: '망각곡선에 맞춰 오늘 떠올릴 문제를 보내 드려요.',
            importance: Importance.high,
          ));

      // 알림을 눌러서 앱이 켜진 경우.
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        _emit(routeFromPayload(launch?.notificationResponse?.payload));
      }
    } catch (e, st) {
      // 알림 초기화 실패로 앱이 안 뜨면 안 된다. 복습 큐는 알림 없이도 앱 안에서 돈다.
      AppLogger.error('알림을 준비하지 못했어요', error: e, stack: st);
    }
  }

  void _onResponse(NotificationResponse response) {
    _emit(routeFromPayload(response.payload));
  }

  void _emit(String? route) {
    if (route == null) return;
    if (_routes.hasListener) {
      _routes.add(route);
    } else {
      _pendingRoute = route;
    }
  }

  /// iOS / Android 13+ 권한 요청. 승인됐는지 돌려준다.
  ///
  /// 거절 이후의 상태 구분은 [permissionStatus] 를 쓴다 — 두 번째 거절부터는
  /// OS 가 대화상자를 띄우지 않으므로 설정으로 보내야 한다.
  Future<bool> requestPermission() async {
    await init();
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        final granted = await android.requestNotificationsPermission() ?? false;
        // 정확한 시각 알림 권한은 별개다. 없으면 근사 예약으로 떨어질 뿐 실패는 아니다.
        if (granted && !(await android.canScheduleExactNotifications() ?? true)) {
          await android.requestExactAlarmsPermission();
        }
        return granted;
      }

      final ios =
          _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      if (ios != null) {
        return await ios.requestPermissions(alert: true, badge: true, sound: true) ?? false;
      }
      return false;
    } catch (e, st) {
      AppLogger.error('알림 권한을 요청하지 못했어요', error: e, stack: st);
      return false;
    }
  }

  /// 지금 OS 가 알림을 허용하고 있는지.
  Future<NotificationPermission> permissionStatus() async {
    await init();
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      final ios =
          _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();

      bool? enabled;
      if (android != null) {
        enabled = await android.areNotificationsEnabled();
      } else if (ios != null) {
        enabled = (await ios.checkPermissions())?.isEnabled;
      } else {
        return NotificationPermission.unsupported;
      }
      if (enabled ?? false) return NotificationPermission.granted;

      // 꺼져 있다면 "다시 물어볼 수 있는지"가 다음 행동을 가른다.
      final status = await Permission.notification.status;
      return status.isPermanentlyDenied || status.isRestricted
          ? NotificationPermission.blocked
          : NotificationPermission.denied;
    } catch (e) {
      AppLogger.debug('알림 권한 상태를 읽지 못했어요: $e');
      return NotificationPermission.unsupported;
    }
  }

  /// 서버가 준 예정 목록으로 **로컬 알림을 통째로 다시 예약**한다.
  ///
  /// 앱 포그라운드 진입·복습 응답 후·학습지 생성 완료 후·설정 변경 후에 부른다.
  /// 부분 갱신을 하지 않는 이유: 서버가 소스 오브 트루스라서, 지우고 다시 거는 쪽이
  /// "무엇이 이미 걸려 있었나"를 추적하는 것보다 언제나 정확하다.
  Future<void> syncFromServer(
    List<ReviewItem> upcoming, {
    required int reviewHour,
    required String timeZone,
  }) async {
    await init();

    final permission = await permissionStatus();
    if (permission != NotificationPermission.granted) {
      // 권한이 없으면 예약을 시도하지 않는다(플랫폼마다 조용히 실패하거나 예외가 난다).
      // 대신 상태를 남긴다 — 설정 화면이 "OS 알림이 꺼져 있어요"를 보여 줄 근거다.
      _lastPlan = const [];
      _lastSync = NotificationSyncStatus(
        at: DateTime.now(),
        scheduled: 0,
        skippedForPermission: true,
      );
      AppLogger.info('알림 권한이 없어 복습 알림 예약을 건너뛰었어요(${permission.name})');
      return;
    }

    final plan = planReviewNotifications(
      upcoming: upcoming,
      location: locationOf(timeZone),
      now: DateTime.now(),
      reviewHour: reviewHour,
    );

    await cancelReviewNotifications();

    final mode = await _scheduleMode();
    final details = NotificationDetails(
      android: const AndroidNotificationDetails(
        kReviewChannelId,
        kReviewChannelName,
        channelDescription: '망각곡선에 맞춰 오늘 떠올릴 문제를 보내 드려요.',
        importance: Importance.high,
        priority: Priority.high,
        // 문제 원문이 길어도 펼쳐서 읽을 수 있어야 인출이 시작된다.
        styleInformation: BigTextStyleInformation(''),
      ),
      iOS: const DarwinNotificationDetails(),
    );

    final scheduled = <PlannedNotification>[];
    for (final p in plan) {
      try {
        await _plugin.zonedSchedule(
          p.id,
          p.title,
          p.body,
          p.at,
          details,
          payload: p.payload,
          androidScheduleMode: mode,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
        scheduled.add(p);
      } catch (e, st) {
        // 하나가 실패해도 나머지는 걸어 둔다. 여기서 멈추면 사용자는 알림을 통째로 잃는다.
        AppLogger.error('복습 알림 하나를 예약하지 못했어요', error: e, stack: st);
      }
    }

    _lastPlan = List.unmodifiable(scheduled);
    _lastSync = NotificationSyncStatus(
      at: DateTime.now(),
      scheduled: scheduled.length,
      skippedForPermission: false,
    );
    AppLogger.info('복습 알림 ${scheduled.length}개를 예약했어요');
  }

  /// 우리가 건 복습 알림만 취소한다. `cancelAll()` 은 남의 알림까지 지운다.
  Future<void> cancelReviewNotifications() async {
    try {
      final pending = await _plugin.pendingNotificationRequests();
      for (final p in pending) {
        if (isReviewNotificationId(p.id)) await _plugin.cancel(p.id);
      }
    } catch (e, st) {
      AppLogger.error('예약된 복습 알림을 정리하지 못했어요', error: e, stack: st);
    }
  }

  /// 정확한 시각 알림을 걸 수 있으면 그렇게, 아니면 근사 예약으로 떨어진다.
  /// Android 14 는 `SCHEDULE_EXACT_ALARM` 없이 exact 로 걸면 예외를 던진다.
  Future<AndroidScheduleMode> _scheduleMode() async {
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (android == null) return AndroidScheduleMode.exactAllowWhileIdle;
      final exact = await android.canScheduleExactNotifications() ?? false;
      return exact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle;
    } catch (_) {
      return AndroidScheduleMode.inexactAllowWhileIdle;
    }
  }

  /// 이름이 이상하거나(서버 값이 낡았거나) 데이터베이스에 없는 타임존이면 기기 로컬로 떨어진다.
  static tz.Location locationOf(String timeZone) {
    try {
      return tz.getLocation(timeZone);
    } catch (_) {
      return tz.local;
    }
  }

  void dispose() {
    unawaited(_routes.close());
  }
}

final notificationServiceProvider = Provider<NotificationService>((ref) {
  final service = NotificationService();
  ref.onDispose(service.dispose);
  return service;
});

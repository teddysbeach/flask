import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/bootstrap.dart';
import '../../core/logger.dart';
import '../../core/notifications.dart';

/// 알림 스위치와 "받은 알림" 목록.
///
/// 받은 알림을 담는 서버 테이블이 없다. 그렇다고 목록을 비워 두면 사용자는 알림을 놓쳤을 때
/// 무엇이 왔었는지 확인할 방법이 없다. 그래서 **예약한 알림을 기기에 적어 두고**,
/// 발송 시각이 지난 것을 "받은 알림"으로 보여 준다. 로컬 알림이라 이 기록과 실제 발송이 같다.
/// (서버 테이블이 생기면 이 목록의 출처만 갈아끼우면 된다.)
class NotificationLogEntry {
  const NotificationLogEntry({
    required this.id,
    required this.scheduleId,
    required this.worksheetId,
    required this.quizItemId,
    required this.title,
    required this.body,
    required this.deliverAt,
    required this.read,
  });

  final int id;
  final String scheduleId;
  final String worksheetId;
  final String quizItemId;
  final String title;
  final String body;
  final DateTime deliverAt;
  final bool read;

  bool get delivered => !deliverAt.isAfter(DateTime.now());

  NotificationLogEntry copyWith({bool? read}) => NotificationLogEntry(
        id: id,
        scheduleId: scheduleId,
        worksheetId: worksheetId,
        quizItemId: quizItemId,
        title: title,
        body: body,
        deliverAt: deliverAt,
        read: read ?? this.read,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'schedule_id': scheduleId,
        'worksheet_id': worksheetId,
        'quiz_item_id': quizItemId,
        'title': title,
        'body': body,
        'deliver_at': deliverAt.toIso8601String(),
        'read': read,
      };

  static NotificationLogEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final at = DateTime.tryParse('${raw['deliver_at']}');
    if (at == null) return null;
    return NotificationLogEntry(
      id: (raw['id'] as num?)?.toInt() ?? 0,
      scheduleId: '${raw['schedule_id'] ?? ''}',
      worksheetId: '${raw['worksheet_id'] ?? ''}',
      quizItemId: '${raw['quiz_item_id'] ?? ''}',
      title: '${raw['title'] ?? ''}',
      body: '${raw['body'] ?? ''}',
      deliverAt: at,
      read: raw['read'] == true,
    );
  }
}

class NotificationPrefs {
  NotificationPrefs(this._prefs);
  final SharedPreferences _prefs;

  static const _kAll = 'noti_all_v1';
  static const _kReview = 'noti_review_v1';
  static const _kMarketing = 'noti_marketing_v1';
  static const _kLog = 'noti_log_v1';

  /// 최근 것만 남긴다. 목록이 길어질수록 읽히지 않고 저장만 커진다.
  static const maxEntries = 50;

  /// 전체 스위치. 이걸 끄면 아래 스위치와 상관없이 아무것도 예약하지 않는다.
  bool get allEnabled => _prefs.getBool(_kAll) ?? true;
  bool get reviewEnabled => _prefs.getBool(_kReview) ?? true;

  /// 마케팅 알림은 **동의 이력이 먼저다.** 아직 이 화면에서 따로 고른 적이 없으면 null 을 돌려주고,
  /// 화면이 약관 동의 때 남긴 값(`ConsentRecord.marketing`)을 쓰게 한다.
  /// 여기서 false 로 뭉개면 동의했던 사용자가 이유 없이 거부로 보인다.
  bool? get marketingChoice => _prefs.getBool(_kMarketing);
  bool get marketingEnabled => marketingChoice ?? false;

  /// 복습 알림을 실제로 걸어야 하는지. 화면마다 두 스위치를 각각 보고 판단하면 어긋난다.
  bool get reviewNotificationsOn => allEnabled && reviewEnabled;

  Future<void> setAllEnabled(bool v) => _prefs.setBool(_kAll, v);
  Future<void> setReviewEnabled(bool v) => _prefs.setBool(_kReview, v);
  Future<void> setMarketingEnabled(bool v) => _prefs.setBool(_kMarketing, v);

  List<NotificationLogEntry> entries() {
    final raw = _prefs.getStringList(_kLog) ?? const <String>[];
    final out = <NotificationLogEntry>[];
    for (final line in raw) {
      try {
        final entry = NotificationLogEntry.fromJson(jsonDecode(line));
        if (entry != null) out.add(entry);
      } catch (e) {
        // 형식이 깨진 한 줄 때문에 목록 전체를 잃지 않는다.
        AppLogger.debug('알림 기록 한 줄을 읽지 못했어요: $e');
      }
    }
    out.sort((a, b) => b.deliverAt.compareTo(a.deliverAt));
    return out;
  }

  /// 화면에 보여 줄 것 — 발송 시각이 지난 것만 "받은 알림"이다.
  List<NotificationLogEntry> delivered() => entries().where((e) => e.delivered).toList();

  int get unreadCount => delivered().where((e) => !e.read).length;

  /// 방금 예약한 목록을 기록에 합친다. 읽음 표시는 유지한다.
  Future<void> rememberPlanned(List<PlannedNotification> planned) async {
    final byId = <int, NotificationLogEntry>{for (final e in entries()) e.id: e};
    for (final p in planned) {
      final previous = byId[p.id];
      byId[p.id] = NotificationLogEntry(
        id: p.id,
        scheduleId: p.scheduleId,
        worksheetId: p.worksheetId,
        quizItemId: p.quizItemId,
        title: p.title,
        body: p.body,
        deliverAt: p.at,
        // 같은 회차를 다시 예약해도 이미 읽은 것을 안 읽음으로 되돌리지 않는다.
        read: previous?.read ?? false,
      );
    }
    await _write(byId.values.toList());
  }

  Future<void> markRead(int id) async {
    final list = entries().map((e) => e.id == id ? e.copyWith(read: true) : e).toList();
    await _write(list);
  }

  Future<void> markAllRead() async {
    await _write(entries().map((e) => e.copyWith(read: true)).toList());
  }

  Future<void> clear() => _prefs.remove(_kLog);

  Future<void> _write(List<NotificationLogEntry> list) async {
    list.sort((a, b) => b.deliverAt.compareTo(a.deliverAt));
    final trimmed = list.take(maxEntries).map((e) => jsonEncode(e.toJson())).toList();
    await _prefs.setStringList(_kLog, trimmed);
  }
}

/// SharedPreferences 가 이미 준비된 곳에서만 읽는다(부팅이 끝난 뒤).
/// 준비 전 화면은 [sharedPrefsProvider] 를 직접 지켜보며 Loading 을 그린다.
final notificationPrefsProvider = Provider<NotificationPrefs>((ref) {
  return NotificationPrefs(ref.watch(sharedPrefsProvider).requireValue);
});

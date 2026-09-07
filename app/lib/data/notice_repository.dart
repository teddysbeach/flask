import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_error.dart';
import '../core/env.dart';
import '../core/routes.dart';
import 'supabase.dart';

/// 공지와 이벤트가 갈리는 지점.
///
/// 사는 곳은 같다(둘 다 "우리가 사용자에게 하는 말"). 다른 것은 **다음 행동이 있는가** 뿐이다.
enum NoticeKind { notice, event }

/// 공지 한 건.
class Notice {
  const Notice({
    required this.id,
    required this.title,
    required this.body,
    required this.pinned,
    required this.publishedAt,
    this.kind = NoticeKind.notice,
    this.ctaLabel,
    this.ctaRoute,
  });

  final String id;
  final String title;
  final String body;
  final bool pinned;
  final DateTime publishedAt;
  final NoticeKind kind;

  /// 누를 곳. 라벨과 경로는 함께 있거나 함께 없다(서버 제약도 같다).
  final String? ctaLabel;
  final String? ctaRoute;

  bool get isEvent => kind == NoticeKind.event;
  bool get hasAction => ctaLabel != null && ctaRoute != null;

  factory Notice.fromMap(Map<String, dynamic> m) => Notice(
        id: '${m['id']}',
        title: '${m['title']}',
        body: '${m['body']}',
        pinned: m['pinned'] == true,
        publishedAt: DateTime.tryParse('${m['published_at']}')?.toLocal() ?? DateTime.now(),
        kind: '${m['kind']}' == 'event' ? NoticeKind.event : NoticeKind.notice,
        ctaLabel: m['cta_label'] as String?,
        // **서버가 준 경로를 그대로 믿지 않는다.** 허용 목록에 없으면 버린다 —
        // 여기가 뚫리면 공지 한 줄로 사용자를 앱 안 아무 데나 보낼 수 있다.
        ctaRoute: safeCtaRoute(m['cta_route']),
      );
}

/// 공지가 보낼 수 있는 곳. **여기 없는 경로는 버린다.**
///
/// 열어 두면 "탈퇴 화면으로 보내는 이벤트 배너" 같은 것이 가능해진다.
/// 사용자가 홈에서 누를 만한 곳만 남긴다.
const kNoticeCtaAllowList = <String>{
  Routes.paywall,
  Routes.create,
  Routes.reviewSession,
  Routes.notices,
  Routes.support,
  Routes.faq,
  Routes.stats,
  Routes.purchases,
};

String? safeCtaRoute(Object? raw) {
  if (raw is! String) return null;
  final path = Uri.tryParse(raw.trim())?.path ?? '';
  return kNoticeCtaAllowList.contains(path) ? path : null;
}

/// 공지. **로그인 없이 읽힌다** — 점검 공지는 로그인이 안 될 때 가장 필요하다.
class NoticeRepository {
  NoticeRepository(this._client);
  final SupabaseClient _client;

  Future<List<Notice>> list({int limit = 30}) async {
    try {
      final rows = await _client
          .from('notices')
          .select('id, title, body, pinned, published_at, kind, cta_label, cta_route')
          // 고정 공지가 먼저, 그다음 최신순.
          .order('pinned', ascending: false)
          .order('published_at', ascending: false)
          .limit(limit)
          .withTimeout();
      return rows.map((r) => Notice.fromMap(r)).toList();
    } catch (e, st) {
      throw mapSupabaseError(e, st);
    }
  }
}

final noticeRepositoryProvider =
    Provider<NoticeRepository>((ref) => NoticeRepository(ref.watch(supabaseProvider)));

final noticesProvider = FutureProvider<List<Notice>>((ref) async {
  // 설정이 없으면 서버를 못 부른다. 빈 목록이 오류보다 정직하다.
  if (!Env.isConfigured) return const [];
  return ref.watch(noticeRepositoryProvider).list();
});

/// 홈 맨 위에 띄울 고정 공지 **한 건**.
///
/// 여러 개를 쌓지 않는다. 공지가 셋 쌓인 홈은 공지판이지 학습 앱이 아니고,
/// 그렇게 되는 순간 사용자는 배너를 통째로 안 보게 된다 — 정작 점검 공지가 떴을 때도.
final pinnedNoticeProvider = Provider<Notice?>((ref) {
  final all = ref.watch(noticesProvider).valueOrNull ?? const <Notice>[];
  for (final n in all) {
    if (n.pinned && !n.isEvent) return n;
  }
  return null;
});

/// 지금 도는 이벤트 한 건. 목록이 최신순이라 첫 번째가 가장 최근이다.
final activeEventProvider = Provider<Notice?>((ref) {
  final all = ref.watch(noticesProvider).valueOrNull ?? const <Notice>[];
  for (final n in all) {
    if (n.isEvent) return n;
  }
  return null;
});

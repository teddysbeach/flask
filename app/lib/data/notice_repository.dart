import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_error.dart';
import '../core/env.dart';
import 'supabase.dart';

/// 공지 한 건.
class Notice {
  const Notice({
    required this.id,
    required this.title,
    required this.body,
    required this.pinned,
    required this.publishedAt,
  });

  final String id;
  final String title;
  final String body;
  final bool pinned;
  final DateTime publishedAt;

  factory Notice.fromMap(Map<String, dynamic> m) => Notice(
        id: '${m['id']}',
        title: '${m['title']}',
        body: '${m['body']}',
        pinned: m['pinned'] == true,
        publishedAt: DateTime.tryParse('${m['published_at']}')?.toLocal() ?? DateTime.now(),
      );
}

/// 공지. **로그인 없이 읽힌다** — 점검 공지는 로그인이 안 될 때 가장 필요하다.
class NoticeRepository {
  NoticeRepository(this._client);
  final SupabaseClient _client;

  Future<List<Notice>> list({int limit = 30}) async {
    try {
      final rows = await _client
          .from('notices')
          .select('id, title, body, pinned, published_at')
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

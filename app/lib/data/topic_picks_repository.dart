import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_error.dart';
import '../core/env.dart';
import 'supabase.dart';

/// 우리가 고른 주제 하나.
class TopicPick {
  const TopicPick({required this.id, required this.topic, this.category, this.blurb});

  final String id;

  /// 만들기 화면에 그대로 채워질 문장. 사용자가 고쳐 쓸 수 있다.
  final String topic;
  final String? category;
  final String? blurb;

  factory TopicPick.fromMap(Map<String, dynamic> m) => TopicPick(
        id: '${m['id']}',
        topic: '${m['topic']}',
        category: m['category'] as String?,
        blurb: m['blurb'] as String?,
      );
}

/// 추천 주제.
///
/// **"다른 사람들이 많이 만든 주제" 가 아니다.** 주제는 사용자가 쓴 글이고 거기에는
/// 남에게 보이면 안 되는 것이 들어온다. 집계라도 원문이 화면에 나오면 그건 유출이다.
/// 그래서 우리가 고른다 — 남이 뭘 배우는지 알려주는 느낌은 그대로 얻으면서
/// 누구의 데이터도 쓰지 않는다.
class TopicPicksRepository {
  TopicPicksRepository(this._client);
  final SupabaseClient _client;

  Future<List<TopicPick>> list({int limit = 8}) async {
    try {
      final rows = await _client
          .from('topic_picks')
          .select('id, topic, category, blurb')
          .order('sort_order')
          .limit(limit)
          .withTimeout();
      return rows.map((r) => TopicPick.fromMap(r)).toList();
    } catch (e, st) {
      throw mapSupabaseError(e, st);
    }
  }
}

final topicPicksRepositoryProvider =
    Provider<TopicPicksRepository>((ref) => TopicPicksRepository(ref.watch(supabaseProvider)));

/// 못 불러와도 **오류를 내지 않는다.** 추천은 곁가지라, 이것 때문에 홈이 오류 화면이
/// 되면 안 된다. 빈 목록이면 섹션 자체가 안 보인다.
final topicPicksProvider = FutureProvider<List<TopicPick>>((ref) async {
  if (!Env.isConfigured) return const [];
  try {
    return await ref.watch(topicPicksRepositoryProvider).list();
  } catch (_) {
    return const [];
  }
});

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_error.dart';
import 'supabase.dart';

/// 문의 한 건. 사용자가 보낸 것과 운영이 단 답.
class SupportTicket {
  const SupportTicket({
    required this.id,
    required this.topic,
    required this.body,
    required this.status,
    required this.createdAt,
    this.answer,
    this.answeredAt,
  });

  final String id;
  final String topic;
  final String body;

  /// open · answered · closed
  final String status;
  final DateTime createdAt;
  final String? answer;
  final DateTime? answeredAt;

  /// 접수 번호. 문의 직후 화면에 보여준 것과 같은 여덟 자리다.
  String get shortId => id.replaceAll('-', '').substring(0, 8).toUpperCase();

  bool get answered => answer != null && answer!.trim().isNotEmpty;

  factory SupportTicket.fromMap(Map<String, dynamic> m) => SupportTicket(
        id: '${m['id']}',
        topic: '${m['topic']}',
        body: '${m['body']}',
        status: '${m['status']}',
        createdAt: DateTime.tryParse('${m['created_at']}')?.toLocal() ?? DateTime.now(),
        answer: m['answer'] as String?,
        answeredAt: DateTime.tryParse('${m['answered_at']}')?.toLocal(),
      );
}

/// 내가 보낸 문의.
///
/// RLS(`support_tickets_select_own`)가 본인 것만 돌려준다. 로그아웃 상태에서 보낸 문의는
/// user_id 가 없어서 여기 안 나온다 — 익명으로 보낸 글을 계정에 붙이면 그건 익명이 아니다.
class SupportRepository {
  SupportRepository(this._client);
  final SupabaseClient _client;

  Future<List<SupportTicket>> myTickets({int limit = 30}) async {
    try {
      final rows = await _client
          .from('support_tickets')
          .select('id, topic, body, status, created_at, answer, answered_at')
          .order('created_at', ascending: false)
          .limit(limit)
          .withTimeout();
      return rows.map((r) => SupportTicket.fromMap(r)).toList();
    } catch (e, st) {
      throw mapSupabaseError(e, st);
    }
  }
}

final supportRepositoryProvider =
    Provider<SupportRepository>((ref) => SupportRepository(ref.watch(supabaseProvider)));

final myTicketsProvider = FutureProvider<List<SupportTicket>>((ref) {
  // 로그인해야 볼 수 있다. 계정이 바뀌면 앞사람의 문의가 남아 있으면 안 된다.
  ref.watch(currentUserProvider);
  return ref.watch(supportRepositoryProvider).myTickets();
});

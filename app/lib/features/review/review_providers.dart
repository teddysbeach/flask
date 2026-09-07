import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/review_repository.dart';
import '../../data/supabase.dart';
import '../../domain/models.dart';

/// 복습 큐. 홈·복습 탭·복습 세션이 같은 목록을 본다.
///
/// 서버가 소스 오브 트루스라, 알림이 오지 않았어도(권한 거부·유실) 앱을 열면 여기서 복원된다.
final dueReviewsProvider = FutureProvider<List<ReviewItem>>((ref) {
  ref.watch(currentUserProvider); // 계정이 바뀌면 남의 큐를 그대로 들고 있으면 안 된다
  return ref.watch(reviewRepositoryProvider).due();
});

/// 홈 화면의 "오늘의 복습 N개" 배지.
///
/// 같은 목록의 길이를 쓴다 — 개수를 따로 세면 배지의 숫자와 실제 큐가 어긋나는 날이 온다.
final dueReviewCountProvider = FutureProvider<int>((ref) async {
  final items = await ref.watch(dueReviewsProvider.future);
  return items.length;
});

/// 앞으로 예정된 복습. 로컬 알림 재예약에 쓴다.
final upcomingReviewsProvider = FutureProvider<List<ReviewItem>>((ref) {
  ref.watch(currentUserProvider);
  return ref.watch(reviewRepositoryProvider).upcoming();
});

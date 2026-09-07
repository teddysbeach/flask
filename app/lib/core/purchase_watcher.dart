import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/profile_repository.dart';
import '../data/purchase_repository.dart';
import '../data/supabase.dart';
import 'env.dart';
import 'logger.dart';

/// 스토어 결과를 **앱이 살아 있는 내내** 듣는다.
///
/// 결제는 결제 화면 안에서만 끝나지 않는다. 가족 승인, 통신 끊김, 검증 중 앱 종료,
/// 스토어가 나중에 다시 보내주는 미완료 거래 — 전부 결제 화면이 떠 있지 않을 때 도착한다.
/// 리포지터리는 만들어지는 순간 스트림을 구독하는데, 그동안 그 리포지터리를 읽는 곳은
/// 결제 화면뿐이었다. 즉 **결제 화면을 한 번도 안 열면 아무도 안 듣고 있었다** —
/// 돈은 빠졌는데 장수가 안 늘어난 채로 남는 길이 바로 이것이다.
///
/// 지급은 여전히 서버가 한다. 여기서 하는 일은 두 가지뿐이다 —
/// 구독을 살려 두고, 지급이 확인되면 화면이 든 옛 장수를 버린다.
final purchaseWatcherProvider = Provider<void>((ref) {
  // 서버 설정이 없으면 검증할 곳이 없다. 스토어 플러그인도 건드리지 않는다.
  if (!Env.isConfigured) return;
  // 검증은 사용자 토큰으로 한다. 로그인 전에 받아 봐야 거래를 닫을 수 없다 —
  // 안 닫힌 거래는 스토어가 로그인 뒤에 다시 보내준다.
  if (ref.watch(currentUserProvider) == null) return;

  final sub = ref.watch(purchaseRepositoryProvider).events.listen((e) {
    if (e.phase != PurchasePhase.granted && e.phase != PurchasePhase.alreadyOwned) return;
    // 홈이 옛 숫자를 들고 있으면 방금 산 장수가 없는 것처럼 보인다.
    ref.invalidate(profileProvider);
    AppLogger.debug('결제 지급 확인 (${e.phase.name})');
  });
  ref.onDispose(() => unawaited(sub.cancel()));
});

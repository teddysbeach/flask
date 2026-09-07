import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 연결 상태. "인터넷 없음" 을 오류가 아니라 **상태**로 다루기 위해 따로 둔다.
///
/// 오류로 다루면 화면마다 빨간 글씨가 뜨고 사용자는 자기가 뭘 잘못했는지 찾는다.
/// 상태로 다루면 배너 하나가 뜨고, 연결이 돌아오면 조용히 사라진다.
enum NetStatus { online, offline }

class ConnectivityService {
  ConnectivityService(this._connectivity);

  final Connectivity _connectivity;

  Stream<NetStatus> watch() async* {
    yield await status();
    yield* _connectivity.onConnectivityChanged.map(_map);
  }

  Future<NetStatus> status() async => _map(await _connectivity.checkConnectivity());

  /// connectivity_plus 는 "연결된 인터페이스" 를 알려줄 뿐 실제 도달성은 모른다.
  /// 그래서 이건 낙관적 신호로만 쓰고, 진짜 판단은 요청 실패가 한다.
  static NetStatus _map(List<ConnectivityResult> r) =>
      r.isEmpty || r.every((e) => e == ConnectivityResult.none)
          ? NetStatus.offline
          : NetStatus.online;
}

final connectivityServiceProvider =
    Provider<ConnectivityService>((ref) => ConnectivityService(Connectivity()));

final netStatusProvider = StreamProvider<NetStatus>(
  (ref) => ref.watch(connectivityServiceProvider).watch(),
);

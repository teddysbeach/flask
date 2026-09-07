import 'package:flutter/widgets.dart';

import 'analytics.dart';

/// 화면 조회를 라우터가 자동으로 기록한다.
///
/// 화면마다 `analytics.screen('...')` 을 부르게 하면 반드시 빠뜨리는 화면이 생기고,
/// 그러면 퍼널에 구멍이 난다. 경로는 이미 라우터가 알고 있으므로 여기서 한 번만 잡는다.
class AnalyticsRouteObserver extends NavigatorObserver {
  AnalyticsRouteObserver(this._analytics);

  final Analytics _analytics;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _send(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) => _send(newRoute);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _send(previousRoute);

  void _send(Route<dynamic>? route) {
    final name = _name(route);
    if (name == null) return;
    _analytics.screen(name);
  }

  /// 경로에서 이름을 만든다. **id 는 뺀다** — 학습지 id 가 분석 도구에 쌓이면
  /// 화면 이름이 사용자마다 갈라지고, 그 자체가 식별 가능한 흔적이 된다.
  static String? _name(Route<dynamic>? route) {
    final raw = route?.settings.name;
    if (raw == null || raw.isEmpty) return null;
    final path = Uri.parse(raw).path;
    final cleaned = path
        .split('/')
        .map((seg) => _looksLikeId(seg) ? ':id' : seg)
        .join('/');
    return cleaned.isEmpty ? '/' : cleaned;
  }

  static final _uuid = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

  static bool _looksLikeId(String seg) =>
      _uuid.hasMatch(seg) || (seg.length >= 12 && !seg.contains(RegExp(r'[가-힣]')) && RegExp(r'\d').hasMatch(seg));
}

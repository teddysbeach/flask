import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'env.dart';
import 'logger.dart';
import 'routes.dart';

/// 밖에서 앱으로 들어오는 모든 길: 푸시 · 이메일 링크 · 웹 링크.
///
/// 들어온 곳으로 바로 못 보내는 경우가 있다 — 로그인이 필요한데 로그아웃 상태일 때.
/// 그때 목적지를 버리면 사용자는 로그인 후 홈에 떨어지고 "내가 뭘 누른 거지" 가 된다.
/// 그래서 **보류함**을 둔다. 라우터가 로그인 뒤에 여기서 꺼내 간다.
class DeepLinkService {
  DeepLinkService(this._links);

  final AppLinks _links;
  final _controller = StreamController<String>.broadcast();

  String? _pending;

  Stream<String> get stream => _controller.stream;

  /// 미뤄 둔 목적지를 **비우지 않고** 본다. 리다이렉트 판정은 여러 번 돌 수 있어서,
  /// 판정 중에 비워 버리면 실제로 이동하기 전에 목적지가 사라진다.
  String? peekPending() => _pending;

  /// 로그인 때문에 미뤄 둔 목적지. 한 번 꺼내면 사라진다.
  String? takePending() {
    final p = _pending;
    _pending = null;
    return p;
  }

  void hold(String route) => _pending = route;

  Future<void> start() async {
    try {
      final initial = await _links.getInitialLink();
      if (initial != null) _emit(initial);
      _links.uriLinkStream.listen(_emit, onError: (Object e) {
        AppLogger.error('딥링크 스트림 오류', error: e);
      });
    } catch (e, st) {
      // 딥링크가 안 되는 것은 불편이지 장애가 아니다. 앱은 계속 떠야 한다.
      AppLogger.error('딥링크 초기화 실패', error: e, stack: st);
    }
  }

  void _emit(Uri uri) {
    final route = toRoute(uri);
    if (route == null) {
      AppLogger.debug('처리할 수 없는 딥링크: ${uri.scheme}://${uri.host}${uri.path}');
      return;
    }
    _controller.add(route);
  }

  /// 외부 URI → 앱 내부 경로.
  ///
  /// 받아들이는 형태:
  ///   me.popol.onpar://worksheet/{id}?quiz={quizId}
  ///   https://onpar.app/worksheet/{id}
  ///   me.popol.onpar://reset-password        (비밀번호 재설정 메일)
  ///   me.popol.onpar://login-callback        (이메일 인증 완료)
  ///   me.popol.onpar://review
  static String? toRoute(Uri uri) {
    final isOurs = uri.scheme == Env.appScheme ||
        (uri.scheme == 'https' && uri.host == Env.universalLinkHost);
    if (!isOurs) return null;

    // 커스텀 스킴은 host 가 첫 조각이고, https 는 path 가 첫 조각이다. 둘을 같게 만든다.
    final segments = <String>[
      if (uri.scheme != 'https' && uri.host.isNotEmpty) uri.host,
      ...uri.pathSegments.where((s) => s.isNotEmpty),
    ];
    if (segments.isEmpty) return Routes.home;

    switch (segments.first) {
      case 'worksheet':
        if (segments.length < 2) return Routes.library;
        final quiz = uri.queryParameters['quiz'];
        return '${Routes.worksheet(segments[1])}${quiz == null ? '' : '?quiz=$quiz'}';
      case 'review':
        return Routes.reviewSession;
      case 'reset-password':
        return Routes.resetPassword;
      case 'login-callback':
        return Routes.home;
      case 'paywall':
        return Routes.paywall;
      case 'notices':
        return Routes.notices;
      case 'settings':
        return Routes.settings;
      default:
        return null;
    }
  }

  void dispose() => _controller.close();
}

final deepLinkServiceProvider = Provider<DeepLinkService>((ref) {
  final s = DeepLinkService(AppLinks());
  ref.onDispose(s.dispose);
  return s;
});

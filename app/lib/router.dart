import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/boot_redirect.dart';
import 'core/bootstrap.dart';
import 'core/deep_links.dart';
import 'core/env.dart';
import 'core/logger.dart';
import 'core/routes.dart';
import 'core/version_gate.dart';
import 'data/supabase.dart';

/// 앱의 문지기.
///
/// "어디로 보낼지" 를 화면마다 판단하면 반드시 어긋난다. 판정은 여기 한 곳에서만 한다.
/// 순서: 설정 없음 → 점검/강제 업데이트 → 첫 실행 → 약관 → 로그인 → 원래 가려던 곳.
///
/// 마지막 조각이 중요하다. 로그인이 필요해서 막았으면 **목적지를 기억**했다가
/// 로그인 뒤에 그리로 보낸다. 안 그러면 알림을 눌러 들어온 사람이 홈에 떨어진다.
final routerProvider = Provider<GoRouter>((ref) {
  final notifier = _RouterRefresh(ref);
  ref.onDispose(notifier.dispose);

  return GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: notifier,
    debugLogDiagnostics: false,
    redirect: (context, state) => _redirect(ref, state),
    routes: _routes(ref),
    errorBuilder: (context, state) => _RouteNotFound(location: state.uri.toString()),
  );
});

String? _redirect(Ref ref, GoRouterState state) {
  final links = ref.read(deepLinkServiceProvider);
  final flags = ref.read(localFlagsProvider);

  // 판정은 순수 함수가 한다(boot_redirect.dart). 여기서는 값을 모아 주고 결과를 실행만 한다.
  // 그래야 이 순서를 앱을 띄우지 않고 시험할 수 있다 — test/boot_redirect_test.dart
  final decision = bootRedirect(BootInput(
    location: state.uri.toString(),
    configured: Env.isConfigured,
    gate: ref.read(appGateProvider).valueOrNull,
    onboarded: flags.onboarded,
    consented: flags.consent?.requiredAccepted == true,
    signedIn: ref.read(currentUserProvider) != null,
    pending: links.peekPending(),
  ));

  if (decision.holdLocation != null) links.hold(decision.holdLocation!);
  if (decision.consumePending) links.takePending();
  return decision.redirect;
}

/// 세션·관문·플래그가 바뀌면 리다이렉트를 다시 계산한다.
class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(this._ref) {
    _subs.add(_ref.listen(authStateProvider, (_, __) => notifyListeners()));
    _subs.add(_ref.listen(appGateProvider, (_, __) => notifyListeners()));
  }

  final Ref _ref;
  final _subs = <ProviderSubscription<Object?>>[];

  @override
  void dispose() {
    for (final s in _subs) {
      s.close();
    }
    super.dispose();
  }
}

class _RouteNotFound extends StatelessWidget {
  const _RouteNotFound({required this.location});
  final String location;

  @override
  Widget build(BuildContext context) {
    AppLogger.debug('없는 경로: $location');
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('찾을 수 없는 화면이에요.', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => context.go(Routes.home),
                  child: const Text('홈으로'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:onpar_design_system/onpar_design_system.dart';

import 'core/analytics.dart';
import 'core/analytics_observer.dart';
import 'core/boot_redirect.dart';
import 'core/bootstrap.dart';
import 'core/deep_links.dart';
import 'core/env.dart';
import 'core/logger.dart';
import 'core/notifications.dart';
import 'core/routes.dart';
import 'core/version_gate.dart';
import 'data/supabase.dart';
import 'features/auth/find_account_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/reset_password_screen.dart';
import 'features/auth/signup_screen.dart';
import 'features/auth/verify_screen.dart';
import 'features/consent/consent_screen.dart';
import 'features/create/create_progress_screen.dart';
import 'features/create/create_screen.dart';
import 'features/gate/gate_screen.dart';
import 'features/home/home_screen.dart';
import 'features/home/home_shell.dart';
import 'features/legal/legal_document_screen.dart';
import 'features/legal/licenses_screen.dart';
import 'features/library/library_screen.dart';
import 'features/notices/notice_list_screen.dart';
import 'features/notifications/notification_list_screen.dart';
import 'features/notifications/notification_settings_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/paywall/paywall_screen.dart';
import 'features/paywall/purchase_history_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/review/review_session_screen.dart';
import 'features/settings/account_screen.dart';
import 'features/settings/change_password_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/splash/splash_screen.dart';
import 'features/stats/stats_screen.dart';
import 'features/support/contact_screen.dart';
import 'features/support/faq_screen.dart';
import 'features/support/support_screen.dart';
import 'features/withdraw/withdraw_screen.dart';
import 'features/worksheet/worksheet_screen.dart';

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

  final router = GoRouter(
    navigatorKey: _rootKey,
    initialLocation: Routes.splash,
    refreshListenable: notifier,
    debugLogDiagnostics: false,
    // 화면 조회는 여기서 한 번만 잡는다. 화면마다 부르게 하면 반드시 빠뜨리는 화면이 생긴다.
    observers: [AnalyticsRouteObserver(ref.read(analyticsProvider))],
    redirect: (context, state) => _redirect(ref, state),
    routes: _routes(ref),
    errorBuilder: (context, state) => _RouteNotFound(location: state.uri.toString()),
  );

  // 알림을 눌러 들어온 길. 로그인 전이면 보류함에 담아 두고 로그인 뒤에 그리로 보낸다 —
  // 안 그러면 복습 알림을 눌렀는데 홈에 떨어진다.
  void follow(String route) {
    final signedIn = ref.read(currentUserProvider) != null;
    if (!signedIn && !Routes.isPublic(route)) {
      ref.read(deepLinkServiceProvider).hold(route);
      router.go(Routes.login);
      return;
    }
    router.go(route);
  }

  final linkSub = ref.read(deepLinkServiceProvider).stream.listen(follow);
  final notifySub = ref.read(notificationServiceProvider).onOpenRoute.listen(follow);
  ref.onDispose(() {
    unawaited(linkSub.cancel());
    unawaited(notifySub.cancel());
  });

  return router;
});

/// 아래에서 올라오는 페이지. 나머지 화면은 테마의 [DsPageTransitionsBuilder] 가 맡는다 —
/// 전환을 화면마다 정하면 반드시 어긋나므로, 여기 예외는 시트뿐이다.
CustomTransitionPage<void> _sheetPage(GoRouterState state, Widget child) => CustomTransitionPage(
      key: state.pageKey,
      transitionDuration: DsMotion.slow,
      // 닫히는 것은 열리는 것보다 빠르다.
      reverseTransitionDuration: DsMotion.base,
      child: child,
      transitionsBuilder: (context, animation, secondary, child) =>
          const DsSheetTransitionsBuilder()
              .buildTransitions<void>(null, context, animation, secondary, child),
    );

String? _redirect(Ref ref, GoRouterState state) {
  final links = ref.read(deepLinkServiceProvider);

  // 로컬 설정을 아직 못 읽었으면 판정할 수 없다. 스플래시에 머문다.
  // 예전에는 여기서 requireValue 를 불러 앱이 켜지자마자 죽었다 —
  // 첫 프레임에는 FutureProvider 가 아직 AsyncLoading 이다.
  final prefs = ref.read(sharedPrefsProvider);
  if (!prefs.hasValue) {
    return state.uri.path == Routes.splash ? null : Routes.splash;
  }
  final flags = ref.read(localFlagsProvider);

  // 판정은 순수 함수가 한다(boot_redirect.dart). 여기서는 값을 모아 주고 결과를 실행만 한다.
  // 그래야 이 순서를 앱을 띄우지 않고 시험할 수 있다 — test/boot_redirect_test.dart
  final decision = bootRedirect(BootInput(
    location: state.uri.toString(),
    configured: Env.isConfigured,
    gate: ref.read(appGateProvider).valueOrNull,
    onboarded: flags.onboarded,
    // 버전까지 본다. 약관이 바뀌면 동의를 다시 받아야 한다(ConsentRecord.isCurrent).
    consented: flags.consent?.isCurrent == true,
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
    // 설정을 다 읽으면 판정을 다시 돌린다 — 안 그러면 스플래시에 갇힌다.
    _subs.add(_ref.listen(sharedPrefsProvider, (_, __) => notifyListeners()));
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

/// 탭 네비게이션을 유지해야 해서 각 탭이 자기 Navigator 를 갖는다.
/// 그래야 서재에서 학습지를 열고 복습 탭에 갔다 돌아와도 있던 자리가 남는다.
final _rootKey = GlobalKey<NavigatorState>();

List<RouteBase> _routes(Ref ref) => [
      GoRoute(path: Routes.splash, builder: (_, __) => const SplashScreen()),
      GoRoute(
        path: Routes.gate,
        builder: (_, __) {
          final gate = ref.read(appGateProvider).valueOrNull ?? AppGate.pass;
          return GateScreen(gate: gate);
        },
      ),
      GoRoute(path: Routes.onboarding, builder: (_, __) => const OnboardingScreen()),
      GoRoute(path: Routes.consent, builder: (_, __) => const ConsentScreen()),

      GoRoute(path: Routes.login, builder: (_, __) => const LoginScreen()),
      GoRoute(path: Routes.signup, builder: (_, __) => const SignupScreen()),
      GoRoute(
        path: Routes.verify,
        builder: (_, state) {
          final args = state.extra;
          // 딥링크로 직접 들어오면 extra 가 없다. 그때는 이메일 안내로 떨어뜨린다 —
          // 빈 화면을 보여주거나 죽는 것보다 낫다.
          return args is VerifyArgs
              ? VerifyScreen.fromArgs(args)
              : const VerifyScreen(mode: VerifyMode.email, target: '');
        },
      ),
      GoRoute(path: Routes.findAccount, builder: (_, __) => const FindAccountScreen()),
      GoRoute(path: Routes.resetPassword, builder: (_, __) => const ResetPasswordScreen()),

      GoRoute(path: Routes.terms, builder: (_, __) => const LegalDocumentScreen(doc: LegalDoc.terms)),
      GoRoute(path: Routes.privacy, builder: (_, __) => const LegalDocumentScreen(doc: LegalDoc.privacy)),
      GoRoute(path: Routes.licenses, builder: (_, __) => const LicensesScreen()),
      GoRoute(path: Routes.support, builder: (_, __) => const SupportScreen()),
      GoRoute(path: Routes.faq, builder: (_, __) => const FaqScreen()),
      GoRoute(path: Routes.contact, builder: (_, __) => const ContactScreen()),

      // 학습지 뷰어는 탭 위에 통째로 올라온다. 필기 중에 탭 막대가 보이면 손이 닿는다.
      GoRoute(
        path: Routes.worksheetPattern,
        parentNavigatorKey: _rootKey,
        builder: (_, state) => WorksheetScreen(
          worksheetId: state.pathParameters['id']!,
          quizId: state.uri.queryParameters['quiz'] ?? state.uri.queryParameters['quizId'],
        ),
      ),
      GoRoute(
        path: Routes.create,
        parentNavigatorKey: _rootKey,
        builder: (_, state) => CreateScreen(initialTopic: state.uri.queryParameters['topic']),
        routes: [
          GoRoute(
            path: 'progress/:id',
            parentNavigatorKey: _rootKey,
            builder: (_, state) => CreateProgressScreen(worksheetId: state.pathParameters['id']!),
          ),
        ],
      ),
      GoRoute(
        path: Routes.reviewSession,
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const ReviewSessionScreen(),
      ),
      // 결제는 **잠깐 얹히는 화면**이다. 밀려 들어오면 "다음 단계" 로 읽히고,
      // 아래에서 올라오면 "여기서 결정하고 돌아간다" 로 읽힌다(iOS 시트).
      GoRoute(
        path: Routes.paywall,
        parentNavigatorKey: _rootKey,
        pageBuilder: (_, state) => _sheetPage(state, const PaywallScreen()),
      ),
      GoRoute(path: Routes.notifications, builder: (_, __) => const NotificationListScreen()),
      // 공지는 **로그인 전에도** 열려야 한다(publicPaths). 점검 공지가 필요한 순간이
      // 바로 로그인이 안 되는 순간이다.
      GoRoute(path: Routes.notices, builder: (_, __) => const NoticeListScreen()),
      GoRoute(path: Routes.stats, builder: (_, __) => const StatsScreen()),

      StatefulShellRoute.indexedStack(
        builder: (_, __, shell) => HomeShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.home, builder: (_, __) => const HomeScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.library, builder: (_, __) => const LibraryScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.reviewTab, builder: (_, __) => const ReviewSessionScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.settings,
              builder: (_, __) => const SettingsScreen(),
              routes: [
                GoRoute(path: 'profile', builder: (_, __) => const ProfileScreen()),
                GoRoute(path: 'notifications', builder: (_, __) => const NotificationSettingsScreen()),
                GoRoute(path: 'purchases', builder: (_, __) => const PurchaseHistoryScreen()),
                GoRoute(
                  path: 'account',
                  builder: (_, __) => const AccountScreen(),
                  routes: [
                    GoRoute(path: 'password', builder: (_, __) => const ChangePasswordScreen()),
                    GoRoute(path: 'withdraw', builder: (_, __) => const WithdrawScreen()),
                  ],
                ),
              ],
            ),
          ]),
        ],
      ),
    ];

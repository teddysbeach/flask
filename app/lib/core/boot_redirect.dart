import 'routes.dart';
import 'version_gate.dart';

/// 앱을 켰을 때 어디로 보낼지. **순수 함수**로 떼어 둔다.
///
/// 이 판정은 조건이 여섯 개고 순서가 있어서 실제로 가장 자주 어긋나는 곳이다.
/// 위젯 안에 두면 시험하려고 앱을 띄워야 하고, 그러면 아무도 시험하지 않는다.
class BootInput {
  const BootInput({
    required this.location,
    required this.configured,
    required this.gate,
    required this.onboarded,
    required this.consented,
    required this.signedIn,
    this.pending,
  });

  final String location;
  final bool configured;
  final AppGate? gate;
  final bool onboarded;
  final bool consented;
  final bool signedIn;

  /// 로그인 때문에 미뤄 둔 목적지.
  final String? pending;

  String get path => Uri.parse(location).path;
}

/// 돌려줄 곳. null 이면 그대로 둔다.
class BootDecision {
  const BootDecision(this.redirect, {this.consumePending = false, this.holdLocation});

  final String? redirect;

  /// 보류함에서 목적지를 꺼내 썼는가(호출자가 실제로 비워야 한다).
  final bool consumePending;

  /// 로그인 때문에 막았으니 이 경로를 보류함에 담아라.
  final String? holdLocation;

  static const stay = BootDecision(null);
}

BootDecision bootRedirect(BootInput i) {
  final path = i.path;

  // 1. 설정이 없으면 아무 것도 못 한다. 조용히 빈 화면을 보여주지 않는다.
  if (!i.configured) return path == Routes.gate ? BootDecision.stay : const BootDecision(Routes.gate);

  // 2. 서버가 막았는가. 서버를 못 불렀으면(gate == null) 통과다 —
  //    우리 실수 하나로 앱 전체가 안 열리는 쪽이 훨씬 나쁘다.
  final blocked = i.gate != null &&
      (i.gate!.decision == GateDecision.maintenance || i.gate!.decision == GateDecision.forceUpdate);
  if (blocked) return path == Routes.gate ? BootDecision.stay : const BootDecision(Routes.gate);
  if (path == Routes.gate) return const BootDecision(Routes.splash);

  // 3. 첫 실행 · 약관. 기기 단위라 로그아웃해도 다시 보지 않는다.
  if (!i.onboarded) {
    return path == Routes.onboarding ? BootDecision.stay : const BootDecision(Routes.onboarding);
  }
  if (!i.consented) {
    return path == Routes.consent ? BootDecision.stay : const BootDecision(Routes.consent);
  }

  // 4. 세션.
  final isPublic = Routes.isPublic(i.location);
  if (!i.signedIn) {
    if (isPublic) return BootDecision.stay;
    // 가려던 곳을 기억한다. 이게 없으면 알림을 눌러 들어온 사람이 로그인 뒤 홈에 떨어진다.
    return BootDecision(Routes.login, holdLocation: i.location);
  }

  // 5. 로그인한 사람이 스플래시·인증 화면에 머무를 이유가 없다.
  final atEntry = path == Routes.splash || path.startsWith('/auth') || path == Routes.consent;
  if (atEntry) {
    final pending = i.pending;
    if (pending != null && pending.isNotEmpty) {
      return BootDecision(pending, consumePending: true);
    }
    return const BootDecision(Routes.home);
  }

  return BootDecision.stay;
}

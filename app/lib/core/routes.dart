/// 경로 상수. 문자열을 화면마다 적으면 오타가 런타임까지 살아남는다.
///
/// 딥링크(푸시·이메일·웹)도 전부 이 경로로 들어온다 — 그래서 한곳에 모아 둔다.
class Routes {
  const Routes._();

  static const splash = '/';
  static const gate = '/gate';              // 점검 · 강제 업데이트
  static const onboarding = '/onboarding';
  static const consent = '/consent';

  static const login = '/auth/login';
  static const signup = '/auth/signup';
  static const verify = '/auth/verify';     // 이메일·휴대폰 인증
  static const findAccount = '/auth/find';
  static const resetPassword = '/auth/reset';

  static const home = '/home';
  static const library = '/library';
  static const reviewTab = '/review';
  static const settings = '/settings';

  static const create = '/create';
  static String createProgress(String id) => '/create/progress/$id';
  static String worksheet(String id) => '/worksheet/$id';
  static const worksheetPattern = '/worksheet/:id';

  static const reviewSession = '/review/session';
  static const notifications = '/notifications';
  static const notificationSettings = '/settings/notifications';

  static const profile = '/settings/profile';
  static const accountSettings = '/settings/account';
  static const changePassword = '/settings/account/password';
  static const withdraw = '/settings/account/withdraw';

  static const paywall = '/paywall';
  static const purchases = '/settings/purchases';

  static const support = '/support';
  static const faq = '/support/faq';
  static const contact = '/support/contact';

  static const terms = '/legal/terms';
  static const privacy = '/legal/privacy';
  static const licenses = '/legal/licenses';
  static const notices = '/notices';

  /// 로그인이 필요 없는 곳. 나머지는 전부 세션이 있어야 한다.
  static const publicPaths = <String>{
    splash, gate, onboarding, consent,
    login, signup, verify, findAccount, resetPassword,
    terms, privacy, licenses, support, faq, contact,
  };

  static bool isPublic(String location) {
    final path = Uri.parse(location).path;
    return publicPaths.contains(path);
  }
}

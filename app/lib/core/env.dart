/// 빌드 시점 설정. 비밀은 여기 없다.
///
/// Anthropic 키는 서버(Edge Function secret)에만 있고 앱은 그 근처에도 안 간다.
/// Supabase anon 키는 공개되어도 되는 값이지만(RLS 가 실제 방어선), 그래도
/// 소스에 박지 않고 `--dart-define` 으로 주입해 환경별로 갈아끼운다.
///
///   flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
class Env {
  const Env._();

  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// 딥링크 스킴. 이메일 인증 링크와 OAuth 리다이렉트가 앱으로 돌아오는 통로.
  static const appScheme = String.fromEnvironment('APP_SCHEME', defaultValue: 'me.popol.onpar');
  static const universalLinkHost =
      String.fromEnvironment('UNIVERSAL_LINK_HOST', defaultValue: 'onpar.app');

  static const termsUrl = String.fromEnvironment('TERMS_URL', defaultValue: 'https://onpar.app/terms');
  static const privacyUrl =
      String.fromEnvironment('PRIVACY_URL', defaultValue: 'https://onpar.app/privacy');
  /// Google 로그인 클라이언트 id. 플랫폼마다 다르다.
  ///
  /// iOS 는 이 값이 **없으면 시작조차 못 한다.** Info.plist 에 GIDClientID 를 두는 길도
  /// 있지만 지금 그것도 없다 — 즉 값이 비어 있으면 Google 버튼은 눌러도 아무 일이 안 난다.
  /// 그래서 [isGoogleSignInConfigured] 로 버튼 자체를 감춘다.
  ///
  /// 값이 생기면 **Info.plist 에 역방향 클라이언트 ID URL 스킴도 함께** 넣어야 한다.
  /// 그게 없으면 구글 화면에서 앱으로 돌아오지 못한다(docs/plan/17-release-ops.md).
  static const googleIosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');
  static const googleServerClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  /// Google 로그인을 **띄워도 되는가.**
  ///
  /// iOS 의 google_sign_in 은 클라이언트 ID 없이는 시작조차 못 한다. 값이 없는 빌드에서
  /// 버튼만 보여주면 누를 때마다 알 수 없는 오류가 뜬다 — Apple 로그인을 안드로이드에서
  /// 숨기는 것과 같은 이유다. **안 되는 버튼을 두는 편이 언제나 더 나쁘다.**
  static bool get isGoogleSignInConfigured =>
      googleIosClientId.isNotEmpty || googleServerClientId.isNotEmpty;

  /// 빈 문자열은 "안 넘긴 것" 과 같다. google_sign_in 은 null 을 받아야 기본값으로 간다.
  static String? get googleIosClientIdOrNull =>
      googleIosClientId.isEmpty ? null : googleIosClientId;
  static String? get googleServerClientIdOrNull =>
      googleServerClientId.isEmpty ? null : googleServerClientId;

  static const supportEmail =
      String.fromEnvironment('SUPPORT_EMAIL', defaultValue: 'help@onpar.app');

  /// 설정이 비어 있으면 앱은 뜨지만 서버를 못 부른다. 조용히 실패하지 않고 점검 화면을 띄운다.
  static bool get isConfigured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}

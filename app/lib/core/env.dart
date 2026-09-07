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
  /// 없으면 google_sign_in 이 플랫폼 설정 파일에서 찾는다 — 그래서 비어 있어도 동작할 수 있다.
  static const googleIosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');
  static const googleServerClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  static String? get googleIosClientIdOrNull =>
      googleIosClientId.isEmpty ? null : googleIosClientId;
  static String? get googleServerClientIdOrNull =>
      googleServerClientId.isEmpty ? null : googleServerClientId;

  static const supportEmail =
      String.fromEnvironment('SUPPORT_EMAIL', defaultValue: 'help@onpar.app');

  /// 설정이 비어 있으면 앱은 뜨지만 서버를 못 부른다. 조용히 실패하지 않고 점검 화면을 띄운다.
  static bool get isConfigured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}

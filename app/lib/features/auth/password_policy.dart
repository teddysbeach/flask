/// 비밀번호 규칙. 화면이 아니라 여기 한 곳에만 있다.
///
/// 가입과 재설정이 서로 다른 규칙을 들고 있으면, 가입은 통과했는데 재설정에서
/// 막히는 계정이 생긴다. 그래서 검사는 순수 함수 하나로 두고 두 화면이 같이 쓴다.
/// (서버도 같은 최소치를 걸지만, 앱이 먼저 알려줘야 사용자가 왕복하지 않는다.)
library;

/// 규칙 한 줄. 화면은 `met` 에 따라 체크 아이콘을 바꾼다 —
/// 색만으로 표시하면 색을 구분 못 하는 사용자에게는 아무 정보도 아니다.
typedef PasswordRule = ({String label, bool met});

/// 검사 결과. `ok` 가 true 여야 제출할 수 있다.
typedef PasswordCheck = ({bool ok, List<PasswordRule> rules});

class PasswordPolicy {
  const PasswordPolicy._();

  /// 최소 길이.
  static const minLength = 8;

  /// 최대 길이. bcrypt 가 72바이트에서 잘라 먹는 구현이 있어 그 위는 아예 막는다.
  /// (길이를 안 막으면 "가입은 됐는데 로그인이 안 되는" 계정이 생긴다.)
  static const maxLength = 72;

  /// 섞어야 하는 문자 종류의 최소 가짓수.
  static const minKinds = 2;

  static final _letter = RegExp(r'[A-Za-z]');
  static final _digit = RegExp(r'[0-9]');

  /// 영문·숫자·공백이 아닌 모든 문자를 '기호'로 센다.
  /// 한글이나 이모지도 여기 들어간다 — 종류를 늘려 주는 쪽이 사용자에게 유리하다.
  static final _symbol = RegExp(r'[^A-Za-z0-9\s]');

  /// 영문/숫자/기호 중 몇 종류를 썼는지(0~3).
  static int kindCount(String password) {
    var n = 0;
    if (_letter.hasMatch(password)) n++;
    if (_digit.hasMatch(password)) n++;
    if (_symbol.hasMatch(password)) n++;
    return n;
  }

  /// 규칙 검사. 화면은 이 결과만 그린다.
  ///
  /// 길이는 코드 유닛이 아니라 **문자(룬)** 로 센다. 이모지 하나를 2자로 세면
  /// 사용자가 보는 길이와 앱이 세는 길이가 어긋난다.
  static PasswordCheck check(String password) {
    final length = password.runes.length;
    final rules = <PasswordRule>[
      (label: '$minLength자 이상', met: length >= minLength),
      (label: '영문 · 숫자 · 기호 중 $minKinds가지 이상', met: kindCount(password) >= minKinds),
      (label: '$maxLength자 이하', met: length <= maxLength),
    ];
    return (ok: rules.every((r) => r.met), rules: rules);
  }

  /// 두 번 입력이 같은지. 앞뒤 공백을 다듬지 않는다 — 비밀번호의 공백은 내용이다.
  static bool matches(String password, String confirm) =>
      password.isNotEmpty && password == confirm;
}

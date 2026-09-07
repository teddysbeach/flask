/// ONPAR 디자인 시스템.
///
/// 토큰과 아이콘은 `design/design_tokens.json` 과 `design/build_icons.mjs` 가 만든다.
/// 이 패키지는 그 생성물을 Flutter 쪽에서 쓰기 좋게 감싸기만 한다 —
/// 값을 여기서 고치면 학습지 HTML(CSS 토큰)과 앱이 갈라진다.
library;

export 'src/tokens/tokens.g.dart';
export 'src/tokens/icons.g.dart';
export 'src/tokens/brand.g.dart';
export 'src/brand.dart';
export 'src/ds_icon.dart';
export 'src/theme.dart';

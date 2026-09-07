// design/build_brand.mjs 가 만든 파일. 손으로 고치지 마세요.
//
// 심볼: 원 하나(사람) 아래 길이가 같은 줄 두 개. par = 동등, 그리고 학습지의 줄.
// 워드마크: "온파" — 원과 사각형만으로 세운 기하 레터링(폰트에 기대지 않는다).

/// 브랜드 도형. 색은 `currentColor` 라 쓰는 쪽이 정한다.
class DsBrand {
  const DsBrand._();

  /// 심볼 비율 — 가로:세로 = 1:2.
  static const double symbolAspect = 288 / 576;

  /// 워드마크 비율 — 가로:세로.
  static const double wordmarkAspect = 752 / 360;

  static const String symbol = r'''<svg xmlns="http://www.w3.org/2000/svg" width="288" height="576" viewBox="368 224 288 576">
  <circle cx="512" cy="368" r="106" fill="none" stroke="currentColor" stroke-width="76"/>
  <rect x="368" y="600" width="288" height="72" rx="36" fill="currentColor"/>
  <rect x="368" y="728" width="288" height="72" rx="36" fill="currentColor"/>
</svg>''';

  static const String wordmark = r'''<svg xmlns="http://www.w3.org/2000/svg" width="752" height="360" viewBox="0 0 752 360">
  <circle cx="160" cy="100" r="49" fill="none" stroke="currentColor" stroke-width="46"/>
  <rect x="137" y="190" width="46" height="38" rx="19" fill="currentColor"/>
  <rect x="0" y="224" width="320" height="46" rx="23" fill="currentColor"/>
  <rect x="24" y="288" width="46" height="72" rx="23" fill="currentColor"/>
  <rect x="24" y="314" width="266" height="46" rx="23" fill="currentColor"/>
  <rect x="372" y="78" width="238" height="46" rx="23" fill="currentColor"/>
  <rect x="372" y="250" width="238" height="46" rx="23" fill="currentColor"/>
  <rect x="422" y="116" width="46" height="142" rx="23" fill="currentColor"/>
  <rect x="514" y="116" width="46" height="142" rx="23" fill="currentColor"/>
  <rect x="640" y="56" width="46" height="274" rx="23" fill="currentColor"/>
  <rect x="686" y="172" width="66" height="46" rx="23" fill="currentColor"/>
</svg>''';
}

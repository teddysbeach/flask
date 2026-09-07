import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'theme.dart';
import 'tokens/brand.g.dart';

/// 브랜드 심볼 — 원 하나(사람) 아래 **길이가 같은 줄 두 개**.
///
/// 이름의 절반인 par(동등한)가 두 줄이 같은 길이인 데 있고, 같은 두 줄은 학습지의 줄이기도 하다.
/// 그래서 이 마크는 브랜드 문장을 그대로 그린 것이다 — "모두가 같은 자리에서 배운다."
///
/// 색은 인자로 받되 기본은 브랜드 색이다. 도형은 `design/build_brand.mjs` 가 만든다 —
/// 여기서 좌표를 손보면 앱 아이콘·스플래시와 갈라진다.
class OnparSymbol extends StatelessWidget {
  const OnparSymbol({super.key, this.height = 48, this.color, this.semanticLabel});

  /// 세로 크기. 가로는 비율(1:2)로 따라온다.
  final double height;
  final Color? color;

  /// 스크린리더가 읽을 이름. 로고 옆에 이름이 이미 있으면 null 로 둔다.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = color ?? DsTheme.of(context).brandPrimary;
    final picture = SvgPicture.string(
      DsBrand.symbol,
      height: height,
      width: height * DsBrand.symbolAspect,
      theme: SvgTheme(currentColor: c),
    );
    return semanticLabel == null
        ? ExcludeSemantics(child: picture)
        : Semantics(label: semanticLabel, image: true, child: picture);
  }
}

/// 워드마크 "온파".
///
/// 폰트로 쓰지 않고 도형으로 둔 이유가 있다. 앱이 폰트를 번들하지 않아서
/// iOS 는 Apple SD Gothic Neo, Android 는 Noto Sans KR 로 그린다 —
/// 그러면 같은 이름이 기기마다 다른 글자가 된다. 로고는 어디서나 같아야 한다.
class OnparWordmark extends StatelessWidget {
  const OnparWordmark({super.key, this.height = 24, this.color, this.semanticLabel = '온파'});

  final double height;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = color ?? DsTheme.of(context).brandPrimary;
    final picture = SvgPicture.string(
      DsBrand.wordmark,
      height: height,
      width: height * DsBrand.wordmarkAspect,
      theme: SvgTheme(currentColor: c),
    );
    return semanticLabel == null
        ? ExcludeSemantics(child: picture)
        : Semantics(label: semanticLabel, image: true, child: picture);
  }
}

/// 로고 배치.
enum OnparLogoLayout {
  /// 심볼 위, 이름 아래. 스플래시·온보딩처럼 화면 한가운데 놓을 때.
  stacked,

  /// 심볼 왼쪽, 이름 오른쪽. 앱바나 좁은 자리.
  inline,
}

/// 심볼 + 워드마크. 둘의 비율과 사이 간격을 여기서만 정한다 —
/// 화면마다 눈대중으로 맞추면 같은 로고가 화면마다 다른 물건이 된다.
class OnparLogo extends StatelessWidget {
  const OnparLogo({
    super.key,
    this.layout = OnparLogoLayout.stacked,
    this.symbolHeight = 88,
    this.color,
  });

  /// 심볼의 세로 크기. 워드마크와 간격은 여기서 비례로 정해진다.
  final double symbolHeight;
  final OnparLogoLayout layout;
  final Color? color;

  // 시안에서 고른 값. 눈으로 맞춘 비율이라 숫자에 뜻은 없고, 대신 한곳에만 있다.
  static const double _wordmarkRatio = 0.55;
  static const double _stackedGapRatio = 0.12;
  static const double _inlineGapRatio = 0.28;

  @override
  Widget build(BuildContext context) {
    final c = color ?? DsTheme.of(context).brandPrimary;
    final symbol = OnparSymbol(height: symbolHeight, color: c);
    final wordmark = OnparWordmark(
      height: symbolHeight * (layout == OnparLogoLayout.stacked ? _wordmarkRatio : 0.62),
      color: c,
      semanticLabel: null,
    );
    final gap = symbolHeight *
        (layout == OnparLogoLayout.stacked ? _stackedGapRatio : _inlineGapRatio);

    return Semantics(
      label: '온파',
      image: true,
      child: ExcludeSemantics(
        child: layout == OnparLogoLayout.stacked
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [symbol, SizedBox(height: gap), wordmark],
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [symbol, SizedBox(width: gap), wordmark],
              ),
      ),
    );
  }
}

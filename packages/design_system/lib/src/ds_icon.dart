import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'tokens/icons.g.dart';

/// Untitled UI 아이콘 하나. path 문자열은 생성물(`icons.g.dart`)에서 온다.
///
/// 아이콘은 언제나 `currentColor` 처럼 굴어야 한다 — 색을 인자로 받지 않고
/// 기본은 주변 텍스트 색을 따른다. 그래야 디자인 시스템을 갈아끼워도 따라간다.
class DsIcon extends StatelessWidget {
  const DsIcon(
    this.paths, {
    super.key,
    this.size = 20,
    this.color,
    this.semanticLabel,
  });

  final List<String> paths;
  final double size;
  final Color? color;

  /// 스크린리더가 읽을 이름. 장식용 아이콘이면 null 로 두어 읽지 않게 한다.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = color ?? DefaultTextStyle.of(context).style.color ?? const Color(0xFF1A1C20);
    final svg = StringBuffer()
      ..write('<svg xmlns="http://www.w3.org/2000/svg" width="${DsIcons.viewBox}" '
          'height="${DsIcons.viewBox}" viewBox="0 0 ${DsIcons.viewBox} ${DsIcons.viewBox}" '
          'fill="none" stroke="${_hex(c)}" stroke-width="${DsIcons.strokeWidth}" '
          'stroke-linecap="round" stroke-linejoin="round">');
    for (final d in paths) {
      svg.write('<path d="$d"/>');
    }
    svg.write('</svg>');

    final picture = SvgPicture.string(svg.toString(), width: size, height: size);
    if (semanticLabel == null) {
      return ExcludeSemantics(child: picture);
    }
    return Semantics(label: semanticLabel, image: true, child: picture);
  }

  static String _hex(Color c) {
    int ch(double v) => (v * 255).round().clamp(0, 255);
    return '#${ch(c.r).toRadixString(16).padLeft(2, '0')}'
        '${ch(c.g).toRadixString(16).padLeft(2, '0')}'
        '${ch(c.b).toRadixString(16).padLeft(2, '0')}';
  }
}

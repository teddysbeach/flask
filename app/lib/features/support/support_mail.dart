/// 문의 메일 만들기.
///
/// 제목에 앱 버전과 플랫폼을 미리 넣는 이유는, 그게 없으면 우리가 첫 답장으로
/// "버전이 어떻게 되시나요" 를 묻게 되기 때문이다. 왕복 한 번이 하루를 잡아먹는다.
///
/// **사용자 식별자(이메일·계정 ID·기기 ID)는 넣지 않는다.** 메일은 어디로든 전달되고,
/// 우리가 안 물어봐도 되는 것을 본문에 박아 두면 그 순간부터 우리 책임이 된다.
/// 어느 계정인지는 보내는 사람의 메일 주소로 이미 충분하다.
library;

import 'package:flutter/foundation.dart';

class SupportMail {
  const SupportMail._();

  /// 현재 플랫폼 이름. 메일 제목에 쓴다.
  static String platformLabel([TargetPlatform? platform]) =>
      switch (platform ?? defaultTargetPlatform) {
        TargetPlatform.iOS => 'iOS',
        TargetPlatform.android => 'Android',
        TargetPlatform.macOS => 'macOS',
        TargetPlatform.windows => 'Windows',
        TargetPlatform.linux => 'Linux',
        TargetPlatform.fuchsia => 'Fuchsia',
      };

  /// `mailto:` URI. 본문은 사용자가 지우고 쓸 수 있는 뼈대만 넣는다.
  static Uri build({
    required String email,
    required String version,
    required String platform,
    String? category,
    String? body,
  }) {
    final subject = category == null || category.isEmpty
        ? '[ONPAR 문의] $version · $platform'
        : '[ONPAR 문의] $category · $version · $platform';

    final text = StringBuffer()
      ..writeln(body?.trim().isNotEmpty == true ? body!.trim() : '어떤 일이 있었는지 적어 주세요.')
      ..writeln()
      ..writeln('---')
      ..writeln('앱 버전: $version')
      ..writeln('기기: $platform')
      ..writeln('(위 두 줄은 문제를 찾는 데 쓰여요. 지우지 말아 주세요.)');

    // Uri 생성자에 Map 을 넘기면 공백이 '+' 로 인코딩된다 — 메일 앱이 그걸 그대로 보여준다.
    // 그래서 직접 퍼센트 인코딩한다.
    final query = 'subject=${Uri.encodeComponent(subject)}'
        '&body=${Uri.encodeComponent(text.toString())}';
    return Uri.parse('mailto:${Uri.encodeComponent(email)}?$query');
  }
}

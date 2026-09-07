import 'package:flutter/services.dart';

import '../../core/logger.dart';

/// 학습지 WebView 가 앱 번들에서 파일을 가져올 때 쓰는 스킴.
///
/// 왜 스킴을 따로 파는가 — 학습지 HTML 에 글꼴을 base64 로 구우면 한 장에 200KB 가 붙는다.
/// 오프라인 보관(기기)과 스토리지(서버)가 같이 세 배가 되고, 얻는 것은 이미 앱이 들고 있는
/// 파일 하나의 사본이다. **앱이 한 벌만 들고 먹인다.**
///
/// 바깥으로 나가는 요청이 아니다. 앱 번들 안에서만 읽으므로 학습지의 "외부 요청 0회" 는
/// 그대로다 — 비행기 모드에서도 글꼴이 붙는다.
const kAssetScheme = 'onpar-asset';

/// 이 스킴으로 내줄 수 있는 것. **목록에 있는 것만 내준다.**
///
/// 임의 경로를 그대로 번들 경로로 만들면 학습지 HTML 한 줄로 앱 안의 아무 파일이나
/// 읽어 갈 수 있게 된다. 학습지는 우리가 만들지만, 본문에는 모델이 쓴 글이 들어간다.
const _allowed = <String, String>{
  'font/pretendard.ttf': 'assets/fonts/PretendardVariable.subset.ttf',
};

/// 학습지가 열리기 **전에** 심는 글꼴 선언.
///
/// 학습지 HTML 에는 이 선언이 없다. 그래야 저장된 문서가 앱에 의존하지 않고,
/// 앱 밖에서 열어도 콘솔 오류 없이 폴백 글꼴로 조용히 읽힌다.
/// 글꼴을 아는 것은 앱뿐이므로, 앱이 문서를 열면서 한 줄을 얹는다.
///
/// 문서가 그려지기 전(document-start)에 얹어야 첫 프레임부터 제 글꼴로 그려진다.
/// 나중에 얹으면 글자가 한 번 바뀌고, 그 리플로우는 필기 좌표계를 흔든다.
const kWorksheetFontUserScript = '''
(function () {
  var s = document.createElement('style');
  s.textContent = "@font-face{font-family:'Pretendard Variable';"
    + "src:url('$kAssetScheme://font/pretendard.ttf') format('truetype');"
    + "font-weight:45 930;font-style:normal;font-display:swap}";
  (document.head || document.documentElement).appendChild(s);
})();
''';

/// `onpar-asset://font/pretendard.ttf` → 번들 바이트. 목록에 없으면 null(=요청 실패).
///
/// **던지지 않는다.** 글꼴을 못 읽어도 학습지는 폴백 글꼴로 읽힌다 —
/// 여기서 예외를 내면 글꼴 하나 때문에 본문이 안 보인다.
Future<Uint8List?> loadWorksheetAsset(Uri? url) async {
  if (url == null || url.scheme != kAssetScheme) return null;
  // host + path 를 합친다. onpar-asset://font/pretendard.ttf 는 host='font', path='/pretendard.ttf'.
  final key = '${url.host}${url.path}'.replaceAll(RegExp(r'^/+'), '');
  final asset = _allowed[key];
  if (asset == null) {
    AppLogger.debug('학습지가 목록에 없는 자원을 요청했어요: $key');
    return null;
  }
  try {
    final data = await rootBundle.load(asset);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } catch (e, st) {
    AppLogger.error('번들 자원을 읽지 못했어요: $asset', error: e, stack: st);
    return null;
  }
}

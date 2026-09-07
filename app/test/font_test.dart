import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onpar/features/legal/licenses_screen.dart';
import 'package:onpar/features/worksheet/worksheet_assets.dart';
import 'package:onpar_design_system/onpar_design_system.dart';
import 'package:yaml/yaml.dart';

/// 글꼴이 실제로 앱에 들어 있는가.
///
/// 예전에는 토큰이 'Pretendard Variable' 이라고 부르는데 그 파일이 저장소 어디에도 없었다.
/// 앱도 학습지도 조용히 시스템 글꼴로 떨어졌고, 화면은 멀쩡해 보여서 아무도 몰랐다.
/// 그런 종류의 실수는 눈으로 못 잡는다 — 파일이 있는지, 이름이 같은지를 값으로 잰다.
void main() {
  final pubspec = loadYaml(File('pubspec.yaml').readAsStringSync()) as YamlMap;

  test('토큰이 부르는 이름의 글꼴이 pubspec 에 선언돼 있다', () {
    final families = ((pubspec['flutter'] as YamlMap)['fonts'] as YamlList)
        .map((f) => (f as YamlMap)['family'] as String)
        .toList();
    expect(families, contains(DsFont.family),
        reason: '토큰은 "${DsFont.family}" 를 쓰는데 그 글꼴이 번들에 없다');
  });

  test('선언한 글꼴 파일이 실제로 있다', () {
    final fonts = (pubspec['flutter'] as YamlMap)['fonts'] as YamlList;
    for (final f in fonts) {
      for (final v in (f as YamlMap)['fonts'] as YamlList) {
        final path = (v as YamlMap)['asset'] as String;
        final file = File(path);
        expect(file.existsSync(), isTrue, reason: '$path 가 없다');
        // 서브셋이 통째로 날아가거나 빈 파일이 커밋되는 사고를 막는다.
        expect(file.lengthSync(), greaterThan(200 * 1024), reason: '$path 가 너무 작다');
        expect(file.lengthSync(), lessThan(3 * 1024 * 1024),
            reason: '$path 가 3MB 를 넘었다 — 앱 용량을 그만큼 쓰고 있다');
      }
    }
  });

  test('OFL 전문이 함께 들어 있다', () {
    // SIL OFL 1.1 은 서브셋(파생물) 배포에도 라이선스 전문 동봉을 요구한다.
    final license = File('assets/fonts/Pretendard-OFL.txt');
    expect(license.existsSync(), isTrue);
    expect(license.readAsStringSync(), contains('SIL OPEN FONT LICENSE'));

    final assets = ((pubspec['flutter'] as YamlMap)['assets'] as YamlList).cast<String>();
    expect(assets, contains('assets/fonts/Pretendard-OFL.txt'));

    // 화면에도 표기가 있어야 한다. 파일만 넣고 안 보여주면 표기 의무를 지킨 게 아니다.
    expect(bundledNotices.map((n) => n.name), contains('Pretendard'));
  });

  group('학습지에 글꼴을 먹이는 길', () {
    test('허용 목록에 없는 경로는 내주지 않는다', () async {
      // 학습지 본문에는 모델이 쓴 글이 들어간다. 임의 경로를 그대로 번들 경로로 만들면
      // 문서 한 줄로 앱 안의 아무 파일이나 읽어 갈 수 있게 된다.
      for (final bad in [
        'onpar-asset://../../secrets.txt',
        'onpar-asset://font/../../pubspec.yaml',
        'onpar-asset://anything',
        'file:///etc/passwd',
        'https://example.com/font.ttf',
      ]) {
        expect(await loadWorksheetAsset(Uri.parse(bad)), isNull, reason: '$bad 를 내줬다');
      }
      expect(await loadWorksheetAsset(null), isNull);
    });

    testWidgets('허용된 글꼴은 번들에서 읽힌다', (tester) async {
      final bytes = await loadWorksheetAsset(Uri.parse('onpar-asset://font/pretendard.ttf'));
      expect(bytes, isNotNull);
      expect(bytes!.length, greaterThan(200 * 1024));
      // TTF 시그니처(0x00010000). 엉뚱한 파일을 글꼴이라고 내주고 있지 않은지 본다.
      expect(bytes.sublist(0, 4), [0x00, 0x01, 0x00, 0x00]);
    });

    test('심는 선언이 그 경로를 가리킨다', () {
      expect(kWorksheetFontUserScript, contains('$kAssetScheme://font/pretendard.ttf'));
      expect(kWorksheetFontUserScript, contains(DsFont.family));
      // 글꼴을 못 읽어도 글자는 즉시 보여야 한다.
      expect(kWorksheetFontUserScript, contains('font-display:swap'));
    });
  });
}

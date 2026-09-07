import 'package:flutter_test/flutter_test.dart';
import 'package:onpar/core/deep_links.dart';
import 'package:onpar/core/routes.dart';

/// 딥링크는 밖에서 들어오는 입력이라 아무 모양이나 온다.
/// 여기서 막지 못하면 앱이 이상한 화면에 떨어지거나 그냥 죽는다.
void main() {
  String? route(String uri) => DeepLinkService.toRoute(Uri.parse(uri));

  group('우리 링크', () {
    test('커스텀 스킴으로 학습지를 연다', () {
      expect(route('me.popol.onpar://worksheet/abc-123'), Routes.worksheet('abc-123'));
    });

    test('유니버설 링크로도 같은 곳에 간다', () {
      expect(route('https://onpar.app/worksheet/abc-123'), Routes.worksheet('abc-123'));
    });

    test('문제 지정이 붙으면 쿼리로 넘긴다 (복습 알림에서 그 문제로 스크롤)', () {
      expect(route('me.popol.onpar://worksheet/w1?quiz=q7'), '${Routes.worksheet('w1')}?quiz=q7');
    });

    test('복습 · 결제 · 설정 · 공지', () {
      expect(route('me.popol.onpar://review'), Routes.reviewSession);
      expect(route('me.popol.onpar://paywall'), Routes.paywall);
      expect(route('me.popol.onpar://settings'), Routes.settings);
      expect(route('me.popol.onpar://notices'), Routes.notices);
    });

    test('비밀번호 재설정 메일 링크', () {
      expect(route('me.popol.onpar://reset-password'), Routes.resetPassword);
    });

    test('이메일 인증을 마치면 홈으로', () {
      expect(route('me.popol.onpar://login-callback'), Routes.home);
    });

    test('스킴만 있으면 홈으로 (빈 링크로 죽지 않는다)', () {
      expect(route('me.popol.onpar://'), Routes.home);
    });

    test('id 없는 학습지 링크는 서재로 — 빈 상세로 보내지 않는다', () {
      expect(route('me.popol.onpar://worksheet'), Routes.library);
    });
  });

  group('남의 링크 · 이상한 링크', () {
    test('다른 앱 스킴은 받지 않는다', () {
      expect(route('otherapp://worksheet/1'), isNull);
    });

    test('다른 도메인의 https 는 받지 않는다 (피싱 링크로 앱을 열 수 없다)', () {
      expect(route('https://evil.example.com/worksheet/1'), isNull);
    });

    test('모르는 경로는 조용히 무시한다', () {
      expect(route('me.popol.onpar://unknown-thing'), isNull);
    });
  });

  group('공개 경로 판정', () {
    test('로그인 없이 볼 수 있는 곳', () {
      expect(Routes.isPublic(Routes.login), isTrue);
      expect(Routes.isPublic(Routes.terms), isTrue);
      expect(Routes.isPublic(Routes.onboarding), isTrue);
    });

    test('나머지는 세션이 필요하다', () {
      expect(Routes.isPublic(Routes.home), isFalse);
      expect(Routes.isPublic(Routes.worksheet('x')), isFalse);
      expect(Routes.isPublic(Routes.withdraw), isFalse);
    });

    test('쿼리가 붙어도 경로로 판정한다', () {
      expect(Routes.isPublic('${Routes.login}?from=/home'), isTrue);
    });
  });
}

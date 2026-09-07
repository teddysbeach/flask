import 'package:flutter_test/flutter_test.dart';
import 'package:onpar/core/logger.dart';

/// 로그는 크래시 리포트·기기 로그·문의 캡처로 빠져나간다.
/// 한 번 새면 회수할 방법이 없으므로, 가리는 규칙은 테스트로 고정한다.
void main() {
  group('개인정보 가리기', () {
    test('이메일은 앞 두 글자만 남는다', () {
      final out = AppLogger.redact('로그인 실패: hyunwoo@example.com');
      expect(out, isNot(contains('hyunwoo@example.com')));
      expect(out, contains('@example.com'));
      expect(out, contains('hy'));
    });

    test('휴대폰 번호는 가운데를 가린다', () {
      expect(AppLogger.redact('010-1234-5678'), '010-****-5678');
      expect(AppLogger.redact('01012345678'), '010-****-5678');
      expect(AppLogger.redact('010 1234 5678'), '010-****-5678');
    });

    test('JWT 는 통째로 지운다', () {
      const jwt = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N';
      final out = AppLogger.redact('Authorization 헤더: $jwt');
      expect(out, isNot(contains('eyJhbGciOi')));
      expect(out, contains('[jwt]'));
    });

    test('Bearer 토큰은 대소문자 상관없이 지운다', () {
      expect(AppLogger.redact('bearer abc123def456'), contains('[token]'));
      expect(AppLogger.redact('Bearer abc123def456'), contains('[token]'));
      expect(AppLogger.redact('BEARER abc123def456'), contains('[token]'));
    });

    test('긴 토큰처럼 보이는 문자열도 지운다', () {
      final out = AppLogger.redact('refresh=aBcD1234efGH5678ijKL9012mnOP3456qrST7890');
      expect(out, contains('[redacted]'));
    });

    test('평범한 한국어 로그는 건드리지 않는다', () {
      const msg = '학습지 생성 요청: 난이도 beginner, 재시도 2회';
      expect(AppLogger.redact(msg), msg);
    });

    test('숫자만 길게 있는 것(금액·시각)은 토큰으로 오인하지 않는다', () {
      const msg = '결제 12900원, 소요 1757000000000ms';
      expect(AppLogger.redact(msg), msg);
    });
  });
}

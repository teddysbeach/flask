import 'package:flutter_test/flutter_test.dart';
import 'package:onpar/features/auth/password_policy.dart';

/// 비밀번호 규칙을 못으로 박아 둔다.
///
/// 이 규칙은 가입 화면과 재설정 화면이 같이 쓰고, 서버의 최소치와도 맞춰져 있다.
/// 여기서 조용히 느슨해지면 "가입은 되는데 로그인이 안 되는" 계정이 생긴다.
void main() {
  group('길이', () {
    test('7자는 안 된다 (경계 바로 아래)', () {
      final r = PasswordPolicy.check('abc123!');
      expect(r.ok, isFalse);
      expect(r.rules.first.met, isFalse, reason: '8자 이상 규칙이 미충족이어야 한다');
    });

    test('8자는 된다 (경계)', () {
      final r = PasswordPolicy.check('abc1234!');
      expect(r.ok, isTrue);
      expect(r.rules.first.met, isTrue);
    });

    test('72자는 된다 (상한 경계)', () {
      final password = 'a1${'x' * 70}';
      expect(password.length, 72);
      expect(PasswordPolicy.check(password).ok, isTrue);
    });

    test('73자는 안 된다 (상한 바로 위)', () {
      final password = 'a1${'x' * 71}';
      expect(password.length, 73);
      final r = PasswordPolicy.check(password);
      expect(r.ok, isFalse);
      expect(r.rules.last.met, isFalse, reason: '72자 이하 규칙이 미충족이어야 한다');
    });

    test('길이는 코드 유닛이 아니라 문자로 센다', () {
      // 이모지 하나는 코드 유닛으로 2다. 그것을 2자로 세면
      // 사용자가 보는 길이와 앱이 세는 길이가 어긋난다.
      const password = 'ab12🙂🙂🙂'; // 문자 7개
      expect(password.length, greaterThan(7));
      expect(PasswordPolicy.check(password).ok, isFalse);
    });

    test('빈 문자열은 아무 조건도 통과하지 못한다', () {
      final r = PasswordPolicy.check('');
      expect(r.ok, isFalse);
      expect(r.rules.where((e) => e.met).length, 1, reason: '상한 규칙만 충족이다');
    });
  });

  group('문자 종류 2가지 이상', () {
    test('영문만 길게 써도 안 된다', () {
      expect(PasswordPolicy.check('abcdefghij').ok, isFalse);
      expect(PasswordPolicy.kindCount('abcdefghij'), 1);
    });

    test('숫자만 길게 써도 안 된다', () {
      expect(PasswordPolicy.check('1234567890').ok, isFalse);
      expect(PasswordPolicy.kindCount('1234567890'), 1);
    });

    test('기호만 길게 써도 안 된다', () {
      expect(PasswordPolicy.check(r'!@#$%^&*()').ok, isFalse);
      expect(PasswordPolicy.kindCount(r'!@#$%^&*()'), 1);
    });

    test('영문 + 숫자면 된다', () {
      expect(PasswordPolicy.kindCount('abcd1234'), 2);
      expect(PasswordPolicy.check('abcd1234').ok, isTrue);
    });

    test('영문 + 기호면 된다', () {
      expect(PasswordPolicy.check('abcdefg!').ok, isTrue);
    });

    test('숫자 + 기호면 된다', () {
      expect(PasswordPolicy.check('12345678!').ok, isTrue);
    });

    test('세 종류를 다 쓰면 3으로 센다', () {
      expect(PasswordPolicy.kindCount('abc123!@'), 3);
    });

    test('한글은 기호로 센다 — 종류를 늘려 주는 쪽이 사용자에게 유리하다', () {
      expect(PasswordPolicy.kindCount('가나다라마바사아'), 1);
      expect(PasswordPolicy.check('가나다라마바사12').ok, isTrue);
    });

    test('공백은 종류로 세지 않는다', () {
      // 8자를 채워도 영문 한 종류뿐이라 통과하면 안 된다.
      expect(PasswordPolicy.kindCount('abcd efgh'), 1);
      expect(PasswordPolicy.check('abcd efgh').ok, isFalse);
    });

    test('공백만으로는 아무 종류도 아니다', () {
      expect(PasswordPolicy.kindCount('        '), 0);
      expect(PasswordPolicy.check('        ').ok, isFalse);
    });
  });

  group('규칙 목록', () {
    test('항상 세 줄이고 순서가 고정이다', () {
      final r = PasswordPolicy.check('abcd1234');
      expect(r.rules.length, 3);
      expect(r.rules[0].label, contains('8자 이상'));
      expect(r.rules[1].label, contains('2가지 이상'));
      expect(r.rules[2].label, contains('72자 이하'));
    });

    test('ok 는 모든 규칙이 met 일 때만 참이다', () {
      for (final password in ['', 'a', 'abcdefgh', 'abcd1234', 'a1${'x' * 80}']) {
        final r = PasswordPolicy.check(password);
        expect(r.ok, r.rules.every((e) => e.met), reason: '입력: ${password.length}자');
      }
    });

    test('상수가 바뀌면 이 테스트가 먼저 깨진다', () {
      expect(PasswordPolicy.minLength, 8);
      expect(PasswordPolicy.maxLength, 72);
      expect(PasswordPolicy.minKinds, 2);
    });
  });

  group('확인 입력 비교', () {
    test('같으면 참', () {
      expect(PasswordPolicy.matches('abcd1234', 'abcd1234'), isTrue);
    });

    test('다르면 거짓', () {
      expect(PasswordPolicy.matches('abcd1234', 'abcd12345'), isFalse);
    });

    test('둘 다 비어 있으면 거짓 — 안 쓴 것은 일치가 아니다', () {
      expect(PasswordPolicy.matches('', ''), isFalse);
    });

    test('앞뒤 공백을 다듬지 않는다 — 비밀번호의 공백은 내용이다', () {
      expect(PasswordPolicy.matches('abcd1234 ', 'abcd1234'), isFalse);
    });
  });
}

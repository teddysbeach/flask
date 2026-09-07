import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:onpar/features/worksheet/worksheet_response_mapping.dart';

/// 학습지 안에서 학생이 무엇을 골랐고 무엇을 썼는지가 이 변환을 지난다.
/// 여기가 틀리면 학습 이력이 조용히 비거나 저장이 통째로 실패한다 — 화면에서는 안 보인다.
void main() {
  group('선택형(choice)', () {
    test('camelCase 를 snake_case 로 옮기고 attempts 를 그대로 싣는다', () {
      final row = mapLearnResponse({
        'id': 'quiz-3',
        'kind': 'choice',
        'questionId': '9f1c0a2e-0000-4000-8000-000000000001',
        'firstChoice': 2,
        'finalChoice': 0,
        'attempts': [
          {'choice': 2, 'text': '가속도', 'correct': false, 'at': 1757000000000, 'msSincePrompt': 4200},
          {'choice': 0, 'text': '속도', 'correct': true, 'at': 1757000009000, 'msSincePrompt': 13200},
        ],
        'correct': true,
        'feedbackSeen': true,
        'changedMind': true,
        'firstCorrect': false,
      });

      expect(row, isNotNull);
      expect(row!['response_id'], 'quiz-3');
      expect(row['kind'], 'choice');
      expect(row['quiz_item_id'], '9f1c0a2e-0000-4000-8000-000000000001');
      expect(row['first_choice'], 2);
      expect(row['final_choice'], 0);
      expect(row['correct'], true);

      final attempts = row['attempts']! as List<Map<String, Object?>>;
      expect(attempts, hasLength(2));
      // attempts 는 jsonb 다 — 안쪽은 DB 주석이 못박은 camelCase 를 유지한다.
      expect(attempts.first['msSincePrompt'], 4200);
      expect(attempts.first['correct'], false);

      // 첫 응답까지 걸린 시간은 첫 시도에서 온다.
      expect(row['ms_since_prompt'], 4200);

      // 선택형에는 서술형 컬럼이 끼어들지 않는다.
      expect(row.containsKey('text'), isFalse);
      expect(row.containsKey('chars'), isFalse);
      expect(row.containsKey('ink_strokes'), isFalse);

      // 화면 표시용 필드는 저장하지 않는다.
      expect(row.containsKey('feedback_seen'), isFalse);
      expect(row.containsKey('changed_mind'), isFalse);
    });

    test('아직 안 고른 응답은 선택 컬럼 키를 아예 넣지 않는다', () {
      // upsert 의 UPDATE 절이 이미 저장된 first_choice 를 null 로 덮으면
      // 그 학생의 첫 오답(= 오개념)이 사라진다. 그래서 "없음" 은 키 자체가 없다.
      final row = mapLearnResponse({
        'id': 'act-1',
        'kind': 'choice',
        'questionId': null,
        'firstChoice': null,
        'finalChoice': null,
        'attempts': <Object?>[],
        'correct': null,
      })!;

      expect(row.keys.toSet(), {'response_id', 'kind', 'attempts'});
      expect(row['attempts'], isEmpty);
    });

    test('정답 키가 없는 활동은 correct 가 null 이고, 그래서 키가 없다', () {
      final row = mapLearnResponse({
        'id': 'act-2',
        'kind': 'choice',
        'firstChoice': 1,
        'finalChoice': 1,
        'correct': null,
        'attempts': [
          {'choice': 1, 'text': '왼쪽', 'correct': null, 'at': 1757000000000, 'msSincePrompt': 900},
        ],
      })!;

      expect(row['first_choice'], 1);
      expect(row.containsKey('correct'), isFalse);
      final attempts = row['attempts']! as List<Map<String, Object?>>;
      expect(attempts.single.containsKey('correct'), isFalse);
      expect(row['ms_since_prompt'], 900);
    });

    test('빈 quiz-id 는 null 과 같다 — uuid 컬럼에 빈 문자열을 넣으면 저장이 통째로 실패한다', () {
      // 렌더러가 `data-quiz-id=""` 를 낸다(활동·예측 칸에는 quiz_items 행이 없다).
      final row = mapLearnResponse({
        'id': 'act-3',
        'kind': 'choice',
        'questionId': '   ',
        'attempts': <Object?>[],
      })!;
      expect(row.containsKey('quiz_item_id'), isFalse);
    });
  });

  group('서술형(written)', () {
    test('글자 수·필기 수는 NOT NULL 이라 언제나 실린다', () {
      final row = mapLearnResponse({
        'id': 'quiz-7',
        'kind': 'written',
        'questionId': '9f1c0a2e-0000-4000-8000-000000000002',
        'text': '속도가 변하는 정도예요.',
        'chars': 12,
        'inkStrokes': 0,
        'revisionHistory': [
          {'chars': 3, 'at': 1757000000000},
          {'chars': 12, 'at': 1757000004000},
        ],
        'submittedAt': 1757000004000,
        'msSincePrompt': 8100,
      })!;

      expect(row['response_id'], 'quiz-7');
      expect(row['kind'], 'written');
      expect(row['text'], '속도가 변하는 정도예요.');
      expect(row['chars'], 12);
      expect(row['ink_strokes'], 0);
      expect(row['ms_since_prompt'], 8100);
      // 서술형에는 선택 이력이 없다. NOT NULL 이므로 빈 배열을 넣는다.
      expect(row['attempts'], isEmpty);
      expect(row.containsKey('first_choice'), isFalse);
      expect(row.containsKey('final_choice'), isFalse);
    });

    test('필기로만 답했으면 text 키가 없다 — 빈 문자열을 넣지 않는다', () {
      // '' 를 저장하면 "타이핑했다 지웠다" 와 "손으로만 썼다" 가 구분되지 않는다.
      final row = mapLearnResponse({
        'id': 'quiz-8',
        'kind': 'written',
        'text': '',
        'chars': 0,
        'inkStrokes': 14,
        'submittedAt': 1757000000000,
        'msSincePrompt': null,
      })!;

      expect(row.containsKey('text'), isFalse);
      expect(row['chars'], 0);
      expect(row['ink_strokes'], 14);
      expect(row.containsKey('ms_since_prompt'), isFalse);
    });

    test('브리지가 숫자를 double 로 올려도 int 로 받는다', () {
      // JS 는 숫자가 한 종류다. 플랫폼 채널을 지나면 4 가 4.0 으로 오기도 한다.
      final row = mapLearnResponse({
        'id': 'quiz-9',
        'kind': 'written',
        'chars': 12.0,
        'inkStrokes': 3.0,
        'msSincePrompt': 8100.0,
      })!;

      expect(row['chars'], isA<int>());
      expect(row['chars'], 12);
      expect(row['ink_strokes'], 3);
      expect(row['ms_since_prompt'], 8100);
    });

    test('값이 아예 없으면 0 으로 채운다(컬럼이 NOT NULL 이다)', () {
      final row = mapLearnResponse({'id': 'quiz-10', 'kind': 'written'})!;
      expect(row['chars'], 0);
      expect(row['ink_strokes'], 0);
      expect(row['attempts'], isEmpty);
    });
  });

  group('저장하지 않는 것', () {
    test('id 가 없거나 비어 있으면 버린다', () {
      expect(mapLearnResponse({'kind': 'choice'}), isNull);
      expect(mapLearnResponse({'id': '', 'kind': 'choice'}), isNull);
      expect(mapLearnResponse({'id': 123, 'kind': 'choice'}), isNull);
    });

    test('아는 kind 가 아니면 버린다 — slider 는 응답이 아니다', () {
      expect(mapLearnResponse({'id': 'fig-1', 'kind': 'slider'}), isNull);
      expect(mapLearnResponse({'id': 'quiz-1'}), isNull);
    });

    test('Map 이 아닌 것이 와도 터지지 않는다', () {
      expect(mapLearnResponse(null), isNull);
      expect(mapLearnResponse('quiz-1'), isNull);
      expect(mapLearnResponse(<Object?>[]), isNull);
    });
  });

  group('여러 건 모으기', () {
    test('같은 자리를 여러 번 보내면 마지막 스냅샷만 남는다', () {
      // 브리지는 타이핑할 때마다 스냅샷을 보낸다. 앞의 것은 이미 낡았다.
      final rows = mapLearnResponses([
        {'id': 'quiz-7', 'kind': 'written', 'text': '속', 'chars': 1},
        {'id': 'quiz-3', 'kind': 'choice', 'firstChoice': 2, 'finalChoice': 2, 'attempts': <Object?>[]},
        {'id': 'quiz-7', 'kind': 'written', 'text': '속도가 변하는 정도', 'chars': 10},
        {'id': 'fig-1', 'kind': 'slider'},
      ]);

      expect(rows, hasLength(2));
      final written = rows.firstWhere((r) => r['response_id'] == 'quiz-7');
      expect(written['chars'], 10);
      expect(written['text'], '속도가 변하는 정도');
    });

    test('만들어진 행은 전부 JSON 으로 직렬화된다 — 그대로 Postgrest 로 나간다', () {
      final rows = mapLearnResponses([
        {
          'id': 'quiz-3',
          'kind': 'choice',
          'attempts': [
            {'choice': 0, 'text': '속도', 'correct': true, 'at': 1757000000000, 'msSincePrompt': 200},
            'not-a-map',
          ],
        },
        {'id': 'quiz-7', 'kind': 'written', 'chars': 3, 'inkStrokes': 0},
      ]);

      expect(() => jsonEncode(rows), returnsNormally);
      final attempts = rows.first['attempts']! as List<Map<String, Object?>>;
      expect(attempts, hasLength(1)); // Map 이 아닌 시도는 버린다
    });
  });
}

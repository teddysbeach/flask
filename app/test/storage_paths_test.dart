import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:onpar/core/app_error.dart';
import 'package:onpar/data/storage_repository.dart';

/// 필기는 파일로 남는다. 경로 규칙이 흔들리면 다음에 열었을 때 **필기를 못 찾고**,
/// gzip 왕복이 어긋나면 파일은 있는데 읽을 수 없다. 둘 다 사용자 데이터 손상이라
/// 화면을 거치지 않는 순수 함수로 못박아 둔다.
void main() {
  group('필기 경로', () {
    const user = '11111111-1111-1111-1111-111111111111';
    const sheet = 'aaaaaaaa-0000-0000-0000-000000000001';

    test('<userId>/<worksheetId>.json.gz', () {
      expect(
        StoragePaths.annotations(userId: user, worksheetId: sheet),
        '$user/$sheet.json.gz',
      );
    });

    test('첫 조각은 언제나 사용자 id — Storage RLS 가 이 조각만 본다', () {
      final path = StoragePaths.annotations(userId: user, worksheetId: sheet);
      expect(path.split('/').first, user);
      expect(StoragePaths.isOwnedBy(path, user), isTrue);
      expect(StoragePaths.isOwnedBy(path, '22222222-2222-2222-2222-222222222222'), isFalse);
    });

    test('남의 폴더로 빠지는 경로는 아예 만들어지지 않는다', () {
      // 학습지 id 에 구분자나 상위 이동이 섞이면 다른 사람 폴더를 가리킬 수 있다.
      expect(
        () => StoragePaths.annotations(userId: user, worksheetId: '../$user/secret'),
        throwsA(isA<AppError>()),
      );
      expect(
        () => StoragePaths.annotations(userId: user, worksheetId: '..'),
        throwsA(isA<AppError>()),
      );
      expect(
        () => StoragePaths.annotations(userId: '$user/..', worksheetId: sheet),
        throwsA(isA<AppError>()),
      );
      // 사용자 id 자리에 다른 사람 폴더를 끼워 넣는 것도 마찬가지.
      expect(
        () => StoragePaths.annotations(userId: '$user/../bob', worksheetId: sheet),
        throwsA(isA<AppError>()),
      );
      expect(
        () => StoragePaths.annotations(userId: '', worksheetId: sheet),
        throwsA(isA<AppError>()),
      );
    });

    test('빈 사용자 id 는 어떤 경로도 소유하지 않는다', () {
      expect(StoragePaths.isOwnedBy('$user/$sheet.json.gz', ''), isFalse);
    });

    test('프로필 사진도 사용자 폴더 안이고, JPG/PNG 만 받는다', () {
      final path = StoragePaths.avatar(userId: user, extension: 'JPG', stamp: 42);
      expect(path, '$user/avatar_42.jpg');
      expect(StoragePaths.isOwnedBy(path, user), isTrue);
      expect(StoragePaths.avatarContentType('png'), 'image/png');
      expect(StoragePaths.avatarContentType('jpeg'), 'image/jpeg');
      expect(
        () => StoragePaths.avatar(userId: user, extension: 'gif', stamp: 1),
        throwsA(isA<AppError>()),
      );
    });
  });

  group('gzip 왕복', () {
    String sampleDoc({int strokes = 40}) => jsonEncode({
          'format_version': 2,
          'sheet_width': 820,
          'doc_height': 7420,
          'deleted': <String>[],
          'strokes': [
            for (var i = 0; i < strokes; i++)
              {
                'id': 's_${i.toString().padLeft(3, '0')}',
                'tool': 'pen',
                'color': '#1A1A1A',
                'width': 2.4,
                'created_at': 1757000000000 + i,
                'anchor': 'quiz-${i % 5}',
                'points': [for (var k = 0; k < 60; k++) (k * 0.0137 + i).toStringAsFixed(4)],
              },
          ],
        });

    test('압축했다 풀면 원본과 한 글자도 다르지 않다', () {
      final json = sampleDoc();
      final payload = InkCodec.encode(json);
      expect(InkCodec.decode(payload.bytes), json);
    });

    test('한글·이모지가 섞여도 왕복한다 (바이트 수는 문자 수가 아니다)', () {
      final json = jsonEncode({
        'format_version': 2,
        'strokes': <Object?>[],
        'note': '필기 메모 🖊️ 미분계수',
      });
      final payload = InkCodec.encode(json);
      expect(InkCodec.decode(payload.bytes), json);
      expect(payload.rawBytes, utf8.encode(json).length);
    });

    test('압축 전후 크기를 반환값으로 알 수 있다 (annotations.bytes 에 들어갈 값)', () {
      final json = sampleDoc();
      final payload = InkCodec.encode(json);

      expect(payload.rawBytes, utf8.encode(json).length);
      expect(payload.gzipBytes, payload.bytes.length);
      // 필기 JSON 은 같은 모양이 반복돼 잘 줄어든다. 안 줄어들면 포맷이나 압축이 깨진 것이다.
      expect(payload.gzipBytes, lessThan(payload.rawBytes));
      expect(payload.ratio, lessThan(1));
    });

    test('gzip 매직 넘버로 시작한다 — 서버가 Content-Encoding 을 보고 읽는다', () {
      final payload = InkCodec.encode(sampleDoc(strokes: 1));
      expect(payload.bytes[0], 0x1f);
      expect(payload.bytes[1], 0x8b);
    });

    test('저장할 획 수는 문서에서 센다', () {
      expect(InkCodec.strokeCount(sampleDoc(strokes: 7)), 7);
      expect(InkCodec.strokeCount('{"format_version":2}'), 0);
    });
  });

  group('충돌 병합', () {
    String doc(List<Map<String, Object?>> strokes, {List<String> deleted = const []}) =>
        jsonEncode({
          'format_version': 2,
          'sheet_width': 820,
          'doc_height': 1000,
          'deleted': deleted,
          'strokes': strokes,
        });

    Map<String, Object?> stroke(String id, int at) =>
        {'id': id, 'tool': 'pen', 'created_at': at, 'anchor': null, 'points': <double>[1, 2, 0.5]};

    test('두 기기의 획을 합치고 시간순으로 세운다 — 어느 쪽도 잃지 않는다', () {
      final merged = InkCodec.merge(
        local: doc([stroke('a', 1), stroke('c', 3)]),
        remote: doc([stroke('b', 2)]),
      );
      final ids = (jsonDecode(merged) as Map<String, Object?>)['strokes']! as List;
      expect(ids.map((s) => (s as Map)['id']), ['a', 'b', 'c']);
    });

    test('한쪽에서 지운 획은 합쳐도 되살아나지 않는다', () {
      final merged = InkCodec.merge(
        local: doc([stroke('a', 1)], deleted: ['b']),
        remote: doc([stroke('a', 1), stroke('b', 2)]),
      );
      final decoded = jsonDecode(merged) as Map<String, Object?>;
      expect((decoded['strokes']! as List).map((s) => (s as Map)['id']), ['a']);
      expect(decoded['deleted'], ['b']);
    });

    test('v1(옛 문서 좌표) 도 합칠 수 있고, 결과는 현재 포맷이다', () {
      final merged = InkCodec.merge(
        local: doc([stroke('new', 5)]),
        remote: jsonEncode({
          'format_version': 1,
          'strokes': [
            {'id': 'old', 'tool': 'pen', 'created_at': 1, 'points': <double>[120.4, 331.2, 0.42]},
          ],
        }),
      );
      final decoded = jsonDecode(merged) as Map<String, Object?>;
      expect(decoded['format_version'], 2);
      expect((decoded['strokes']! as List).map((s) => (s as Map)['id']), ['old', 'new']);
    });

    test('모르는 미래 포맷은 합치지 않고 던진다 — 사용자에게 물어야 한다', () {
      expect(
        () => InkCodec.merge(
          local: doc([stroke('a', 1)]),
          remote: jsonEncode({'format_version': 99, 'strokes': <Object?>[]}),
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });
}

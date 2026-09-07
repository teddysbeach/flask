import 'package:flutter_test/flutter_test.dart';
import 'package:onpar/data/worksheet_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 같은 주제 재생성.
///
/// 여기서 지키는 것: 서버의 409 를 **오류가 아니라 물어볼 일**로 옮긴다.
/// 못 알아보면 "알 수 없는 오류" 가 뜨고, 사용자는 결국 같은 주제를 또 만들어 한 장을 더 쓴다.
void main() {
  FunctionException dupe(Map<String, Object?> details) =>
      FunctionException(status: 409, details: details);

  test('409 duplicate_topic 을 결과로 알아본다', () {
    final r = duplicateFromError(dupe({
      'error': 'duplicate_topic',
      'worksheet_id': 'ws-42',
      'title': '미분, 한 순간의 기울기',
      'created_at': '2026-03-01T10:00:00Z',
    }));
    expect(r, isNotNull);
    expect(r!.worksheetId, 'ws-42');
    expect(r.title, '미분, 한 순간의 기울기');
    expect(r.createdAt, isNotNull);
  });

  test('학습지 id 가 없으면 중복으로 치지 않는다 — 열 곳이 없으면 물어볼 수도 없다', () {
    expect(duplicateFromError(dupe({'error': 'duplicate_topic'})), isNull);
    expect(duplicateFromError(dupe({'error': 'duplicate_topic', 'worksheet_id': ''})), isNull);
  });

  test('다른 오류는 그대로 오류다', () {
    expect(duplicateFromError(dupe({'error': 'quota_exhausted'})), isNull);
    expect(duplicateFromError(Exception('네트워크')), isNull);
  });
}

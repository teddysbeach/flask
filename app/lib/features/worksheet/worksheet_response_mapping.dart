/// 학습지 WebView 의 `learn` 브리지가 보내는 응답 레코드를 `responses` 테이블 행으로 옮긴다.
///
/// JS(`worksheet-interact.js`)는 camelCase 로 말하고 Postgres 는 snake_case 로 듣는다.
/// 그 변환을 화면 코드 안에 흩어 두면 컬럼 이름 오타가 런타임까지, 그러니까
/// **사용자가 문제를 다 푼 뒤에** 발견된다. 그래서 순수 함수 하나로 모으고 테스트로 고정한다.
///
/// 규칙 세 가지:
/// 1. 값이 없는 선택 컬럼은 **키 자체를 넣지 않는다.** upsert 의 UPDATE 절이 기존 값을
///    null 로 덮어쓰는 사고를 막는다(첫 선택은 절대 덮어쓰면 안 되는 값이다).
/// 2. `attempts` 는 NOT NULL 이라 언제나 넣는다. 서술형은 빈 배열이다.
/// 3. jsonb 로 들어가는 값은 JSON 으로 직렬화 가능한 것만 남긴다 — 브리지가 준
///    이상한 타입을 그대로 넘기면 저장이 통째로 실패한다.
library;

/// `responses.kind` 가 허용하는 값(테이블 CHECK 제약과 같다).
const kResponseKindChoice = 'choice';
const kResponseKindWritten = 'written';

/// 브리지 레코드 한 건 → DB 행 하나. 저장할 수 없는 것이면 null.
///
/// 걸러내는 것: id 가 없거나 빈 문자열, 아는 kind 가 아닌 것(예: 'slider').
/// 이 둘은 오류가 아니라 "저장할 게 아니다" 이므로 조용히 버린다.
Map<String, Object?>? mapLearnResponse(Object? raw) {
  if (raw is! Map) return null;

  final id = _str(raw['id']);
  if (id == null) return null;

  final kind = _str(raw['kind']);
  if (kind != kResponseKindChoice && kind != kResponseKindWritten) return null;

  final row = <String, Object?>{
    'response_id': id,
    'kind': kind,
  };

  // quiz_item_id 는 연습 문제일 때만 채워진다. 렌더러는 그 외의 자리에 빈 문자열을
  // 넣으므로(`data-quiz-id=""`) 빈 문자열을 null 과 같이 취급한다 — uuid 캐스팅이 터진다.
  final quizItemId = _str(raw['questionId']);
  if (quizItemId != null) row['quiz_item_id'] = quizItemId;

  if (kind == kResponseKindChoice) {
    final attempts = _attempts(raw['attempts']);
    row['attempts'] = attempts;

    _put(row, 'first_choice', _int(raw['firstChoice']));
    _put(row, 'final_choice', _int(raw['finalChoice']));
    _put(row, 'correct', _bool(raw['correct']));

    // 선택형의 "첫 응답까지 걸린 시간" 은 첫 시도에만 있다(레코드 최상단에는 없다).
    _put(row, 'ms_since_prompt', _firstAttemptMs(attempts));
    return row;
  }

  // 서술형. attempts 는 선택형 이력의 모양이라 서술형에는 채울 것이 없다.
  row['attempts'] = const <Object?>[];
  row['chars'] = _int(raw['chars']) ?? 0;
  row['ink_strokes'] = _int(raw['inkStrokes']) ?? 0;

  // 필기로만 답했으면 text 는 null 이다. 빈 문자열을 넣으면 "타이핑했는데 지웠다" 와
  // "손으로만 썼다" 가 데이터상 같아진다.
  final text = _str(raw['text']);
  if (text != null) row['text'] = text;

  _put(row, 'ms_since_prompt', _int(raw['msSincePrompt']));
  return row;
}

/// 여러 건을 한 번에. 같은 `response_id` 가 여러 번 오면 **마지막 것만** 남긴다 —
/// 브리지는 타이핑할 때마다 스냅샷을 보내므로 앞의 것은 이미 낡았다.
List<Map<String, Object?>> mapLearnResponses(Iterable<Object?> raws) {
  final byId = <String, Map<String, Object?>>{};
  for (final raw in raws) {
    final row = mapLearnResponse(raw);
    if (row == null) continue;
    byId[row['response_id']! as String] = row;
  }
  return byId.values.toList(growable: false);
}

void _put(Map<String, Object?> row, String key, Object? value) {
  if (value != null) row[key] = value;
}

/// `attempts` 는 jsonb 로 들어간다. DB 주석이 못박은 모양(`{choice,text,correct,at,msSincePrompt}`)만
/// 남기고 나머지는 버린다 — 브리지가 필드를 늘려도 저장 스키마는 흔들리지 않는다.
List<Map<String, Object?>> _attempts(Object? raw) {
  if (raw is! List) return const [];
  final out = <Map<String, Object?>>[];
  for (final a in raw) {
    if (a is! Map) continue;
    final one = <String, Object?>{};
    _put(one, 'choice', _int(a['choice']));
    _put(one, 'text', _str(a['text']));
    _put(one, 'correct', _bool(a['correct']));
    _put(one, 'at', _int(a['at']));
    _put(one, 'msSincePrompt', _int(a['msSincePrompt']));
    if (one.isNotEmpty) out.add(one);
  }
  return out;
}

int? _firstAttemptMs(List<Map<String, Object?>> attempts) {
  for (final a in attempts) {
    final ms = a['msSincePrompt'];
    if (ms is int) return ms;
  }
  return null;
}

/// 빈 문자열은 null 로 본다. 브리지는 "값 없음" 을 `null` 로도 `''` 로도 보낸다.
String? _str(Object? v) {
  if (v is! String) return null;
  final t = v.trim();
  return t.isEmpty ? null : v;
}

/// WebView 브리지는 정수를 double 로 올려보내기도 한다(JS 는 숫자가 한 종류다).
int? _int(Object? v) {
  if (v is int) return v;
  if (v is num) {
    if (v.isNaN || v.isInfinite) return null;
    return v.round();
  }
  if (v is String) return int.tryParse(v.trim());
  return null;
}

bool? _bool(Object? v) {
  if (v is bool) return v;
  return null;
}

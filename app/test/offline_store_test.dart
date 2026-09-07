import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onpar/core/app_error.dart';
import 'package:onpar/data/offline_store.dart';

/// 오프라인 보관함.
///
/// 여기서 지키는 것은 하나다 — **못 올린 필기는 앱이 죽어도 남는다.**
/// 나머지(본문 캐시)는 편의지만, 이건 잃으면 되돌릴 수 없는 사용자 데이터다.
void main() {
  late Directory tmp;
  late OfflineStore store;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('onpar_offline_');
    store = OfflineStore(root: tmp);
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('id 에 경로 조각이 섞이면 거부한다', () {
    // 이걸 놓치면 ../ 로 남의 폴더에 쓴다.
    for (final bad in ['../etc/passwd', 'a/b', '', '.hidden', 'x' * 80]) {
      expect(() => OfflineStore.fileName(bad, 'html'), throwsA(isA<AppError>()),
          reason: '"$bad" 가 파일 이름으로 통과했다');
    }
    expect(OfflineStore.fileName('ws-0001', 'html'), 'ws-0001.html');
  });

  test('학습지 본문을 적고 그대로 읽는다', () async {
    expect(await store.readSheet('ws1'), isNull, reason: '없는 것은 null 이어야 한다');
    const html = '<!doctype html><p>학습지 본문</p>';
    await store.writeSheet('ws1', html);
    expect(await store.readSheet('ws1'), html);
  });

  test('못 올린 필기는 rev 와 함께 남는다', () async {
    await store.writeInkSpool('ws1', json: '{"strokes":[1,2,3]}', rev: 7);
    final spool = await store.readInkSpool('ws1');
    expect(spool, isNotNull);
    expect(spool!.json, '{"strokes":[1,2,3]}');
    // rev 를 같이 저장하지 않으면 나중에 올릴 때 어느 판 위에서 그린 것인지 몰라
    // 남의 기기 필기를 덮어쓰게 된다.
    expect(spool.rev, 7);
    expect(spool.savedAt, isNotNull);
  });

  test('올리고 나면 지운다 — 안 지우면 다음에 옛 필기를 다시 올린다', () async {
    await store.writeInkSpool('ws1', json: '{"a":1}', rev: 1);
    await store.clearInkSpool('ws1');
    expect(await store.readInkSpool('ws1'), isNull);
    // 없는 것을 지우는 것도 성공이어야 한다(두 번 눌러도 같은 결과).
    await store.clearInkSpool('ws1');
  });

  test('보관물이 깨져 있어도 학습지는 열려야 한다', () async {
    await store.writeInkSpool('ws1', json: '{"a":1}', rev: 1);
    final f = File('${tmp.path}/onpar/${OfflineStore.spoolDir}/ws1.ink.json');
    await f.writeAsString('이건 JSON 이 아니다');
    // 깨진 파일 때문에 예외가 나가면 학습지 화면이 통째로 안 열린다.
    expect(await store.readInkSpool('ws1'), isNull);
    expect(await f.exists(), isFalse, reason: '깨진 보관물은 치워야 다음에 또 안 걸린다');
  });

  test('빈 필기는 보관물로 치지 않는다', () async {
    await store.writeInkSpool('ws1', json: '', rev: 3);
    expect(await store.readInkSpool('ws1'), isNull);
  });

  test('로그아웃하면 전부 비운다 — 다음 사람이 남의 학습지를 보면 안 된다', () async {
    await store.writeSheet('ws1', '<p>a</p>');
    await store.writeInkSpool('ws1', json: '{"a":1}', rev: 1);
    await store.clearAll();
    expect(await store.readSheet('ws1'), isNull);
    expect(await store.readInkSpool('ws1'), isNull);
    // 비운 뒤에도 다시 쓸 수 있어야 한다(폴더를 지웠으니 새로 만들어야 한다).
    await store.writeSheet('ws2', '<p>b</p>');
    expect(await store.readSheet('ws2'), '<p>b</p>');
  });

  test('학습지마다 따로 보관한다', () async {
    await store.writeInkSpool('ws1', json: '{"one":1}', rev: 1);
    await store.writeInkSpool('ws2', json: '{"two":2}', rev: 2);
    expect((await store.readInkSpool('ws1'))!.json, '{"one":1}');
    expect((await store.readInkSpool('ws2'))!.rev, 2);
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../core/app_error.dart';
import '../core/logger.dart';

/// 기기에 두는 보관함 — 학습지 본문과 **아직 못 올린 필기**.
///
/// 두 가지를 푼다.
///
/// 1. **오프라인에서 학습지를 못 열던 것.** 본문은 서명 URL 로만 열렸다.
///    지하철·도서관·비행기가 공부하는 자리인데 거기서 앱이 아무것도 못 했다.
///    학습지 HTML 은 외부 요청이 0회인 자족 문서라, 한 번 받아 두면 그대로 다시 그릴 수 있다.
///
/// 2. **앱이 죽으면 사라지던 필기.** 저장에 실패하면 메모리에만 남아 있었다.
///    40분 필기하고 지하철에서 앱이 죽으면 그걸로 끝이었다. 이제 실패한 순간 기기에 적는다.
///
/// 저장 위치는 Application Support 다. Caches 는 OS 가 언제든 비울 수 있어서
/// 오프라인 본문도, 못 올린 필기도 둘 곳이 아니다.
class OfflineStore {
  OfflineStore({Directory? root}) : _override = root;

  final Directory? _override;
  Directory? _resolved;

  static const sheetsDir = 'sheets';
  static const spoolDir = 'spool';

  /// 파일 이름에 쓸 수 있는 id 인가. 경로 조각이 섞이면 남의 폴더를 건드린다.
  static final _safeId = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$');

  static String fileName(String worksheetId, String ext) {
    if (!_safeId.hasMatch(worksheetId)) {
      throw AppError.of(AppErrorKind.validation, message: '학습지 id 가 올바르지 않아요.');
    }
    return '$worksheetId.$ext';
  }

  Future<Directory> _dir(String kind) async {
    _resolved ??= _override ?? await getApplicationSupportDirectory();
    final d = Directory('${_resolved!.path}/onpar/$kind');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<File> _file(String kind, String worksheetId, String ext) async =>
      File('${(await _dir(kind)).path}/${fileName(worksheetId, ext)}');

  // ── 학습지 본문 ─────────────────────────────────────────────────────────

  /// 본문은 학습지마다 한 번 만들어지고 바뀌지 않는다. 그래서 캐시를 다시 확인하지 않는다 —
  /// 언젠가 다시 렌더하는 날이 오면 여기에 버전 키를 붙여야 한다.
  Future<String?> readSheet(String worksheetId) async {
    try {
      final f = await _file(sheetsDir, worksheetId, 'html');
      return await f.exists() ? await f.readAsString() : null;
    } catch (e, st) {
      AppLogger.error('보관된 학습지를 못 읽었다', error: e, stack: st);
      return null;   // 캐시를 못 읽는 것은 실패가 아니다. 서버에서 받으면 된다.
    }
  }

  Future<void> writeSheet(String worksheetId, String html) async {
    try {
      final f = await _file(sheetsDir, worksheetId, 'html');
      await f.writeAsString(html, flush: true);
    } catch (e, st) {
      // 못 적어도 지금 보는 데는 지장이 없다. 다음에 열 때 다시 받는다.
      AppLogger.error('학습지를 기기에 못 적었다', error: e, stack: st);
    }
  }

  // ── 못 올린 필기 ────────────────────────────────────────────────────────

  /// 올리지 못한 필기 한 벌. `rev` 는 이 필기가 어느 서버 판 위에서 그려졌는지다.
  Future<void> writeInkSpool(String worksheetId, {required String json, required int rev}) async {
    final f = await _file(spoolDir, worksheetId, 'ink.json');
    await f.writeAsString(jsonEncode({
      'rev': rev,
      'saved_at': DateTime.now().toUtc().toIso8601String(),
      'strokes': json,
    }), flush: true);
    AppLogger.debug('필기를 기기에 보관했다 (rev=$rev, ${json.length}B)');
  }

  Future<InkSpool?> readInkSpool(String worksheetId) async {
    try {
      final f = await _file(spoolDir, worksheetId, 'ink.json');
      if (!await f.exists()) return null;
      final m = jsonDecode(await f.readAsString());
      if (m is! Map) return null;
      final strokes = m['strokes'];
      if (strokes is! String || strokes.isEmpty) return null;
      return InkSpool(
        json: strokes,
        rev: (m['rev'] as num?)?.toInt() ?? 0,
        savedAt: DateTime.tryParse('${m['saved_at']}')?.toLocal(),
      );
    } catch (e, st) {
      // 깨진 보관물 때문에 학습지가 안 열리면 안 된다. 버리고 계속한다.
      AppLogger.error('보관된 필기를 못 읽었다', error: e, stack: st);
      await clearInkSpool(worksheetId);
      return null;
    }
  }

  Future<void> clearInkSpool(String worksheetId) async {
    try {
      final f = await _file(spoolDir, worksheetId, 'ink.json');
      if (await f.exists()) await f.delete();
    } catch (e, st) {
      AppLogger.error('보관된 필기를 못 지웠다', error: e, stack: st);
    }
  }

  /// 학습지 한 장에 대한 기기 사본을 전부 지운다(본문 + 못 올린 필기).
  ///
  /// 서버에서 지운 학습지가 기기에 남아 있으면 오프라인에서 되살아난다 —
  /// 사용자는 지웠다고 믿는데 비행기 모드에서 다시 보이는 상태다.
  Future<void> forget(String worksheetId) async {
    await clearInkSpool(worksheetId);
    try {
      final f = await _file(sheetsDir, worksheetId, 'html');
      if (await f.exists()) await f.delete();
    } catch (e, st) {
      AppLogger.error('보관된 학습지를 못 지웠다', error: e, stack: st);
    }
  }

  /// 로그아웃·탈퇴에서 부른다. 남의 기기가 아니라 **같은 기기의 다음 사람**을 막는 것이다.
  Future<void> clearAll() async {
    for (final kind in [sheetsDir, spoolDir]) {
      try {
        final d = await _dir(kind);
        if (await d.exists()) await d.delete(recursive: true);
      } catch (e, st) {
        AppLogger.error('보관함을 못 비웠다', error: e, stack: st);
      }
    }
  }
}

class InkSpool {
  const InkSpool({required this.json, required this.rev, this.savedAt});

  final String json;

  /// 이 필기가 그려진 시점의 서버 판. 올릴 때 이 값으로 낙관적 잠금을 건다.
  final int rev;
  final DateTime? savedAt;
}

final offlineStoreProvider = Provider<OfflineStore>((ref) => OfflineStore());

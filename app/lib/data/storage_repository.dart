import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_error.dart';
import 'supabase.dart';

/// Storage 경로 규약. 문서(`docs/plan/06-annotation.md` §4)가 못박은 모양은 하나다:
///
///   `{bucket}/{user_id}/{worksheet_id}.json.gz`
///
/// 경로의 **첫 조각이 사용자 id** 라는 게 전부다. Storage RLS 가
/// `(storage.foldername(name))[1] = auth.uid()::text` 로 그 조각만 본다 —
/// 여기서 `../` 나 `bob/` 같은 게 섞이면 남의 폴더를 가리키는 경로가 만들어지고,
/// 서버는 막아 주지만 앱은 "저장했다" 고 말한 채 파일을 잃는다.
/// 그래서 경로를 문자열 조립이 아니라 **검증을 통과한 조각**으로만 만든다.
class StoragePaths {
  const StoragePaths._();

  static const annotationsBucket = 'annotations';
  static const worksheetsBucket = 'worksheets';
  static const avatarsBucket = 'avatars';

  /// 경로 한 조각으로 쓸 수 있는 문자. uuid 와 확장자를 담기에 충분하고
  /// `.` 로 시작하거나 `/` 를 품은 것은 통과하지 못한다(`..`, `bob/x` 차단).
  static final _segment = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$');

  /// 필기 파일. gzip 이므로 확장자도 `.json.gz` 다.
  static String annotations({required String userId, required String worksheetId}) =>
      '${_safe(userId, '사용자')}/${_safe(worksheetId, '학습지')}.json.gz';

  /// 프로필 사진. 같은 이름으로 덮어쓰면 CDN·이미지 캐시가 옛 사진을 계속 보여준다.
  /// 그래서 새로 올릴 때마다 이름을 바꾸고, 성공한 뒤에 옛 파일을 지운다.
  static String avatar({
    required String userId,
    required String extension,
    required int stamp,
  }) {
    final ext = extension.toLowerCase();
    if (!avatarExtensions.contains(ext)) {
      throw AppError.of(AppErrorKind.validation,
          message: 'JPG 나 PNG 사진만 올릴 수 있어요. 다른 사진으로 골라 주세요.');
    }
    return '${_safe(userId, '사용자')}/avatar_$stamp.$ext';
  }

  static const avatarExtensions = {'jpg', 'jpeg', 'png'};

  static String avatarContentType(String extension) =>
      extension.toLowerCase() == 'png' ? 'image/png' : 'image/jpeg';

  /// 이 경로가 정말 이 사용자의 폴더 안인가. 올리기 전에 앱이 먼저 본다 —
  /// 서버에 맡기면 실패가 업로드 뒤에야 오고, 그때는 이미 필기를 들고 있던 화면이 지나간 뒤다.
  static bool isOwnedBy(String path, String userId) {
    if (userId.isEmpty) return false;
    final first = path.split('/').first;
    return first == userId;
  }

  static String _safe(String value, String what) {
    if (!_segment.hasMatch(value)) {
      // 사용자가 고칠 수 있는 값이 아니다. 화면에는 일반 문구만 나가고 원인은 로그로 간다.
      throw AppError.of(
        AppErrorKind.validation,
        message: '저장 경로를 만들지 못했어요. 앱을 다시 시작해 주세요.',
        cause: '$what id 가 경로 조각으로 쓸 수 없는 값이다',
      );
    }
    return value;
  }
}

/// gzip 한 필기 한 벌. 압축 전후 크기를 **반환값으로** 들고 다닌다 —
/// `annotations.bytes` 에 실제 저장 용량(압축 후)을 넣어야 하고,
/// 압축이 먹고 있는지는 로그가 아니라 이 값으로 판단한다.
class InkPayload {
  const InkPayload({required this.bytes, required this.rawBytes});

  /// 업로드할 gzip 바이트.
  final Uint8List bytes;

  /// 압축 전 UTF-8 바이트 수.
  final int rawBytes;

  int get gzipBytes => bytes.length;

  /// 0.18 이면 82% 줄었다는 뜻.
  double get ratio => rawBytes == 0 ? 1 : gzipBytes / rawBytes;
}

/// 필기 JSON ↔ gzip. `JSON.stringify → gzip` (`docs/plan/06-annotation.md` §4).
///
/// A4 5장 빽빽한 필기가 압축 전 3~5MB 다. 그대로 올리면 통신비도 통신비지만
/// 저장이 3초 디바운스를 넘겨서 "저장 중" 이 안 끝난다.
class InkCodec {
  const InkCodec._();

  static InkPayload encode(String json) {
    final raw = utf8.encode(json);
    return InkPayload(bytes: Uint8List.fromList(gzip.encode(raw)), rawBytes: raw.length);
  }

  static String decode(List<int> gzipped) => utf8.decode(gzip.decode(gzipped));

  /// 이 문서에 든 획 수. `annotations.stroke_count` 는 화면 카운터가 아니라
  /// **방금 올린 문서**에서 세야 기록과 파일이 어긋나지 않는다.
  static int strokeCount(String json) {
    final decoded = jsonDecode(json);
    if (decoded is! Map<String, Object?>) return 0;
    final strokes = decoded['strokes'];
    return strokes is List ? strokes.length : 0;
  }

  /// 두 기기의 필기를 합친다. ink-core.js 의 `mergeAnnotations` 와 같은 규칙이다:
  /// 스트로크는 append-only 이고 고유 id 를 가지므로 **합집합**이 곧 병합이고,
  /// 지우개는 tombstone(`deleted`) 으로 표현돼 있어 합집합에서 다시 빼면 된다.
  ///
  /// 런타임(`window.ONPAR_INK`)이 mergeAnnotations 를 밖으로 열어 두지 않아서 여기서 같은 일을 한다.
  /// 규칙이 갈라지면 기기마다 다른 필기가 보이므로, ink-core 가 바뀌면 여기도 같이 바꿔야 한다.
  ///
  /// 정렬은 (created_at, id) — 두 기기가 같은 순서에 도달해야 겹친 획의 위아래가 같아진다.
  /// 어느 한쪽이라도 읽을 수 없으면 던진다. 반쯤 합친 필기를 저장하느니 사용자에게 묻는 게 낫다.
  static String merge({required String local, required String remote}) {
    final l = _asDoc(local);
    final r = _asDoc(remote);

    final byId = <String, Map<String, Object?>>{};
    for (final s in _strokes(l)) {
      final id = s['id'];
      if (id is String) byId[id] = s;
    }
    for (final s in _strokes(r)) {
      final id = s['id'];
      if (id is String) byId.putIfAbsent(id, () => s);
    }

    final deleted = <String>{..._ids(l['deleted']), ..._ids(r['deleted'])};
    for (final id in deleted) {
      byId.remove(id);
    }

    final strokes = byId.values.toList()
      ..sort((a, b) {
        final ta = (a['created_at'] as num?)?.toDouble() ?? 0;
        final tb = (b['created_at'] as num?)?.toDouble() ?? 0;
        final byTime = ta.compareTo(tb);
        if (byTime != 0) return byTime;
        return (a['id']! as String).compareTo(b['id']! as String);
      });

    return jsonEncode({
      // 결과는 언제나 현재 포맷이다. v1 스트로크는 anchor 가 없을 뿐 좌표는 그대로 유효하고,
      // 런타임의 migrateStrokes 가 anchor: null 로 읽는다.
      'format_version': 2,
      // 폭·높이는 이 기기의 현재 레이아웃 값을 쓴다 — 지금 화면에 그릴 값이기 때문이다.
      'sheet_width': l['sheet_width'] ?? r['sheet_width'],
      'doc_height': l['doc_height'] ?? r['doc_height'],
      'deleted': deleted.toList()..sort(),
      'strokes': strokes,
    });
  }

  static Map<String, Object?> _asDoc(String json) {
    final decoded = jsonDecode(json);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('필기 문서가 객체가 아니다');
    }
    final v = (decoded['format_version'] as num?)?.toInt() ?? 1;
    // 미래 포맷을 억지로 읽으면 필기가 깨진 채로 저장된다. 읽지 않는 쪽이 안전하다(ink-core 와 같은 판단).
    if (v > 2) throw FormatException('지원하지 않는 필기 포맷 버전: $v');
    return decoded;
  }

  static List<Map<String, Object?>> _strokes(Map<String, Object?> doc) {
    final raw = doc['strokes'];
    if (raw is! List) return const [];
    return raw.whereType<Map<String, Object?>>().toList();
  }

  static Iterable<String> _ids(Object? raw) =>
      raw is List ? raw.whereType<String>() : const <String>[];
}

/// Storage 입출력. 버킷은 전부 비공개고, 읽기는 정책(본인 폴더) 또는 서명 URL 로만 된다.
class StorageRepository {
  StorageRepository(this._client);

  final SupabaseClient _client;

  /// 필기 업로드. 같은 경로에 계속 덮어쓴다(`upsert`) — 학습지 하나에 필기는 한 벌이다.
  ///
  /// `cacheControl: '0'`: 캐시된 옛 필기를 내려받으면 사용자가 방금 쓴 것이 사라진 것처럼 보인다.
  Future<void> putAnnotations(String path, List<int> gzipped) async {
    try {
      await _client.storage.from(StoragePaths.annotationsBucket).uploadBinary(
            path,
            gzipped is Uint8List ? gzipped : Uint8List.fromList(gzipped),
            fileOptions: const FileOptions(
              contentType: 'application/gzip',
              upsert: true,
              cacheControl: '0',
            ),
          ).withTimeout(kTransferTimeout);
    } catch (e, st) {
      throw mapSupabaseError(e, st);
    }
  }

  /// 학습지 본문. 서명 URL 로 웹뷰가 직접 받는 대신 우리가 받아서 기기에 둔다 —
  /// 그래야 오프라인에서도 열리고, 서명 URL 만료를 신경 쓸 필요도 없어진다.
  Future<String> getWorksheetHtml(String path) async {
    try {
      final bytes = await _client.storage
          .from(StoragePaths.worksheetsBucket)
          .download(path)
          .withTimeout(kTransferTimeout);
      return utf8.decode(bytes);
    } catch (e, st) {
      throw mapSupabaseError(e, st);
    }
  }

  /// 저장된 필기. **파일이 없으면 null** — 첫 방문은 실패가 아니다.
  Future<List<int>?> getAnnotations(String path) async {
    try {
      return await _client.storage
          .from(StoragePaths.annotationsBucket)
          .download(path)
          .withTimeout(kTransferTimeout);
    } on StorageException catch (e, st) {
      if (_isMissing(e)) return null;
      throw mapSupabaseError(e, st);
    } catch (e, st) {
      throw mapSupabaseError(e, st);
    }
  }

  Future<void> putAvatar(
    String path,
    List<int> bytes, {
    required String contentType,
  }) async {
    try {
      await _client.storage.from(StoragePaths.avatarsBucket).uploadBinary(
            path,
            bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
            fileOptions: FileOptions(contentType: contentType, upsert: true),
          ).withTimeout(kTransferTimeout);
    } catch (e, st) {
      throw mapSupabaseError(e, st);
    }
  }

  /// 프로필 사진을 볼 때 쓸 URL. 버킷이 비공개라 서명해서 연다 —
  /// 공개 URL 이면 사용자 id 만 알면 누구나 남의 프로필 사진을 본다.
  /// 만료되는 값이라 DB 에는 절대 넣지 않는다(경로만 저장한다).
  Future<String> signedAvatarUrl(String path, {Duration ttl = const Duration(hours: 1)}) async {
    try {
      return await _client.storage
          .from(StoragePaths.avatarsBucket)
          .createSignedUrl(path, ttl.inSeconds)
          .withTimeout();
    } catch (e, st) {
      throw mapSupabaseError(e, st);
    }
  }

  /// 이미 없는 파일을 지우는 것은 성공으로 친다 — 되돌리기(기본 이미지로)가 두 번 눌려도 같은 결과여야 한다.
  Future<void> removeAvatar(String path) async {
    try {
      await _client.storage.from(StoragePaths.avatarsBucket).remove([path]).withTimeout();
    } on StorageException catch (e, st) {
      if (_isMissing(e)) return;
      throw mapSupabaseError(e, st);
    } catch (e, st) {
      throw mapSupabaseError(e, st);
    }
  }

  static bool _isMissing(StorageException e) =>
      e.statusCode == '404' ||
      e.error == 'not_found' ||
      e.message.toLowerCase().contains('not found');
}

final storageRepositoryProvider =
    Provider<StorageRepository>((ref) => StorageRepository(ref.watch(supabaseProvider)));

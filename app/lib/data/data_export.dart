import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_error.dart';
import 'supabase.dart';

/// 내 데이터 내보내기.
///
/// 개인정보보호법의 열람권·이동권에 대응한다. 계정을 지우는 길(delete-account)은 있는데
/// **가져가는 길**이 없었다 — 지우기 전에 자기 것을 챙길 방법이 없다는 뜻이다.
///
/// 서버에 새 함수를 두지 않는다. RLS 가 이미 "내 것만" 을 보장하므로 사용자 토큰으로
/// 그대로 읽으면 된다. 서버 함수를 만들면 그 안에서 범위를 다시 짜야 하고,
/// 그 코드가 틀리면 남의 데이터가 섞인다.
class DataExport {
  DataExport(this._client);
  final SupabaseClient _client;

  /// 내보낼 표. 순서는 사람이 읽는 순서다(계정 → 학습지 → 문항 → 답 → 복습 → 결제).
  static const _tables = <String, String>{
    'profile': 'profiles',
    'worksheets': 'worksheets',
    'quiz_items': 'quiz_items',
    'responses': 'responses',
    'review_schedules': 'review_schedules',
    'annotations': 'annotations',
    'purchases': 'purchases',
    'support_tickets': 'support_tickets',
  };

  /// 사람이 읽을 수 있는 JSON 한 덩어리.
  ///
  /// **한 표가 실패해도 나머지는 담는다.** 전부 아니면 전무로 만들면, 표 하나에 문제가
  /// 있을 때 사용자는 자기 데이터를 하나도 못 가져간다.
  Future<Map<String, Object?>> collect() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw AppError.of(AppErrorKind.unauthorized, message: '로그인한 뒤에 내려받을 수 있어요.');
    }

    final out = <String, Object?>{
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'account': {'id': user.id, 'email': user.email, 'created_at': user.createdAt},
      'note': '이 파일에는 회원님이 만든 학습지와 답, 복습 기록, 결제 내역이 들어 있어요. '
          '필기 원본(그림)은 용량이 커서 빠져 있어요.',
    };

    final failed = <String>[];
    for (final entry in _tables.entries) {
      try {
        out[entry.key] = await _client.from(entry.value).select().withTimeout();
      } catch (_) {
        failed.add(entry.key);
      }
    }
    if (failed.isNotEmpty) out['_incomplete'] = failed;
    return out;
  }

  /// 파일로 쓴다. 공유 시트에 넘길 경로를 돌려준다.
  Future<File> writeFile() async {
    final data = await collect();
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().toIso8601String().split('T').first;
    final file = File('${dir.path}/onpar-내데이터-$stamp.json');
    // 들여쓴 JSON 으로 쓴다. 기계가 읽는 것만 목적이면 한 줄이 낫지만,
    // 이동권은 **사람이 자기 데이터를 확인할 수 있어야** 한다는 뜻이다.
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
    return file;
  }
}

final dataExportProvider =
    Provider<DataExport>((ref) => DataExport(ref.watch(supabaseProvider)));

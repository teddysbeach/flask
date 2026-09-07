import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_error.dart';
import '../domain/models.dart';
import 'storage_repository.dart';
import 'supabase.dart';

class ProfileRepository {
  ProfileRepository(this._client);
  final SupabaseClient _client;

  Future<Profile> me() async {
    try {
      final id = _client.auth.currentUser!.id;
      final row = await _client.from('profiles').select().eq('id', id).single().withTimeout();
      return Profile.fromMap(row);
    } catch (e, st) {
      throw mapSupabaseError(e, st);
    }
  }

  /// RLS 가 quota_total 같은 컬럼의 수정을 막고 있다 — 여기서 보내도 서버가 거부한다.
  /// 그래서 앱은 바꿀 수 있는 것만 보낸다.
  Future<Profile> update({String? displayName, int? reviewHour, String? timezone}) async {
    try {
      final id = _client.auth.currentUser!.id;
      final patch = <String, Object?>{
        if (displayName != null) 'display_name': displayName,
        if (reviewHour != null) 'review_hour': reviewHour,
        if (timezone != null) 'timezone': timezone,
      };
      final row =
          await _client.from('profiles').update(patch).eq('id', id).select().single().withTimeout();
      return Profile.fromMap(row);
    } catch (e, st) {
      throw mapSupabaseError(e, st);
    }
  }

  /// 프로필 사진의 **경로**를 기록한다. null 이면 기본 이미지로 되돌린 것.
  ///
  /// URL 이 아니라 경로를 넣는 이유: 버킷이 비공개라 보는 순간마다 서명 URL 을 새로 받는데,
  /// 서명 URL 은 만료되므로 DB 에 넣으면 얼마 뒤부터 못 여는 링크가 남는다.
  ///
  /// `avatar_path` 는 profiles 의 컬럼 단위 update grant 목록에 들어 있어야 한다
  /// (`20260101000012_avatar_storage.sql`). 빠지면 여기서 42501 로 막힌다.
  Future<Profile> setAvatarPath(String? path) async {
    try {
      final id = _client.auth.currentUser!.id;
      final row = await _client
          .from('profiles')
          .update({'avatar_path': path})
          .eq('id', id)
          .select()
          .single()
          .withTimeout();
      return Profile.fromMap(row);
    } catch (e, st) {
      throw mapSupabaseError(e, st);
    }
  }

  Future<List<Product>> products() async {
    try {
      final rows = await _client
          .from('products')
          .select()
          .eq('is_active', true)
          .order('sort_order')
          .withTimeout();
      return rows.map((r) => Product.fromMap(r)).toList();
    } catch (e, st) {
      throw mapSupabaseError(e, st);
    }
  }
}

final profileRepositoryProvider =
    Provider<ProfileRepository>((ref) => ProfileRepository(ref.watch(supabaseProvider)));

final profileProvider = FutureProvider<Profile>((ref) {
  ref.watch(currentUserProvider);
  return ref.watch(profileRepositoryProvider).me();
});

/// 프로필 사진을 열 서명 URL. 화면이 뜰 때마다(autoDispose) 새로 받는다 —
/// 서명 URL 은 만료되므로 오래 들고 있으면 사진이 조용히 안 나오게 된다.
///
/// 사진이 없으면 null 이고, 서명에 실패해도 프로필 화면 전체를 오류로 만들지 않는다.
/// 사진 한 장 때문에 닉네임을 못 고치게 되는 건 과한 실패다.
final avatarUrlProvider = FutureProvider.autoDispose<String?>((ref) async {
  final me = await ref.watch(profileProvider.future);
  final path = me.avatarPath;
  if (path == null || path.isEmpty) return null;
  try {
    return await ref.watch(storageRepositoryProvider).signedAvatarUrl(path);
  } catch (_) {
    return null;
  }
});

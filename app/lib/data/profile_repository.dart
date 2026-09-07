import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/models.dart';
import 'supabase.dart';

class ProfileRepository {
  ProfileRepository(this._client);
  final SupabaseClient _client;

  Future<Profile> me() async {
    try {
      final id = _client.auth.currentUser!.id;
      final row = await _client.from('profiles').select().eq('id', id).single();
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
      final row = await _client.from('profiles').update(patch).eq('id', id).select().single();
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
          .order('sort_order');
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

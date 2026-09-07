import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/bootstrap.dart';

/// 홈이 기기에 적어 두는 것.
///
/// 서버에 둘 만한 값이 아니다 — "이 공지를 닫았다" 와 "마지막으로 이걸 봤다" 는
/// 기기마다 다른 게 자연스럽고, 서버에 두면 그만큼 계정에 붙는 기록이 늘어난다.
class HomePrefs {
  const HomePrefs(this._prefs);
  final SharedPreferences _prefs;

  static const _kDismissed = 'home_dismissed_notices_v1';
  static const _kLastOpened = 'home_last_opened_v1';
  static const _kLastOpenedAt = 'home_last_opened_at_v1';

  /// 닫은 공지는 다시 안 띄운다. **id 로 기억한다** — 내용이 바뀌면 새 공지이고,
  /// 새 공지는 닫은 적이 없으니 다시 떠야 한다.
  ///
  /// 목록이 무한히 자라지 않게 최근 것만 남긴다. 오래된 공지는 어차피 만료된다.
  Set<String> get dismissedNotices =>
      (_prefs.getStringList(_kDismissed) ?? const <String>[]).toSet();

  Future<void> dismissNotice(String id) async {
    final list = [..._prefs.getStringList(_kDismissed) ?? const <String>[], id];
    await _prefs.setStringList(_kDismissed, list.length <= 30 ? list : list.sublist(list.length - 30));
  }

  /// 마지막으로 연 학습지. "이어서 하기" 가 여기서 나온다.
  ///
  /// 서버의 응답·필기 시각으로도 알 수 있지만, 그건 **쓴 것**이고 이건 **본 것**이다.
  /// 읽기만 하고 나온 학습지도 이어서 볼 대상이라 기기가 기억하는 편이 맞다.
  String? get lastOpenedWorksheetId => _prefs.getString(_kLastOpened);

  DateTime? get lastOpenedAt {
    final raw = _prefs.getString(_kLastOpenedAt);
    return raw == null ? null : DateTime.tryParse(raw)?.toLocal();
  }

  Future<void> rememberOpened(String worksheetId) async {
    await _prefs.setString(_kLastOpened, worksheetId);
    await _prefs.setString(_kLastOpenedAt, DateTime.now().toUtc().toIso8601String());
  }

  /// 로그아웃에서 부른다. 다음 사람의 홈에 앞사람이 보던 학습지가 뜨면 안 된다.
  Future<void> clear() async {
    await _prefs.remove(_kLastOpened);
    await _prefs.remove(_kLastOpenedAt);
    await _prefs.remove(_kDismissed);
  }
}

final homePrefsProvider = Provider<HomePrefs?>((ref) {
  final prefs = ref.watch(sharedPrefsProvider).valueOrNull;
  return prefs == null ? null : HomePrefs(prefs);
});

/// 화면이 부르기 좋게 감싼다. prefs 가 아직 없으면 조용히 아무것도 안 한다 —
/// 마지막으로 본 학습지를 못 적었다고 사용자에게 알릴 일은 없다.
Future<void> rememberOpenedWorksheet(WidgetRef ref, String worksheetId) async {
  final prefs = ref.read(homePrefsProvider);
  if (prefs == null) return;
  unawaited(prefs.rememberOpened(worksheetId));
}

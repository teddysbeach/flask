import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/bootstrap.dart';
import '../../core/logger.dart';

/// 화면 테마(시스템/라이트/다크).
///
/// 저장은 `LocalFlags.themeMode` 한 곳에서만 한다. 서버에 두지 않는 이유는
/// 기기마다 다르게 쓰는 설정이기 때문이다 — 아이패드는 밝게, 폰은 어둡게 쓰는 사람이 있다.
class ThemeModeController extends StateNotifier<ThemeMode> {
  ThemeModeController(Ref ref)
      : _ref = ref,
        super(themeModeFromKey(_readKey(ref)));

  final Ref _ref;

  Future<void> set(ThemeMode mode) async {
    if (mode == state) return;
    state = mode;
    try {
      await _ref.read(localFlagsProvider).setThemeMode(themeModeKey(mode));
    } catch (e, st) {
      // 저장이 실패해도 이번 실행 동안은 바뀐 채로 둔다. 화면이 되돌아가면
      // 사용자는 자기가 잘못 눌렀다고 생각한다.
      AppLogger.error('theme mode save failed', error: e, stack: st);
    }
  }

  /// 설정을 아직 못 읽었으면(첫 프레임) 시스템을 따른다 — 여기서 던지면 앱이 안 뜬다.
  static String _readKey(Ref ref) {
    try {
      return ref.read(localFlagsProvider).themeMode;
    } catch (_) {
      return 'system';
    }
  }
}

ThemeMode themeModeFromKey(String key) => switch (key) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };

String themeModeKey(ThemeMode mode) => switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };

/// 설정 화면에 그대로 찍는 이름.
String themeModeLabel(ThemeMode mode) => switch (mode) {
      ThemeMode.light => '라이트',
      ThemeMode.dark => '다크',
      ThemeMode.system => '시스템 설정 따르기',
    };

final themeModeProvider =
    StateNotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);

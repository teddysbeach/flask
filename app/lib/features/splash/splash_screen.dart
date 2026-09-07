import 'package:flutter/material.dart';
import 'package:onpar_design_system/onpar_design_system.dart';

import '../../core/env.dart';

/// 앱을 켜자마자 보이는 화면.
///
/// **여기서는 아무 판정도 하지 않는다.** 어디로 보낼지는 라우터가 정한다
/// (설정 없음 → 점검 → 강제 업데이트 → 온보딩 → 약관 → 로그인).
/// 화면마다 그 순서를 다시 짐작하면 반드시 어딘가에서 어긋난다.
/// 그래서 이 화면이 하는 일은 브랜드를 보여 주며 기다리는 것뿐이다.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    return Scaffold(
      backgroundColor: p.surfaceBase,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(DsSpace.s8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const OnparLogo(symbolHeight: 92),
                const SizedBox(height: DsSpace.s6),
                Text(
                  '배우고 싶은 걸 넣으면, 학습지가 나와요',
                  textAlign: TextAlign.center,
                  style: dsTextStyle(DsType.body, p.textSecondary),
                ),
                const SizedBox(height: DsSpace.s12),
                if (Env.isConfigured)
                  Semantics(
                    label: '앱을 준비하는 중',
                    liveRegion: true,
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(color: p.brandPrimary, strokeWidth: 3),
                    ),
                  )
                else
                  const _MissingConfigNotice(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 설정(`--dart-define`)이 비어 있으면 앱은 뜨지만 서버를 못 부른다.
/// 무한 스피너로 두면 사용자는 자기 인터넷을 의심한다 — 조용히, 그러나 분명하게 말한다.
class _MissingConfigNotice extends StatelessWidget {
  const _MissingConfigNotice();

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(DsSpace.s4),
        decoration: BoxDecoration(
          color: p.statusBgWarning,
          borderRadius: BorderRadius.circular(DsRadius.lg),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DsIcon(DsIcons.warning, size: 20, color: p.statusWarning),
            const SizedBox(height: DsSpace.s2),
            Text(
              '설정이 없어요',
              textAlign: TextAlign.center,
              style: dsTextStyle(DsType.h3, p.textPrimary),
            ),
            const SizedBox(height: DsSpace.s1),
            Text(
              '이 빌드에는 서버 설정이 들어 있지 않아서 접속할 수 없어요.\n'
              '${Env.supportEmail} 로 알려 주시면 확인할게요.',
              textAlign: TextAlign.center,
              style: dsTextStyle(DsType.caption, p.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

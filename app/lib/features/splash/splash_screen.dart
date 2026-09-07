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
                // 앱을 켠 첫 0.5초다. 로고가 이미 놓여 있으면 '기다렸다' 로 읽히고,
                // 살짝 커지며 놓이면 '지금 열렸다' 로 읽힌다. 이 화면에만 쓰는 강조 곡선.
                const _LogoEntrance(),
                const SizedBox(height: DsSpace.s6),
                DsFadeSlide(
                  delay: dsStaggerDelay(2),
                  child: Text(
                    '배우고 싶은 걸 넣으면, 학습지가 나와요',
                    textAlign: TextAlign.center,
                    style: dsTextStyle(DsType.body, p.textSecondary),
                  ),
                ),
                const SizedBox(height: DsSpace.s12),
                if (Env.isConfigured)
                  Semantics(
                    label: '앱을 준비하는 중',
                    liveRegion: true,
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(color: p.brandText, strokeWidth: 3),
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

/// 로고가 놓이는 방식. 페이드와 함께 0.94 → 1 로 커진다.
///
/// 커지는 폭이 이보다 크면 '튀어나온다'가 되고, 스플래시에서 튀어나오는 것은
/// 브랜드가 아니라 광고처럼 보인다.
class _LogoEntrance extends StatefulWidget {
  const _LogoEntrance();

  @override
  State<_LogoEntrance> createState() => _LogoEntranceState();
}

class _LogoEntranceState extends State<_LogoEntrance> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: DsMotion.slower)..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const logo = OnparLogo(symbolHeight: 92);
    if (dsReduceMotion(context)) return logo;

    final curved = _c.drive(CurveTween(curve: DsCurve.emphasized));
    return FadeTransition(
      opacity: curved,
      alwaysIncludeSemantics: true,
      child: ScaleTransition(scale: Tween(begin: 0.94, end: 1.0).animate(curved), child: logo),
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

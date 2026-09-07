import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:onpar_design_system/onpar_design_system.dart';

import '../../core/analytics.dart';
import '../../core/bootstrap.dart';
import '../../core/routes.dart';
import 'onboarding_demos.dart';

/// 첫 실행 워크스루 네 장.
///
/// 기능을 나열하지 않는다. 네 장이 답하는 것은 하나다 — **"이걸 켜면 내 시간에 무슨 일이
/// 일어나는가."** 그래서 넷 다 그림이 아니라 **움직이는 데모**고, 셋째 장은 아예 손으로
/// 만져진다. 온보딩에서 한 번이라도 획을 그은 사람과 아닌 사람은 그 뒤 행동이 다르다.
///
/// 순서에도 이유가 있다.
///
///   ① 무엇을 넣으면 무엇이 나오는가 (거래를 먼저 밝힌다)
///   ② 나오는 것이 왜 문제집과 다른가 (값을 치를 이유)
///   ③ 그걸로 내가 무엇을 하는가 (직접 해 본다)
///   ④ 그 뒤에 앱이 나에게 무엇을 하는가 (계속 열 이유)
///
/// ④ 를 마지막에 두는 것이 중요하다. 알림을 첫 장에서 말하면 "귀찮게 하는 앱" 으로
/// 읽히고, 만들고 풀어 본 다음에 말하면 "지켜 주는 앱" 이 된다.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _index = 0;

  /// 셋째 장에서 직접 그어 봤는가. 온보딩을 고칠 때 볼 수 있는 신호 중
  /// 가장 뜻이 분명한 것이라 완료 이벤트에 함께 싣는다(획 자체는 어디에도 안 남는다).
  bool _drew = false;

  static const _titles = <String>[
    '배우고 싶은 걸 적으면\n학습지 한 장이 나와요',
    '문제집과 순서가 달라요',
    '화면에 바로 손으로 풀어요',
    '잊을 때쯤 다시 물어볼게요',
  ];

  static const _bodies = <String>[
    '“이차함수의 판별식”, “칸트의 정언명령” 처럼 한 줄이면 돼요.\n40초쯤 뒤에 25분짜리 학습지 한 장이 나와요.',
    '설명을 먼저 읽지 않아요. 먼저 틀려 보고,\n왜 틀렸는지 확인한 다음에 개념을 봐요.\n순서를 바꾸면 같은 내용도 더 오래 남아요.',
    '인쇄하지 않아도 돼요. 애플펜슬의 필압이 그대로 살아 있어요.\n위 학습지에 직접 써 보세요 — 지금 쓴 것도 진짜로 그려져요.',
    '한 번 푼 것은 시간이 지나면 흐려져요.\n1일 · 3일 · 7일 · 16일 · 35일에\n문제를 하나씩 다시 보내 드려요.',
  ];

  static const _pageCount = 4;

  bool get _isLast => _index == _pageCount - 1;

  @override
  void initState() {
    super.initState();
    ref.read(analyticsProvider).track(AnalyticsEvent.onboardingStart);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish({required bool skipped}) async {
    // 온보딩을 봤다는 사실은 기기에 남는다 — 건너뛰어도 마찬가지다.
    // 안 남기면 앱을 켤 때마다 같은 장들을 다시 보게 된다.
    final analytics = ref.read(analyticsProvider);
    // 어디까지 보고 건너뛰었는지가 온보딩을 고칠 때 쓰는 유일한 단서다.
    if (skipped) {
      analytics.track(AnalyticsEvent.onboardingSkip,
          props: {'page': _index, 'pages': _pageCount});
    } else {
      analytics.track(AnalyticsEvent.onboardingComplete,
          props: {'pages': _pageCount, 'count': _drew ? 1 : 0});
    }
    await ref.read(localFlagsProvider).setOnboarded(true);
    if (!mounted) return;
    context.go(Routes.consent);
  }

  void _next() {
    if (_isLast) {
      unawaited(_finish(skipped: false));
      return;
    }
    _controller.nextPage(
      duration: dsDuration(context, DsMotion.slow),
      curve: DsCurve.standard,
    );
  }

  Widget _demoFor(int i) => switch (i) {
        0 => TopicToSheetDemo(active: _index == 0),
        1 => WorksheetAnatomyDemo(active: _index == 1),
        2 => InkDemo(
            active: _index == 2,
            onFirstStroke: () {
              if (!_drew) setState(() => _drew = true);
            },
          ),
        _ => ReviewCurveDemo(active: _index == 3),
      };

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    return Scaffold(
      backgroundColor: p.surfaceBase,
      body: SafeArea(
        child: Column(
          children: [
            // 첫 화면부터 이름을 보여 준다. 장마다 그림이 바뀌어도 로고는 그대로 있어
            // "무슨 앱을 켰는지" 를 놓치지 않게 한다.
            Padding(
              padding: const EdgeInsets.fromLTRB(DsSpace.s4, DsSpace.s2, DsSpace.s2, 0),
              child: Row(
                children: [
                      const OnparLogo(layout: OnparLogoLayout.inline, symbolHeight: 26),
                      const Spacer(),
                      TextButton(
                        onPressed: () => unawaited(_finish(skipped: true)),
                        child: const Text('건너뛰기'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: _pageCount,
                    onPageChanged: (i) => setState(() => _index = i),
                    // 필기 장에서는 가로로 끄는 손짓이 필기와 싸운다. 그 장만 페이지를
                    // 손짓으로 넘기지 않게 두고, 넘기는 일은 아래 버튼이 맡는다.
                    physics: _index == 2
                        ? const NeverScrollableScrollPhysics()
                        : const ClampingScrollPhysics(),
                    itemBuilder: (context, i) => _WalkthroughPage(
                      title: _titles[i],
                      body: _bodies[i],
                      demo: _demoFor(i),
                    ),
                  ),
                ),
                _Dots(count: _pageCount, index: _index),
                Padding(
                  padding: const EdgeInsets.fromLTRB(DsSpace.s6, DsSpace.s4, DsSpace.s6, DsSpace.s6),
                  child: FilledButton(
                    onPressed: _next,
                    child: DsSwitcher(
                      child: Text(_isLast ? '시작하기' : '다음', key: ValueKey(_isLast)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }

    /// 한 장의 뼈대: 데모가 위, 말이 아래.
    ///
    /// 반대로 두면 사용자는 글을 읽다가 그림을 발견한다. 그림이 먼저 눈에 들어와야
    /// 글이 그림의 설명으로 읽히고, 그 순서라야 세 줄이 길게 느껴지지 않는다.
    class _WalkthroughPage extends StatelessWidget {
      const _WalkthroughPage({required this.title, required this.body, required this.demo});

      final String title;
      final String body;
      final Widget demo;

      @override
      Widget build(BuildContext context) {
        final p = DsTheme.of(context);
        // 글꼴을 크게 쓰는 사용자에게도 잘려나가는 곳이 없도록 항상 스크롤 가능하게 둔다.
        // 그리고 남는 공간이 있으면 가운데로 모은다 — 큰 화면에서 위쪽에만 몰려 있으면
        // 아래 절반이 "아직 안 만들어진 곳" 처럼 보인다.
        return LayoutBuilder(
          builder: (context, c) => SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: DsSpace.s6, vertical: DsSpace.s4),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: c.maxHeight - DsSpace.s8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
              const SizedBox(height: DsSpace.s2),
              // 데모 · 제목 · 설명이 차례로 놓이면 '설명을 듣는다' 가 되고,
              // 한꺼번에 뜨면 '읽어야 할 것이 많다' 가 된다.
              DsFadeSlide(
                duration: DsMotion.slower,
                curve: DsCurve.emphasized,
                child: demo,
              ),
              const SizedBox(height: DsSpace.s8),
              DsFadeSlide(
                delay: dsStaggerDelay(2),
                child: Text(title,
                    textAlign: TextAlign.center, style: dsTextStyle(DsType.h2, p.textPrimary)),
              ),
              const SizedBox(height: DsSpace.s3),
              DsFadeSlide(
                delay: dsStaggerDelay(3),
                child: Text(body,
                    textAlign: TextAlign.center, style: dsTextStyle(DsType.body, p.textSecondary)),
              ),
              const SizedBox(height: DsSpace.s4),
            ],
          ),
        ),
      ),
    );
  }
}

/// 현재 위치 표시. 색만으로 알리지 않도록 스크린리더에는 "4장 중 1장" 으로 읽어 준다.
class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    return Semantics(
      label: '$count장 중 ${index + 1}장',
      liveRegion: true,
      child: ExcludeSemantics(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < count; i++)
              AnimatedContainer(
                duration: dsDuration(context, DsMotion.base),
                curve: DsCurve.standard,
                margin: const EdgeInsets.symmetric(horizontal: DsSpace.s1),
                height: 8,
                width: i == index ? 24 : 8,
                decoration: BoxDecoration(
                  color: i == index ? p.brandText : p.borderDefault,
                  borderRadius: BorderRadius.circular(DsRadius.full),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

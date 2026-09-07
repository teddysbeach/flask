import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:onpar_design_system/onpar_design_system.dart';

import '../../core/analytics.dart';
import '../../core/bootstrap.dart';
import '../../core/routes.dart';

/// 첫 실행 안내 세 장.
///
/// 기능 목록이 아니라 "이 앱을 켜면 무엇이 일어나는가" 를 말한다.
/// 세 장을 넘긴 뒤에 사용자가 무엇을 기대해야 하는지 알면 성공이다.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _index = 0;

  static const _pages = <_Page>[
    _Page(
      icon: DsIcons.create,
      title: '배우고 싶은 걸 적으면\n학습지가 나와요',
      body: '"이차함수", "칸트의 정언명령" 처럼 궁금한 것을 넣어 주세요.\n'
          '문제 → 예상 → 관찰 → 개념 → 연습 → 확인, 6단계로 짜인 학습지를 만들어 드려요.',
    ),
    _Page(
      icon: DsIcons.pen,
      title: '애플펜슬로 바로 풀어요',
      body: '인쇄하지 않아도 돼요. 화면에 그대로 쓰고 지우고 형광펜을 그을 수 있어요.\n'
          '손글씨가 불편한 날에는 타이핑으로 답해도 돼요.',
    ),
    _Page(
      icon: DsIcons.review,
      title: '잊을 때쯤 복습 문제가 와요',
      body: '한 번 푼 것은 시간이 지나면 흐려져요.\n'
          '망각곡선에 맞춰 다시 물어볼 테니, 알림이 오면 몇 문제만 풀어 주세요.',
    ),
  ];

  bool get _isLast => _index == _pages.length - 1;

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
    // 안 남기면 앱을 켤 때마다 같은 세 장을 다시 보게 된다.
    final analytics = ref.read(analyticsProvider);
    // 어디까지 보고 건너뛰었는지가 온보딩을 고칠 때 쓰는 유일한 단서다.
    if (skipped) {
      analytics.track(AnalyticsEvent.onboardingSkip, props: {'page': _index, 'pages': _pages.length});
    } else {
      analytics.track(AnalyticsEvent.onboardingComplete, props: {'pages': _pages.length});
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
    _controller.nextPage(duration: DsMotion.durationBase, curve: DsMotion.easingStandard);
  }

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    return Scaffold(
      backgroundColor: p.surfaceBase,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: DsSpace.s2),
                child: TextButton(
                  onPressed: () => unawaited(_finish(skipped: true)),
                  child: const Text('건너뛰기'),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) => _OnboardingPage(page: _pages[i]),
              ),
            ),
            _Dots(count: _pages.length, index: _index),
            Padding(
              padding: const EdgeInsets.fromLTRB(DsSpace.s6, DsSpace.s6, DsSpace.s6, DsSpace.s6),
              child: FilledButton(
                onPressed: _next,
                child: Text(_isLast ? '시작하기' : '다음'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Page {
  const _Page({required this.icon, required this.title, required this.body});
  final List<String> icon;
  final String title;
  final String body;
}

class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({required this.page});

  final _Page page;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    // 글꼴을 크게 쓰는 사용자에게도 잘려나가는 곳이 없도록 항상 스크롤 가능하게 둔다.
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: DsSpace.s6, vertical: DsSpace.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: DsSpace.s8),
          Container(
            padding: const EdgeInsets.all(DsSpace.s6),
            decoration: BoxDecoration(color: p.brandPrimarySubtle, shape: BoxShape.circle),
            child: DsIcon(page.icon, size: 40, color: p.brandPrimary),
          ),
          const SizedBox(height: DsSpace.s8),
          Text(page.title, textAlign: TextAlign.center, style: dsTextStyle(DsType.h1, p.textPrimary)),
          const SizedBox(height: DsSpace.s4),
          Text(page.body, textAlign: TextAlign.center, style: dsTextStyle(DsType.bodyLg, p.textSecondary)),
          const SizedBox(height: DsSpace.s8),
        ],
      ),
    );
  }
}

/// 현재 위치 표시. 색만으로 알리지 않도록 스크린리더에는 "3장 중 1장" 으로 읽어 준다.
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
                duration: DsMotion.durationBase,
                curve: DsMotion.easingStandard,
                margin: const EdgeInsets.symmetric(horizontal: DsSpace.s1),
                height: 8,
                width: i == index ? 24 : 8,
                decoration: BoxDecoration(
                  color: i == index ? p.brandPrimary : p.borderDefault,
                  borderRadius: BorderRadius.circular(DsRadius.full),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

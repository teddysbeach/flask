import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:onpar_design_system/onpar_design_system.dart';

import '../../core/connectivity.dart';
import '../../ui/states/app_state_views.dart';

/// 탭 네 개를 감싸는 껍데기. 탭마다 스택이 따로 살아 있어야 해서
/// `StatefulNavigationShell` 을 그대로 body 로 쓴다(라우터가 만들어 넘긴다).
///
/// 오프라인 배너는 탭 **위**에 둔다. 탭 안쪽에 두면 화면마다 배너가 생겼다 없어졌다 하고,
/// 아래에 두면 탭 바에 가려 안 보인다.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _tabs = <_ShellTab>[
    _ShellTab(icon: DsIcons.home, label: '홈'),
    _ShellTab(icon: DsIcons.library, label: '서재'),
    _ShellTab(icon: DsIcons.review, label: '복습'),
    _ShellTab(icon: DsIcons.settings, label: '설정'),
  ];

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  void _onTap(int index) {
    // 이미 있는 탭을 다시 누르면 그 탭의 첫 화면으로 돌아간다(iOS 관습).
    final shell = widget.navigationShell;
    shell.goBranch(index, initialLocation: index == shell.currentIndex);
  }

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    final offline = ref.watch(netStatusProvider).valueOrNull == NetStatus.offline;

    return Scaffold(
      backgroundColor: p.surfaceBase,
      body: Column(
        children: [
          // 배너가 생기고 사라질 때 아래 화면이 툭 밀리지 않게 자리도 같이 연다.
          AnimatedSize(
            duration: dsDuration(context, DsMotion.base),
            curve: DsCurve.standard,
            alignment: Alignment.topCenter,
            child: offline
                ? const SafeArea(bottom: false, child: OfflineBanner())
                : const SizedBox(width: double.infinity),
          ),
          // 탭 사이는 밀지 않고 **겹쳐 넘긴다.** 탭은 나란히 있는 것이지
          // 앞뒤로 있는 것이 아니라서, 좌우로 밀면 "뒤로 갔다"는 잘못된 신호가 된다.
          Expanded(child: _TabCrossFade(child: widget.navigationShell)),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: widget.navigationShell.currentIndex,
        onDestinationSelected: _onTap,
        backgroundColor: p.surfaceRaised,
        indicatorColor: p.brandPrimarySubtle,
        surfaceTintColor: Colors.transparent,
        // 색만으로 선택을 알리지 않는다 — 글자는 언제나 보이고, 선택된 칸은 알약 모양이 붙는다.
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [
          for (var i = 0; i < HomeShell._tabs.length; i++)
            NavigationDestination(
              icon: DsIcon(HomeShell._tabs[i].icon, size: 22, color: p.textTertiary),
              selectedIcon: DsIcon(HomeShell._tabs[i].icon, size: 22, color: p.brandTextOnSubtle),
              label: HomeShell._tabs[i].label,
              // 스크린리더는 label 로 "홈, 4개 중 1번째, 선택됨" 을 읽는다.
              // 아이콘에 라벨을 또 달면 같은 말이 두 번 나온다 — 그래서 DsIcon 은 장식으로 둔다.
              tooltip: HomeShell._tabs[i].label,
            ),
        ],
      ),
    );
  }
}

/// 탭이 바뀔 때의 크로스 페이드.
///
/// [StatefulNavigationShell] 은 IndexedStack 이라 상태를 잃지 않는 대신 전환이 없다.
/// 상태를 지키면서 전환만 얹기 위해, 인덱스가 바뀐 순간에만 짧게 밝기를 태운다.
class _TabCrossFade extends StatefulWidget {
  const _TabCrossFade({required this.child});

  final StatefulNavigationShell child;

  @override
  State<_TabCrossFade> createState() => _TabCrossFadeState();
}

class _TabCrossFadeState extends State<_TabCrossFade> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: DsMotion.base, value: 1);

  @override
  void didUpdateWidget(covariant _TabCrossFade old) {
    super.didUpdateWidget(old);
    if (old.child.currentIndex != widget.child.currentIndex) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (dsReduceMotion(context)) return widget.child;
    final curved = _c.drive(CurveTween(curve: DsCurve.enter));
    return FadeTransition(
      opacity: curved,
      alwaysIncludeSemantics: true,
      child: AnimatedBuilder(
        animation: curved,
        builder: (_, child) => Transform.translate(
          // 8dp 면 '자리를 잡는다' 로 읽히고, 그보다 크면 '어디선가 온다' 로 읽힌다.
          offset: Offset(0, 8 * (1 - curved.value)),
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}

class _ShellTab {
  const _ShellTab({required this.icon, required this.label});
  final List<String> icon;
  final String label;
}

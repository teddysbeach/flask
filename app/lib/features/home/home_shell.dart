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
class HomeShell extends ConsumerWidget {
  const HomeShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _tabs = <_ShellTab>[
    _ShellTab(icon: DsIcons.home, label: '홈'),
    _ShellTab(icon: DsIcons.library, label: '서재'),
    _ShellTab(icon: DsIcons.review, label: '복습'),
    _ShellTab(icon: DsIcons.settings, label: '설정'),
  ];

  void _onTap(int index) {
    // 이미 있는 탭을 다시 누르면 그 탭의 첫 화면으로 돌아간다(iOS 관습).
    navigationShell.goBranch(index, initialLocation: index == navigationShell.currentIndex);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = DsTheme.of(context);
    final offline = ref.watch(netStatusProvider).valueOrNull == NetStatus.offline;

    return Scaffold(
      backgroundColor: p.surfaceBase,
      body: Column(
        children: [
          if (offline) SafeArea(bottom: false, child: const OfflineBanner()),
          Expanded(child: navigationShell),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: _onTap,
        backgroundColor: p.surfaceRaised,
        indicatorColor: p.brandPrimarySubtle,
        surfaceTintColor: Colors.transparent,
        // 색만으로 선택을 알리지 않는다 — 글자는 언제나 보이고, 선택된 칸은 알약 모양이 붙는다.
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [
          for (var i = 0; i < _tabs.length; i++)
            NavigationDestination(
              icon: DsIcon(_tabs[i].icon, size: 22, color: p.textTertiary),
              selectedIcon: DsIcon(_tabs[i].icon, size: 22, color: p.brandTextOnSubtle),
              label: _tabs[i].label,
              // 스크린리더는 label 로 "홈, 4개 중 1번째, 선택됨" 을 읽는다.
              // 아이콘에 라벨을 또 달면 같은 말이 두 번 나온다 — 그래서 DsIcon 은 장식으로 둔다.
              tooltip: _tabs[i].label,
            ),
        ],
      ),
    );
  }
}

class _ShellTab {
  const _ShellTab({required this.icon, required this.label});
  final List<String> icon;
  final String label;
}

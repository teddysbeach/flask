import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:onpar_design_system/onpar_design_system.dart';

import '../../core/routes.dart';
import '../../core/bootstrap.dart';
import '../../data/profile_repository.dart';
import '../../domain/models.dart';
import '../../ui/states/app_state_views.dart';
import '../library/library_controller.dart';
import '../notifications/notification_prefs.dart';
import '../library/worksheet_tile.dart';
// 복습 데이터는 복습 기능 담당이 만든다. 홈은 개수만 읽는다.
import '../review/review_providers.dart';
import '../settings/settings_tile.dart';
import 'home_sections.dart';

/// 앱을 열면 처음 보이는 곳.
///
/// **홈은 "지금 뭘 할까" 에 먼저 답하고, 그 아래로 내가 만든 전부가 이어진다.**
/// 스크롤 한 번이면 앱 전체가 보인다.
///
/// 순서에는 이유가 있다.
///   ① 남은 장수 — 만들기 전에 알아야 하는 유일한 숫자.
///   ② 오늘 복습 — **있을 때만.** 없는 날 빈 카드가 자리를 차지하면 홈이 무거워진다.
///   ③ 만드는 중 — **있을 때만.** 기다리는 사람에게는 이게 가장 위여야 한다.
///   ④ 만들기 — 이 앱에서 하는 일 그 자체.
///   ⑤ 모든 학습지 — 날짜로 묶어서 전부. 사람은 자기 학습지를 제목이 아니라
///      "그때 무엇을 하고 있었는지" 로 기억한다.
///
/// 목록은 서재(찾기) 탭과 **같은 컨트롤러**를 본다. 두 벌로 두면 한쪽에서 지운 학습지가
/// 다른 쪽에 남고, 같은 페이지를 두 번 받아 온다. 홈은 필터·검색을 적용하지 않은
/// `items` 를, 찾기는 걸러진 `visible` 을 그린다.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  /// 바닥 가까이 오면 다음 페이지. 중복 요청은 컨트롤러가 막는다.
  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.maxScrollExtent - _scroll.position.pixels > 480) return;
    unawaited(ref.read(libraryControllerProvider.notifier).loadMore());
  }

  Future<void> _refresh() async {
    ref
      ..invalidate(profileProvider)
      ..invalidate(dueReviewCountProvider);
    // 실패해도 화면은 각자의 오류 상태를 그린다. 여기서 예외가 새면 새로고침
    // 인디케이터가 영원히 돌거나 프레임워크가 빨간 화면을 띄운다.
    await Future.wait<void>([
      _quiet(ref.read(profileProvider.future)),
      _quiet(ref.read(dueReviewCountProvider.future)),
      _quiet(ref.read(libraryControllerProvider.notifier).refresh()),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    final list = ref.watch(libraryControllerProvider);
    // 홈은 거르지 않는다. 찾기 탭에서 필터를 걸어 두었다고 홈이 좁아지면 안 된다.
    final all = list.items;
    final making = all.where((w) => !w.isTerminal).toList(growable: false);
    final groups = groupWorksheetsByDate(all);

    return Scaffold(
      backgroundColor: p.surfaceBase,
      appBar: AppBar(
        title: const Text('ONPAR'),
        // 받은 알림 목록은 여태 **어디서도 들어갈 수 없었다.** 라우트만 있고
        // 누르는 곳이 없어서, 알림을 밀어서 지운 사람은 그걸 되찾을 방법이 없었다.
        actions: const [_NotificationsButton()],
      ),
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: p.brandText,
          onRefresh: _refresh,
          child: CustomScrollView(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(DsSpace.s4, DsSpace.s4, DsSpace.s4, 0),
                sliver: SliverList.list(
                  children: [
                    const _QuotaSection(),
                    // ② 오늘 복습 — 있을 때만.
                    const _TodayReviewSection(),
                    // ③ 만드는 중 — 있을 때만. 기다리는 사람에게 가장 위.
                    for (final w in making) ...[
                      const SizedBox(height: DsSpace.s3),
                      DsFadeSlide(
                        key: ValueKey('making-${w.id}'),
                        child: _MakingCard(worksheet: w),
                      ),
                    ],
                    const SizedBox(height: DsSpace.s3),
                    const _CreateSection(),
                  ],
                ),
              ),
              // ⑤ 모든 학습지.
              if (list.loading && all.isEmpty)
                const SliverPadding(
                  padding: EdgeInsets.fromLTRB(DsSpace.s4, DsSpace.s6, DsSpace.s4, 0),
                  sliver: SliverToBoxAdapter(child: _ListSkeleton()),
                )
              else if (list.error != null && all.isEmpty)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(DsSpace.s4, DsSpace.s8, DsSpace.s4, 0),
                  sliver: SliverToBoxAdapter(
                    child: ErrorView(
                      error: list.error!,
                      onRetry: ref.read(libraryControllerProvider.notifier).refresh,
                    ),
                  ),
                )
              else if (all.isEmpty)
                const SliverPadding(
                  padding: EdgeInsets.fromLTRB(DsSpace.s4, DsSpace.s8, DsSpace.s4, 0),
                  sliver: SliverToBoxAdapter(child: _FirstSheetGuide()),
                )
              else ...[
                for (final group in groups)
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: DsSpace.s4),
                    sliver: SliverList.builder(
                      itemCount: group.items.length + 1,
                      itemBuilder: (context, i) {
                        if (i == 0) {
                          return DateGroupHeader(
                            label: group.label,
                            count: group.items.length,
                          );
                        }
                        final w = group.items[i - 1];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: DsSpace.s2),
                          child: DsFadeSlide(
                            key: ValueKey(w.id),
                            delay: dsStaggerDelay(i - 1),
                            child: WorksheetTile(
                              worksheet: w,
                              onTap: () => openWorksheet(context, w),
                              onRetry: () => openWorksheet(context, w),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                      DsSpace.s4, DsSpace.s4, DsSpace.s4, DsSpace.s12),
                  sliver: SliverToBoxAdapter(child: _ListFooter(state: list)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 결과도 실패도 삼킨다 — 여기서는 "다 끝났다" 만 알면 된다.
Future<void> _quiet(Future<Object?> f) =>
    f.then<void>((_) {}, onError: (Object _, StackTrace __) {});

/// 알림함 버튼. 안 읽은 것이 있으면 점을 붙인다.
///
/// 숫자가 아니라 점인 이유: 알림은 몇 개인지가 중요한 게 아니라 **있는지**가 중요하다.
/// 숫자를 붙이면 사용자는 그 숫자를 0 으로 만들어야 한다는 부담을 진다.
class _NotificationsButton extends ConsumerWidget {
  const _NotificationsButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = DsTheme.of(context);
    final prefs = ref.watch(sharedPrefsProvider).valueOrNull;
    final unread = prefs == null ? 0 : NotificationPrefs(prefs).unreadCount;

    return IconButton(
      tooltip: '알림',
      onPressed: () => context.push(Routes.notifications),
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          DsIcon(DsIcons.review, size: 22, color: p.textSecondary,
              semanticLabel: unread > 0 ? '알림, 안 읽음 $unread개' : '알림'),
          if (unread > 0)
            Positioned(
              right: -1,
              top: -1,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: p.statusDanger,
                  shape: BoxShape.circle,
                  // 아이콘 위에 얹히므로 테두리로 배경과 떼어 놓는다.
                  border: Border.all(color: p.surfaceBase, width: 1.5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── ① 남은 장수 ──────────────────────────────────────────────────────────

class _QuotaSection extends ConsumerWidget {
  const _QuotaSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    return QuotaBar(
      loading: profile.isLoading,
      // 못 읽었을 때 0 으로 두지 않는다 — 0 은 "다 썼다" 라는 뜻이고, 그건 거짓말이다.
      remaining: profile.valueOrNull?.quotaRemaining,
      onCharge: () => context.push(Routes.paywall),
    );
  }
}

// ── ② 오늘 복습 ──────────────────────────────────────────────────────────

class _TodayReviewSection extends ConsumerWidget {
  const _TodayReviewSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = DsTheme.of(context);
    final count = ref.watch(dueReviewCountProvider).valueOrNull ?? 0;
    // 없는 날은 자리도 차지하지 않는다. "오늘은 복습이 없어요" 카드는
    // 아무 일도 안 하면서 홈을 한 칸 밀어낸다.
    if (count == 0) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: DsSpace.s3),
      child: DsFadeSlide(
        child: HomeCard(
          accent: true,
          onTap: () => context.push(Routes.reviewSession),
          child: Row(
            children: [
              DsIcon(DsIcons.review, size: 22, color: p.brandText),
              const SizedBox(width: DsSpace.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('오늘의 복습 $count개',
                        style: dsTextStyle(DsType.bodyLg, p.textPrimary)
                            .copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: DsSpace.s1),
                    Text('잊을 때쯤 다시 꺼내면 기억이 오래가요.',
                        style: dsTextStyle(DsType.caption, p.brandTextOnSubtle)),
                  ],
                ),
              ),
              const ChevronRight(),
            ],
          ),
        ),
      ),
    );
  }
}

// ── ③ 만드는 중 ──────────────────────────────────────────────────────────

/// 아직 만들어지는 중인 학습지.
///
/// 목록 안에도 같은 카드가 있지만 여기에 한 번 더 올린다. 기다리는 사람에게는
/// 이것이 홈의 전부이고, 스크롤해서 찾게 만들 이유가 없다.
class _MakingCard extends StatelessWidget {
  const _MakingCard({required this.worksheet});
  final WorksheetSummary worksheet;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    return HomeCard(
      onTap: () => openWorksheet(context, worksheet),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: p.brandText),
          ),
          const SizedBox(width: DsSpace.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('만드는 중',
                    style: dsTextStyle(DsType.caption, p.textSecondary)),
                const SizedBox(height: DsSpace.s1),
                Text(
                  worksheet.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: dsTextStyle(DsType.bodyLg, p.textPrimary)
                      .copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const ChevronRight(),
        ],
      ),
    );
  }
}

// ── ④ 만들기 ─────────────────────────────────────────────────────────────

class _CreateSection extends StatelessWidget {
  const _CreateSection();

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    return DsFadeSlide(
      delay: dsStaggerDelay(1),
      child: HomeCard(
        // 진입 지점 자체는 이벤트로 남기지 않는다. 화면 조회(/create)는 라우터가 잡고,
        // "만들기 시작" 은 실제로 주문이 나가는 순간에 한 번만 남긴다.
        onTap: () => context.push(Routes.create),
        child: Row(
          children: [
            DsIcon(DsIcons.create, size: 22, color: p.brandText),
            const SizedBox(width: DsSpace.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('새 학습지 만들기',
                      style: dsTextStyle(DsType.bodyLg, p.textPrimary)
                          .copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: DsSpace.s1),
                  Text('배우고 싶은 걸 한 줄 적으면 6단계로 만들어 드려요.',
                      style: dsTextStyle(DsType.caption, p.textSecondary)),
                ],
              ),
            ),
            const ChevronRight(),
          ],
        ),
      ),
    );
  }
}

// ── ⑤ 모든 학습지 ────────────────────────────────────────────────────────

class _FirstSheetGuide extends StatelessWidget {
  const _FirstSheetGuide();

  @override
  Widget build(BuildContext context) => EmptyView(
        icon: DsIcons.library,
        title: '아직 만든 학습지가 없어요',
        description: '여기에 만든 학습지가 전부 쌓여요. 위에서 첫 장을 만들어 보세요.',
      );
}

class _ListSkeleton extends StatelessWidget {
  const _ListSkeleton();

  @override
  Widget build(BuildContext context) => const Column(
        children: [
          WorksheetTileSkeleton(),
          SizedBox(height: DsSpace.s2),
          WorksheetTileSkeleton(),
          SizedBox(height: DsSpace.s2),
          WorksheetTileSkeleton(),
        ],
      );
}

class _ListFooter extends ConsumerWidget {
  const _ListFooter({required this.state});
  final LibraryState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = DsTheme.of(context);
    final controller = ref.read(libraryControllerProvider.notifier);

    if (state.moreError != null) {
      return Column(
        children: [
          Text(state.moreError!.message,
              textAlign: TextAlign.center,
              style: dsTextStyle(DsType.caption, p.textSecondary)),
          const SizedBox(height: DsSpace.s3),
          OutlinedButton(onPressed: controller.retryMore, child: const Text('더 불러오기')),
        ],
      );
    }
    if (state.loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: DsSpace.s4),
        child: Center(child: LoadingView(label: '더 불러오는 중')),
      );
    }
    if (state.endReached) {
      return Center(
        child: Text('여기까지예요', style: dsTextStyle(DsType.caption, p.textTertiary)),
      );
    }
    return const SizedBox(height: DsSpace.s6);
  }
}

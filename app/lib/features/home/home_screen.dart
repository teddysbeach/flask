import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:onpar_design_system/onpar_design_system.dart';

import '../../core/routes.dart';
import '../../core/bootstrap.dart';
import '../../data/notice_repository.dart';
import '../../data/profile_repository.dart';
import '../../data/topic_picks_repository.dart';
import '../../domain/models.dart';
import '../../ui/states/app_state_views.dart';
import '../library/library_controller.dart';
import '../notifications/notification_prefs.dart';
import '../library/worksheet_tile.dart';
// 복습 데이터는 복습 기능 담당이 만든다. 홈은 개수만 읽는다.
import '../review/review_providers.dart';
import '../settings/settings_tile.dart';
import 'home_prefs.dart';
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
      ..invalidate(dueReviewCountProvider)
      ..invalidate(noticesProvider)
      ..invalidate(topicPicksProvider);
    // 실패해도 화면은 각자의 오류 상태를 그린다. 여기서 예외가 새면 새로고침
    // 인디케이터가 영원히 돌거나 프레임워크가 빨간 화면을 띄운다.
    await Future.wait<void>([
      _quiet(ref.read(profileProvider.future)),
      _quiet(ref.read(dueReviewCountProvider.future)),
      _quiet(ref.read(libraryControllerProvider.notifier).refresh()),
      // 공지·추천은 못 받아도 홈이 오류가 되지 않는다. 기다리기만 한다.
      _quiet(ref.read(noticesProvider.future)),
      _quiet(ref.read(topicPicksProvider.future)),
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
                    // ① 공지 — 점검처럼 지금 알아야 하는 것. 닫으면 다시 안 뜬다.
                    const _PinnedNoticeSection(),
                    // ② 이어서 하기 — 하던 것으로 돌아가는 가장 짧은 길.
                    const _ContinueSection(),
                    // ③ 오늘 복습 — 있을 때만.
                    const _TodayReviewSection(),
                    // ④ 만드는 중 — 있을 때만. 기다리는 사람에게 가장 위.
                    for (final w in making) ...[
                      const SizedBox(height: DsSpace.s3),
                      DsFadeSlide(
                        key: ValueKey('making-${w.id}'),
                        child: _MakingCard(worksheet: w),
                      ),
                    ],
                    // ⑤ 이벤트 — 기간이 있는 것. 지나면 서버에서 만료된다.
                    const _EventSection(),
                    const SizedBox(height: DsSpace.s3),
                    // ⑥ 남은 장수 · 충전
                    const _QuotaSection(),
                    const SizedBox(height: DsSpace.s3),
                    // ⑦ 만들기
                    const _CreateSection(),
                    // ⑧ 추천 주제 — 서버가 주면.
                    const _TopicPicksSection(),
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

// ── ① 공지 ───────────────────────────────────────────────────────────────

/// 고정 공지 한 건. **한 건만** — 셋 쌓인 홈은 공지판이지 학습 앱이 아니고,
/// 그렇게 되는 순간 사용자는 배너를 통째로 안 보게 된다. 정작 점검 공지가 떴을 때도.
class _PinnedNoticeSection extends ConsumerStatefulWidget {
  const _PinnedNoticeSection();

  @override
  ConsumerState<_PinnedNoticeSection> createState() => _PinnedNoticeSectionState();
}

class _PinnedNoticeSectionState extends ConsumerState<_PinnedNoticeSection> {
  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    final notice = ref.watch(pinnedNoticeProvider);
    final prefs = ref.watch(homePrefsProvider);
    if (notice == null || prefs == null) return const SizedBox.shrink();
    // 닫은 것은 id 로 기억한다. 내용이 바뀌면 새 공지이고, 새 공지는 다시 떠야 한다.
    if (prefs.dismissedNotices.contains(notice.id)) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: DsSpace.s3),
      child: DsFadeSlide(
        from: DsFrom.above,
        child: Container(
          padding: const EdgeInsets.fromLTRB(DsSpace.s4, DsSpace.s3, DsSpace.s2, DsSpace.s3),
          decoration: BoxDecoration(
            color: p.statusBgInfo,
            borderRadius: BorderRadius.circular(DsRadius.lg),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DsIcon(DsIcons.info, size: 18, color: p.statusInfo),
              const SizedBox(width: DsSpace.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(notice.title,
                        style: dsTextStyle(DsType.body, p.textPrimary)
                            .copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: DsSpace.s1),
                    Text(notice.body,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: dsTextStyle(DsType.caption, p.textSecondary)),
                    const SizedBox(height: DsSpace.s2),
                    // 접힌 본문을 다 보려면 공지 목록으로.
                    GestureDetector(
                      onTap: () => context.push(Routes.notices),
                      child: Text('공지 전체 보기',
                          style: dsTextStyle(DsType.caption, p.brandText)
                              .copyWith(fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '닫기',
                icon: DsIcon(DsIcons.close, size: 16, color: p.textTertiary),
                onPressed: () async {
                  await prefs.dismissNotice(notice.id);
                  if (mounted) setState(() {});
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── ② 이어서 하기 ────────────────────────────────────────────────────────

/// 마지막으로 본 학습지.
///
/// 다시 앱을 여는 사람의 절반은 "하던 것" 을 이어서 하려고 온다. 목록에서 찾게 하면
/// 그 절반이 매번 스크롤을 한다. **한 번 누르면 그 자리로 돌아간다.**
///
/// 오늘 만든 것이면 안 보여준다 — 바로 위 목록 첫 줄에 있는 것을 두 번 보여줄 이유가 없다.
class _ContinueSection extends ConsumerWidget {
  const _ContinueSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = DsTheme.of(context);
    final prefs = ref.watch(homePrefsProvider);
    final id = prefs?.lastOpenedWorksheetId;
    if (id == null) return const SizedBox.shrink();

    final items = ref.watch(libraryControllerProvider).items;
    // 지웠거나 아직 안 받아 온 장이면 조용히 없던 일로 한다.
    final sheet = items.where((w) => w.id == id).firstOrNull;
    if (sheet == null || sheet.status != WorksheetStatus.ready) return const SizedBox.shrink();

    // 방금 만든 장이 목록 맨 위에 있는데 여기에도 띄우면 같은 카드가 두 번이다.
    if (items.isNotEmpty && items.first.id == id) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: DsSpace.s3),
      child: DsFadeSlide(
        child: HomeCard(
          onTap: () => openWorksheet(context, sheet),
          child: Row(
            children: [
              DsIcon(DsIcons.library, size: 22, color: p.brandText),
              const SizedBox(width: DsSpace.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('이어서 하기', style: dsTextStyle(DsType.caption, p.textSecondary)),
                    const SizedBox(height: DsSpace.s1),
                    Text(
                      sheet.displayTitle,
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
        ),
      ),
    );
  }
}

// ── ⑤ 이벤트 ─────────────────────────────────────────────────────────────

/// 기간이 있는 것. 서버가 만료시키면 저절로 사라진다.
///
/// 홈에 상시 광고 배너를 두지 않는 대신, **기간과 다음 행동이 분명한 것 하나**만 둔다.
/// 늘 떠 있는 배너는 사용자가 배너 자리를 통째로 안 보게 만들고, 그러면 정작 필요할 때
/// 아무것도 전달되지 않는다.
class _EventSection extends ConsumerWidget {
  const _EventSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = DsTheme.of(context);
    final event = ref.watch(activeEventProvider);
    if (event == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: DsSpace.s3),
      child: DsFadeSlide(
        child: HomeCard(
          accent: true,
          onTap: event.hasAction ? () => context.push(event.ctaRoute!) : null,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 이벤트라고 말해 준다. 색만으로는 공지와 구분되지 않는다.
                    Text('이벤트',
                        style: dsTextStyle(DsType.caption, p.brandTextOnSubtle)
                            .copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: DsSpace.s1),
                    Text(event.title,
                        style: dsTextStyle(DsType.bodyLg, p.textPrimary)
                            .copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: DsSpace.s1),
                    Text(event.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: dsTextStyle(DsType.caption, p.brandTextOnSubtle)),
                  ],
                ),
              ),
              if (event.hasAction) ...[
                const SizedBox(width: DsSpace.s3),
                FilledButton(
                  onPressed: () => context.push(event.ctaRoute!),
                  style: FilledButton.styleFrom(minimumSize: const Size(88, 44)),
                  child: Text(event.ctaLabel!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── ③ 오늘 복습 ──────────────────────────────────────────────────────────

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

// ── ⑧ 추천 주제 ──────────────────────────────────────────────────────────

/// 이런 주제는 어때요.
///
/// **다른 사람들이 많이 만든 주제가 아니다.** 주제는 사용자가 쓴 글이고 거기에는
/// 남에게 보이면 안 되는 것이 들어온다 — 집계라도 원문이 화면에 나오면 유출이다.
/// 그래서 우리가 고른 것을 서버에서 받는다. 앱에 박아 두면 문구 하나 고치는 데
/// 스토어 심사를 기다려야 한다.
///
/// 못 불러오면 섹션 자체가 없다. 추천은 곁가지라 오류를 낼 자격이 없다.
class _TopicPicksSection extends ConsumerWidget {
  const _TopicPicksSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = DsTheme.of(context);
    final picks = ref.watch(topicPicksProvider).valueOrNull ?? const <TopicPick>[];
    if (picks.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: DsSpace.s6),
      child: DsFadeSlide(
        delay: dsStaggerDelay(2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('이런 주제는 어때요',
                style: dsTextStyle(DsType.h3, p.textPrimary)
                    .copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: DsSpace.s3),
            SizedBox(
              // 가로로 흘린다. 세로로 쌓으면 추천이 목록보다 길어져서, 정작 자기 학습지가
              // 화면 밖으로 밀린다.
              height: 116,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                itemCount: picks.length,
                separatorBuilder: (_, __) => const SizedBox(width: DsSpace.s2),
                itemBuilder: (context, i) => _PickCard(pick: picks[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickCard extends StatelessWidget {
  const _PickCard({required this.pick});
  final TopicPick pick;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    return SizedBox(
      width: 208,
      child: DsPressable(
        // 누르면 만들기 화면에 채워진다. **주문이 바로 나가지 않는다** —
        // 추천을 눌렀다고 장수가 깎이면 그건 함정이다.
        onTap: () => context.push('${Routes.create}?topic=${Uri.encodeQueryComponent(pick.topic)}'),
        child: Container(
          padding: const EdgeInsets.all(DsSpace.s3),
          decoration: BoxDecoration(
            color: p.surfaceRaised,
            borderRadius: BorderRadius.circular(DsRadius.lg),
            border: Border.all(color: p.borderSubtle),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (pick.category != null)
                Text(pick.category!,
                    style: dsTextStyle(DsType.caption, p.brandText)
                        .copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: DsSpace.s1),
              Expanded(
                child: Text(
                  pick.topic,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: dsTextStyle(DsType.body, p.textPrimary)
                      .copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              if (pick.blurb != null)
                Text(
                  pick.blurb!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: dsTextStyle(DsType.caption, p.textSecondary),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── ⑨ 모든 학습지 ────────────────────────────────────────────────────────

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

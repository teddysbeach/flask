import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:onpar_design_system/onpar_design_system.dart';

import '../../core/app_error.dart';
import '../../core/routes.dart';
import '../../data/profile_repository.dart';
import '../../data/worksheet_repository.dart';
import '../../domain/models.dart';
import '../../ui/states/app_state_views.dart';
import '../library/worksheet_tile.dart';
// 복습 데이터는 복습 기능 담당이 만든다. 홈은 개수만 읽는다.
import '../review/review_providers.dart';

/// 홈에 보이는 최근 학습지. 서재의 첫 페이지에서 세 장만 잘라 쓴다 —
/// 홈만을 위한 질의를 따로 두면 정렬 규칙이 두 벌이 된다.
final recentWorksheetsProvider = FutureProvider.autoDispose<List<WorksheetSummary>>((ref) async {
  final all = await ref.watch(worksheetRepositoryProvider).list();
  return all.take(3).toList();
});

/// 앱을 열면 처음 보이는 곳. 세 가지 질문에 답한다:
/// 몇 장 남았나 · 오늘 복습할 게 있나 · 방금 만든 게 어디 있나.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref
      ..invalidate(profileProvider)
      ..invalidate(recentWorksheetsProvider)
      ..invalidate(dueReviewCountProvider);
    // 실패해도 화면은 각자의 오류 상태를 그린다. 여기서 예외가 새면 새로고침 인디케이터가
    // 영원히 돌거나 프레임워크가 빨간 화면을 띄운다.
    await Future.wait<void>([
      _quiet(ref.read(profileProvider.future)),
      _quiet(ref.read(recentWorksheetsProvider.future)),
      _quiet(ref.read(dueReviewCountProvider.future)),
    ]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = DsTheme.of(context);

    return Scaffold(
      backgroundColor: p.surfaceBase,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: p.brandText,
          onRefresh: () => _refresh(ref),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(DsSpace.s4, DsSpace.s4, DsSpace.s4, DsSpace.s12),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              _QuotaCard(onCharge: () => context.push(Routes.paywall)),
              const SizedBox(height: DsSpace.s3),
              _ReviewCard(onStart: () => context.push(Routes.reviewSession)),
              const SizedBox(height: DsSpace.s6),
              const _RecentSection(),
              const SizedBox(height: DsSpace.s8),
              FilledButton(
                onPressed: () {
                  // 진입 지점 자체는 이벤트로 남기지 않는다. 화면 조회(/create)는 라우터가 잡고,
                  // "만들기 시작" 은 실제로 주문이 나가는 순간(create 화면의 제출)에 한 번만 남긴다.
                  // 여기서도 worksheetCreateStart 를 쏘면 한 번 만들 때 두 번 세어진다.
                  context.push(Routes.create);
                },
                child: const Text('학습지 만들기'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 결과도 실패도 삼킨다 — 여기서는 "다 끝났다" 만 알면 된다.
Future<void> _quiet(Future<Object?> f) => f.then<void>((_) {}, onError: (Object _, StackTrace __) {});

// ── 남은 장수 ────────────────────────────────────────────────────────────

class _QuotaCard extends ConsumerWidget {
  const _QuotaCard({required this.onCharge});
  final VoidCallback onCharge;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = DsTheme.of(context);

    return _Card(
      child: dsAsync(
            ref.watch(profileProvider),
            alignment: Alignment.centerLeft,
            loading: () => const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(height: 13, width: 88),
                SizedBox(height: DsSpace.s3),
                SkeletonBox(height: 34, width: 130),
              ],
            ),
            error: (e, st) => _InlineError(
              error: AppError.from(e, st),
              onRetry: () => ref.invalidate(profileProvider),
            ),
            data: (profile) {
              final left = profile.quotaRemaining;
              final empty = left == 0;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('남은 학습지', style: dsTextStyle(DsType.caption, p.textSecondary)),
                  const SizedBox(height: DsSpace.s2),
                  Semantics(
                    liveRegion: true,
                    label: '남은 학습지 $left장',
                    child: ExcludeSemantics(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          DsCounterText('$left',
                              style: dsTextStyle(DsType.display,
                                  empty ? p.textTertiary : p.textPrimary)),
                          const SizedBox(width: DsSpace.s1),
                          Text('장', style: dsTextStyle(DsType.bodyLg, p.textSecondary)),
                        ],
                      ),
                    ),
                  ),
                  if (empty) ...[
                    const SizedBox(height: DsSpace.s3),
                    Text('다 쓰셨어요. 충전하면 이어서 만들 수 있어요.',
                        style: dsTextStyle(DsType.body, p.textSecondary)),
                    const SizedBox(height: DsSpace.s3),
                    FilledButton(onPressed: onCharge, child: const Text('충전하기')),
                  ],
                ],
              );
            },
          ),
    );
  }
}

// ── 오늘 복습 ────────────────────────────────────────────────────────────

class _ReviewCard extends ConsumerWidget {
  const _ReviewCard({required this.onStart});
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = DsTheme.of(context);

    return dsAsync(
          ref.watch(dueReviewCountProvider),
          loading: () => const _Card(
            child: Row(children: [SkeletonBox(height: 18, width: 160)]),
          ),
          // 복습 개수는 홈의 곁가지다. 못 읽었다고 홈 전체를 오류로 덮지 않는다.
          error: (e, st) => _Card(
            child: _InlineError(
              error: AppError.from(e, st),
              onRetry: () => ref.invalidate(dueReviewCountProvider),
            ),
          ),
          data: (count) {
            if (count == 0) {
              return _Card(
                child: Row(
                  children: [
                    DsIcon(DsIcons.success, size: 20, color: p.statusSuccess),
                    const SizedBox(width: DsSpace.s3),
                    Expanded(
                      child: Text('오늘 복습할 문제는 없어요.',
                          style: dsTextStyle(DsType.body, p.textSecondary)),
                    ),
                  ],
                ),
              );
            }
            return _Card(
              onTap: onStart,
              child: Row(
                children: [
                  DsIcon(DsIcons.review, size: 22, color: p.brandText),
                  const SizedBox(width: DsSpace.s3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('오늘 복습할 문제 $count개',
                            style: dsTextStyle(DsType.bodyLg, p.textPrimary)
                                .copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: DsSpace.s1),
                        Text('한 번 더 보면 오래 남아요.',
                            style: dsTextStyle(DsType.caption, p.textSecondary)),
                      ],
                    ),
                  ),
                  DsIcon(DsIcons.back, size: 18, color: p.textTertiary),
                ],
              ),
            );
          },
        );
  }
}

// ── 최근 학습지 ──────────────────────────────────────────────────────────

class _RecentSection extends ConsumerWidget {
  const _RecentSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = DsTheme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('최근 학습지',
                  style: dsTextStyle(DsType.h3, p.textPrimary)
                      .copyWith(fontWeight: FontWeight.w700)),
            ),
            TextButton(
              onPressed: () => context.go(Routes.library),
              child: const Text('전체 보기'),
            ),
          ],
        ),
        const SizedBox(height: DsSpace.s2),
        dsAsync(
              ref.watch(recentWorksheetsProvider),
              alignment: Alignment.topLeft,
              loading: () => const Column(
                children: [
                  WorksheetTileSkeleton(),
                  SizedBox(height: DsSpace.s2),
                  WorksheetTileSkeleton(),
                  SizedBox(height: DsSpace.s2),
                  WorksheetTileSkeleton(),
                ],
              ),
              error: (e, st) => _Card(
                child: _InlineError(
                  error: AppError.from(e, st),
                  onRetry: () => ref.invalidate(recentWorksheetsProvider),
                ),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return _Card(
                    child: EmptyView(
                      icon: DsIcons.create,
                      title: '아직 학습지가 없어요',
                      description: '배우고 싶은 걸 한 줄 적으면 6단계 학습지를 만들어 드려요.',
                      actionLabel: '첫 학습지 만들기',
                      onAction: () => context.push(Routes.create),
                    ),
                  );
                }
                // 학습지는 차례로 놓인다. 한꺼번에 나타나면 '목록이 로드됐다' 지만
                // 차례로 놓이면 '내가 만든 것이 쌓여 있다' 로 읽힌다.
                return Column(
                  children: [
                    for (final (i, w) in items.indexed) ...[
                      DsFadeSlide(
                        delay: dsStaggerDelay(i),
                        child: WorksheetTile(
                          worksheet: w,
                          onTap: () => openWorksheet(context, w),
                          onRetry: () => openWorksheet(context, w),
                        ),
                      ),
                      if (w != items.last) const SizedBox(height: DsSpace.s2),
                    ],
                  ],
                );
              },
            ),
      ],
    );
  }
}

// ── 조각들 ──────────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  const _Card({required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    final body = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(DsSpace.s4),
      decoration: BoxDecoration(
        color: p.surfaceRaised,
        borderRadius: BorderRadius.circular(DsRadius.lg),
        border: Border.all(color: p.borderSubtle),
      ),
      child: child,
    );
    if (onTap == null) return body;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DsRadius.lg),
        child: body,
      ),
    );
  }
}

/// 카드 한 칸 안에서 나는 실패. 화면을 통째로 덮지 않고 그 칸만 오류로 만든다.
class _InlineError extends StatelessWidget {
  const _InlineError({required this.error, required this.onRetry});
  final AppError error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    return Row(
      children: [
        DsIcon(DsIcons.warning, size: 18, color: p.statusWarning),
        const SizedBox(width: DsSpace.s2),
        Expanded(
          child: Text(error.message, style: dsTextStyle(DsType.body, p.textSecondary)),
        ),
        if (error.retryable)
          TextButton(onPressed: onRetry, child: const Text('다시 시도')),
      ],
    );
  }
}

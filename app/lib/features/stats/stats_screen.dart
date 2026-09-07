import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:onpar_design_system/onpar_design_system.dart';

import '../../core/app_error.dart';
import '../../core/routes.dart';
import '../../data/stats_repository.dart';
import '../../ui/states/app_state_views.dart';
import '../../ui/widgets/adaptive.dart';

/// 학습 기록.
///
/// 숫자를 자랑하려고 만드는 화면이 아니다. **다음에 또 올 이유**를 만드는 화면이다.
/// 그래서 세 가지를 지킨다.
///
///   1. 못한 것을 세지 않는다. 틀린 개수가 아니라 떠올린 비율을 보여준다.
///   2. 끊긴 연속을 벌하지 않는다. 어제까지 이어졌으면 아직 살아 있다.
///   3. 숫자 옆에는 언제나 **다음 행동**이 있다. 볼거리로 끝나면 한 번 보고 안 온다.
class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = DsTheme.of(context);
    final stats = ref.watch(learningStatsProvider);

    return Scaffold(
      backgroundColor: p.surfaceBase,
      appBar: AppBar(title: const Text('학습 기록')),
      body: SafeArea(
        child: RefreshIndicator(
          color: p.brandText,
          onRefresh: () async => ref.invalidate(learningStatsProvider),
          child: dsAsync(
            stats,
            loading: () => ListView(
              padding: const EdgeInsets.all(DsSpace.s4),
              children: const [
                SkeletonBox(height: 120),
                SizedBox(height: DsSpace.s3),
                SkeletonBox(height: 96),
              ],
            ),
            error: (e, st) => ErrorView(
              error: AppError.from(e, st),
              onRetry: () => ref.invalidate(learningStatsProvider),
            ),
            data: (s) => ListView(
              padding: const EdgeInsets.fromLTRB(
                  DsSpace.s4, DsSpace.s4, DsSpace.s4, DsSpace.s12),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                ReadableWidth(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DsFadeSlide(child: _StreakCard(stats: s)),
                      const SizedBox(height: DsSpace.s3),
                      DsFadeSlide(delay: dsStaggerDelay(1), child: _AccuracyCard(stats: s)),
                      const SizedBox(height: DsSpace.s3),
                      DsFadeSlide(delay: dsStaggerDelay(2), child: _CountsCard(stats: s)),
                      const SizedBox(height: DsSpace.s6),
                      // 숫자만 보여주고 끝나면 한 번 보고 안 온다. 다음 행동을 같이 둔다.
                      DsFadeSlide(
                        delay: dsStaggerDelay(3),
                        child: s.reviewsDueToday > 0
                            ? FilledButton(
                                onPressed: () => context.push(Routes.reviewSession),
                                child: Text('오늘 복습 ${s.reviewsDueToday}개 하러 가기'),
                              )
                            : OutlinedButton(
                                onPressed: () => context.push(Routes.create),
                                child: const Text('새 학습지 만들기'),
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(DsSpace.s4),
      decoration: BoxDecoration(
        color: p.surfaceRaised,
        borderRadius: BorderRadius.circular(DsRadius.lg),
        border: Border.all(color: p.borderSubtle),
      ),
      child: child,
    );
  }
}

class _StreakCard extends StatelessWidget {
  const _StreakCard({required this.stats});
  final LearningStats stats;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    final days = stats.streakDays;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('연속 학습', style: dsTextStyle(DsType.caption, p.textSecondary)),
          const SizedBox(height: DsSpace.s2),
          Semantics(
            liveRegion: true,
            label: days == 0 ? '연속 학습 기록 없음' : '연속 $days일',
            child: ExcludeSemantics(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  DsCounterText('$days',
                      style: dsTextStyle(
                          DsType.display, days == 0 ? p.textTertiary : p.textPrimary)),
                  const SizedBox(width: DsSpace.s1),
                  Text('일', style: dsTextStyle(DsType.bodyLg, p.textSecondary)),
                ],
              ),
            ),
          ),
          const SizedBox(height: DsSpace.s2),
          Text(
            // 끊긴 것을 지적하지 않는다. 다시 시작하는 사람에게 필요한 것은 꾸중이 아니라
            // "지금 하면 이어진다" 는 사실이다.
            days == 0
                ? '오늘 한 문제만 풀어도 시작이에요.'
                : '오늘 복습하면 ${days + 1}일째가 돼요.',
            style: dsTextStyle(DsType.body, p.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _AccuracyCard extends StatelessWidget {
  const _AccuracyCard({required this.stats});
  final LearningStats stats;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    final rate = stats.accuracy;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('처음에 떠올린 비율', style: dsTextStyle(DsType.caption, p.textSecondary)),
          const SizedBox(height: DsSpace.s2),
          if (rate == null)
            Text('아직 푼 문제가 없어요.', style: dsTextStyle(DsType.bodyLg, p.textPrimary))
          else ...[
            DsCounterText('${(rate * 100).round()}%',
                style: dsTextStyle(DsType.h1, p.textPrimary)),
            const SizedBox(height: DsSpace.s3),
            ClipRRect(
              borderRadius: BorderRadius.circular(DsRadius.full),
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: rate),
                duration: dsDuration(context, DsMotion.slower),
                curve: DsCurve.enter,
                builder: (_, v, __) => LinearProgressIndicator(
                  value: v,
                  minHeight: 8,
                  backgroundColor: p.surfaceSunken,
                  color: p.brandText,
                ),
              ),
            ),
            const SizedBox(height: DsSpace.s2),
            Text(
              // 틀린 개수를 세지 않는다. 틀린 것은 복습으로 돌아오는 것이지 벌점이 아니다.
              '${stats.answered}개 중 ${stats.correct}개를 처음에 떠올렸어요. '
              '못 떠올린 문제는 복습으로 다시 나와요.',
              style: dsTextStyle(DsType.caption, p.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

class _CountsCard extends StatelessWidget {
  const _CountsCard({required this.stats});
  final LearningStats stats;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Row(
        children: [
          _Metric(label: '만든 학습지', value: '${stats.worksheets}'),
          _Metric(label: '끝낸 복습', value: '${stats.reviewsDone}'),
          _Metric(label: '학습한 날', value: '${stats.activeDays}'),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    return Expanded(
      child: Semantics(
        label: '$label $value',
        child: ExcludeSemantics(
          child: Column(
            children: [
              DsCounterText(value, style: dsTextStyle(DsType.h2, p.textPrimary)),
              const SizedBox(height: DsSpace.s1),
              Text(label,
                  textAlign: TextAlign.center,
                  style: dsTextStyle(DsType.caption, p.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}

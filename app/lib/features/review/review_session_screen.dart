import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:onpar_design_system/onpar_design_system.dart';

import '../../core/analytics.dart';
import '../../core/app_error.dart';
import '../../core/bootstrap.dart';
import '../../core/notifications.dart';
import '../../core/routes.dart';
import '../../data/profile_repository.dart';
import '../../data/review_repository.dart';
import '../../domain/models.dart';
import '../../ui/states/app_state_views.dart';
import '../../ui/widgets/feedback.dart';
import '../notifications/notification_prefs.dart';
import '../notifications/notification_sync.dart';
import 'review_providers.dart';

/// 복습 세션. 한 번에 한 문제.
///
/// **정답을 먼저 보여주면 복습이 아니다.** 스스로 떠올리는 순간(인출)이 기억을 붙잡는 것이고,
/// 화면에 답이 먼저 떠 있으면 사용자는 "아 맞아" 하고 넘어간다 — 그건 읽기지 복습이 아니다.
/// 그래서 문제 → 스스로 떠올리기 → 공개 → 자기 평가 순서를 화면 구조로 강제한다.
class ReviewSessionScreen extends ConsumerStatefulWidget {
  const ReviewSessionScreen({super.key});

  @override
  ConsumerState<ReviewSessionScreen> createState() => _ReviewSessionScreenState();
}

class _ReviewSessionScreenState extends ConsumerState<ReviewSessionScreen> {
  /// 이번 세션에서 풀 문제들. **시작할 때 한 번 찍고 끝까지 그대로 쓴다.**
  ///
  /// 서버 큐(dueReviewsProvider)를 그대로 보고 있으면 한 문제를 풀 때마다 그 문제가
  /// 큐에서 빠지고 목록이 한 칸씩 앞으로 당겨진다. 거기에 _index 까지 1 늘리면
  /// 다음 문제를 건너뛴다 — 3문제 중 1번을 풀면 2번이 아니라 3번이 나온다.
  List<ReviewItem>? _queue;

  int _index = 0;
  bool _revealed = false;
  int? _picked;
  int _recalled = 0;
  int _answered = 0;
  bool _submitting = false;
  bool _finished = false;

  bool get _inProgress => !_finished && (_index > 0 || _revealed || _picked != null);

  /// 세션 큐를 처음 한 번만 고정한다. 새 세션은 화면을 다시 열 때 시작된다.
  List<ReviewItem> _pin(List<ReviewItem> fetched) => _queue ??= List.unmodifiable(fetched);

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    final queue = ref.watch(dueReviewsProvider);

    return PopScope(
      canPop: !_inProgress,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await AppFeedback.confirm(
          context,
          title: '복습을 그만할까요?',
          message: '지금까지 답한 것은 저장했어요. 남은 문제는 다음에 이어서 할 수 있어요.',
          confirmLabel: '그만하기',
          cancelLabel: '계속하기',
        );
        if (leave && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: p.surfaceBase,
        appBar: AppBar(title: const Text('오늘의 복습')),
        body: SafeArea(
          child: _finished
              ? _Summary(answered: _answered, recalled: _recalled, onClose: _close)
              : queue.when(
                  loading: () => const LoadingView(label: '복습할 문제를 불러오는 중'),
                  error: (e, st) => ErrorView(
                    error: AppError.from(e, st),
                    onRetry: () => ref.invalidate(dueReviewsProvider),
                  ),
                  data: (fetched) {
                    final items = _pin(fetched);
                    if (items.isEmpty) {
                      return EmptyView(
                        title: '오늘 복습할 게 없어요',
                        description: '망각곡선에 맞춰 다음 문제가 준비되면 알려 드릴게요.',
                        icon: DsIcons.review,
                        actionLabel: '닫기',
                        onAction: _close,
                      );
                    }
                    final index = _index.clamp(0, items.length - 1);
                    return _Card(
                      key: ValueKey(items[index].scheduleId),
                      item: items[index],
                      position: index + 1,
                      total: items.length,
                      revealed: _revealed,
                      picked: _picked,
                      submitting: _submitting,
                      onPick: (i) => setState(() {
                        _picked = i;
                        _revealed = true;
                      }),
                      onReveal: () => setState(() => _revealed = true),
                      onGrade: (grade) => _grade(items[index], grade, items.length),
                      onOpenWorksheet: () => _openWorksheet(items[index]),
                    );
                  },
                ),
        ),
      ),
    );
  }

  void _close() {
    // 세션이 끝났다. 이제서야 큐를 다시 받는다 — 홈·복습 탭의 "오늘 남은 개수" 가
    // 방금 푼 것을 반영해야 한다.
    ref.invalidate(dueReviewsProvider);
    // 복습 **탭**은 pop 해도 위젯이 살아 있다(IndexedStack). 상태를 비우지 않으면
    // 다음에 탭을 눌렀을 때 어제의 요약 화면이 그대로 떠 있다.
    setState(() {
      _queue = null;
      _index = 0;
      _revealed = false;
      _picked = null;
      _recalled = 0;
      _answered = 0;
      _finished = false;
    });
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.home);
    }
  }

  void _openWorksheet(ReviewItem item) {
    // 학습지의 그 문제 자리로 간다 — 그때 쓴 내 필기가 그대로 보이는 게 이 앱의 순간이다.
    context.push('${Routes.worksheet(item.worksheetId)}?quizId=${item.quizItemId}');
  }

  Future<void> _grade(ReviewItem item, int grade, int total) async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      await ref.read(reviewRepositoryProvider).answer(
            scheduleId: item.scheduleId,
            grade: grade,
          );
      // 문제 원문·답안은 싣지 않는다. 채점 등급과 몇 번째인지만 남긴다.
      ref.read(analyticsProvider).track(AnalyticsEvent.reviewAnswer,
          props: {'grade': grade, 'index': _index, 'total': total});
      if (!mounted) return;

      final last = _index + 1 >= total;
      setState(() {
        _answered += 1;
        // "떠올렸다" 는 정말 떠올린 것만 센다. `모르겠음`(grade 0)까지 세면
        // 하나도 못 떠올린 사람이 "5개를 떠올렸어요" 를 보게 되고,
        // 그 숫자는 그날부터 아무 의미가 없다.
        if (grade >= 1) _recalled += 1;
        _revealed = false;
        _picked = null;
        if (last) {
          _finished = true;
        } else {
          _index += 1;
        }
      });

      // 다음 알림은 다시 계산해야 한다. 다만 **이번 세션의 큐는 건드리지 않는다** —
      // 지금 보고 있는 목록이 발밑에서 바뀌면 남은 문제의 순서가 어긋난다.
      // 오늘 남은 문제는 세션을 닫을 때(_close) 다시 받는다.
      ref.invalidate(upcomingReviewsProvider);
      unawaited(_resyncNotifications());
    } on AppError catch (e) {
      if (mounted) AppFeedback.toast(context, e.message, danger: true);
    } catch (e, st) {
      if (mounted) AppFeedback.toast(context, AppError.from(e, st).message, danger: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// 알림 재예약은 화면을 막지 않는다. 실패해도 큐는 서버에서 복원된다.
  Future<void> _resyncNotifications() async {
    final profile = ref.read(profileProvider).valueOrNull;
    final prefs = ref.read(sharedPrefsProvider).valueOrNull;
    if (profile == null || prefs == null) return;
    await syncReviewNotifications(
      service: ref.read(notificationServiceProvider),
      reviews: ref.read(reviewRepositoryProvider),
      prefs: NotificationPrefs(prefs),
      profile: profile,
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    super.key,
    required this.item,
    required this.position,
    required this.total,
    required this.revealed,
    required this.picked,
    required this.submitting,
    required this.onPick,
    required this.onReveal,
    required this.onGrade,
    required this.onOpenWorksheet,
  });

  final ReviewItem item;
  final int position;
  final int total;
  final bool revealed;
  final int? picked;
  final bool submitting;
  final ValueChanged<int> onPick;
  final VoidCallback onReveal;
  final ValueChanged<int> onGrade;
  final VoidCallback onOpenWorksheet;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    final choices = item.choices;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Progress(position: position, total: total),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(DsSpace.s4, DsSpace.s4, DsSpace.s4, DsSpace.s8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${item.worksheetTitle ?? '학습지'} · ${item.repetition + 1}회차',
                  style: dsTextStyle(DsType.caption, p.textSecondary),
                ),
                const SizedBox(height: DsSpace.s3),
                Text(item.question, style: dsTextStyle(DsType.h2, p.textPrimary)),
                const SizedBox(height: DsSpace.s6),
                if (choices != null && choices.isNotEmpty)
                  _Choices(
                    choices: choices,
                    picked: picked,
                    answer: item.answer,
                    revealed: revealed,
                    onPick: revealed ? null : onPick,
                  )
                else if (!revealed)
                  _RecallPrompt(onReveal: onReveal),
                if (revealed) ...[
                  const SizedBox(height: DsSpace.s6),
                  _Answer(item: item),
                  const SizedBox(height: DsSpace.s6),
                  _GradeBar(submitting: submitting, onGrade: onGrade),
                ],
                const SizedBox(height: DsSpace.s6),
                TextButton(
                  onPressed: onOpenWorksheet,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DsIcon(DsIcons.library, size: 18, color: p.brandText),
                      const SizedBox(width: DsSpace.s2),
                      Flexible(
                        child: Text('학습지에서 이 부분 보기',
                            style: dsTextStyle(DsType.body, p.brandText)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.position, required this.total});
  final int position;
  final int total;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(DsSpace.s4, DsSpace.s2, DsSpace.s4, 0),
      child: Semantics(
        liveRegion: true,
        label: '전체 $total개 중 $position번째 문제',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ExcludeSemantics(
              child: Text('$position/$total', style: dsTextStyle(DsType.caption, p.textSecondary)),
            ),
            const SizedBox(height: DsSpace.s1),
            ClipRRect(
              borderRadius: BorderRadius.circular(DsRadius.full),
              child: LinearProgressIndicator(
                value: total == 0 ? 0 : position / total,
                minHeight: 6,
                backgroundColor: p.surfaceSunken,
                color: p.brandText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 서술형: 답을 보기 전에 반드시 한 번 멈춘다.
class _RecallPrompt extends StatelessWidget {
  const _RecallPrompt({required this.onReveal});
  final VoidCallback onReveal;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(DsSpace.s4),
          decoration: BoxDecoration(
            color: p.surfaceSunken,
            borderRadius: BorderRadius.circular(DsRadius.xl),
          ),
          child: Text(
            '머릿속으로 먼저 답해 보세요. 떠올리는 그 순간이 기억을 오래 붙잡아요.',
            style: dsTextStyle(DsType.body, p.textSecondary),
          ),
        ),
        const SizedBox(height: DsSpace.s4),
        FilledButton(onPressed: onReveal, child: const Text('떠올렸어요')),
      ],
    );
  }
}

class _Choices extends StatelessWidget {
  const _Choices({
    required this.choices,
    required this.picked,
    required this.answer,
    required this.revealed,
    required this.onPick,
  });

  final List<String> choices;
  final int? picked;
  final String answer;
  final bool revealed;
  final ValueChanged<int>? onPick;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < choices.length; i++) ...[
          _ChoiceTile(
            label: choices[i],
            selected: picked == i,
            // 색만으로 정답을 말하지 않는다 — 아이콘과 글자를 같이 쓴다.
            correct: revealed && choices[i].trim() == answer.trim(),
            onTap: onPick == null ? null : () => onPick!(i),
          ),
          if (i != choices.length - 1) const SizedBox(height: DsSpace.s2),
        ],
        if (!revealed) ...[
          const SizedBox(height: DsSpace.s4),
          Text('고르면 정답과 해설을 보여 드릴게요.',
              style: dsTextStyle(DsType.caption, p.textTertiary)),
        ],
      ],
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.label,
    required this.selected,
    required this.correct,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool correct;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    final border = correct
        ? p.statusSuccess
        : selected
            ? p.brandText
            : p.borderSubtle;
    return Semantics(
      button: onTap != null,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DsRadius.xl),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: DsSpace.s4, vertical: DsSpace.s3),
          decoration: BoxDecoration(
            color: correct ? p.statusBgSuccess : p.surfaceRaised,
            border: Border.all(color: border, width: correct || selected ? 2 : 1),
            borderRadius: BorderRadius.circular(DsRadius.xl),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(label, style: dsTextStyle(DsType.bodyLg, p.textPrimary))),
              if (correct) ...[
                const SizedBox(width: DsSpace.s2),
                DsIcon(DsIcons.success, size: 20, color: p.statusSuccess, semanticLabel: '정답'),
              ] else if (selected) ...[
                const SizedBox(width: DsSpace.s2),
                Text('내 답', style: dsTextStyle(DsType.caption, p.textSecondary)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Answer extends StatelessWidget {
  const _Answer({required this.item});
  final ReviewItem item;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(DsSpace.s4),
        decoration: BoxDecoration(
          color: p.surfaceRaised,
          border: Border.all(color: p.borderSubtle),
          borderRadius: BorderRadius.circular(DsRadius.xl),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('정답', style: dsTextStyle(DsType.caption, p.textSecondary)),
            const SizedBox(height: DsSpace.s1),
            Text(item.answer, style: dsTextStyle(DsType.bodyLg, p.textPrimary)),
            if (item.explanation.trim().isNotEmpty) ...[
              const SizedBox(height: DsSpace.s4),
              Text('해설', style: dsTextStyle(DsType.caption, p.textSecondary)),
              const SizedBox(height: DsSpace.s1),
              Text(item.explanation, style: dsTextStyle(DsType.body, p.textPrimary)),
            ],
          ],
        ),
      ),
    );
  }
}

class _GradeBar extends StatelessWidget {
  const _GradeBar({required this.submitting, required this.onGrade});

  final bool submitting;
  final ValueChanged<int> onGrade;

  /// 서버 grade 와 같은 순서다(0=모르겠음 … 3=쉬움). 라벨만 바꾸면 안 된다.
  static const _labels = ['모르겠음', '어려움', '보통', '쉬움'];

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('얼마나 기억났나요?', style: dsTextStyle(DsType.h3, p.textPrimary)),
        const SizedBox(height: DsSpace.s3),
        Wrap(
          spacing: DsSpace.s2,
          runSpacing: DsSpace.s2,
          children: [
            for (var grade = 0; grade < _labels.length; grade++)
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(96, 48),
                  padding: const EdgeInsets.symmetric(horizontal: DsSpace.s4),
                ),
                onPressed: submitting ? null : () => onGrade(grade),
                child: Text(_labels[grade]),
              ),
          ],
        ),
        if (submitting) ...[
          const SizedBox(height: DsSpace.s3),
          Semantics(
            liveRegion: true,
            child: Text('저장하는 중이에요', style: dsTextStyle(DsType.caption, p.textSecondary)),
          ),
        ],
      ],
    );
  }
}

/// 끝난 뒤에는 점수를 말하지 않는다. 복습은 맞히기 시험이 아니라 떠올리기 연습이다.
class _Summary extends StatelessWidget {
  const _Summary({required this.answered, required this.recalled, required this.onClose});

  final int answered;
  final int recalled;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(DsSpace.s8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DsIcon(DsIcons.success, size: 40, color: p.statusSuccess),
            const SizedBox(height: DsSpace.s4),
            Semantics(
              liveRegion: true,
              child: Text(
                '오늘 $answered개를 복습했어요',
                textAlign: TextAlign.center,
                style: dsTextStyle(DsType.h2, p.textPrimary),
              ),
            ),
            const SizedBox(height: DsSpace.s2),
            Text(
              recalled == answered
                  ? '잊을 때쯤 다시 꺼내면 기억이 오래가요. 다음 복습은 알림으로 알려 드릴게요.'
                  : '그중 $recalled개를 떠올렸어요. 못 떠올린 문제는 곧 다시 보여 드릴게요.',
              textAlign: TextAlign.center,
              style: dsTextStyle(DsType.body, p.textSecondary),
            ),
            const SizedBox(height: DsSpace.s8),
            FilledButton(onPressed: onClose, child: const Text('닫기')),
          ],
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:onpar_design_system/onpar_design_system.dart';

import '../../core/analytics.dart';
import '../../core/app_error.dart';
import '../../core/routes.dart';
import '../../data/profile_repository.dart';
import '../../data/worksheet_repository.dart';
import '../../domain/models.dart';
import '../../ui/states/app_state_views.dart';

/// 생성 중인 학습지 하나를 지켜본다. 리포지터리가 Realtime 대신 폴링으로 받쳐 주고,
/// 5분이 넘으면 timeout 을 던진다.
final worksheetProgressProvider =
    StreamProvider.autoDispose.family<WorksheetSummary, String>(
  (ref, id) => ref.watch(worksheetRepositoryProvider).watch(id),
);

/// 40~120초 동안 사용자가 보는 화면.
///
/// 스피너 하나만 두면 "멈춘 건가" 를 40초 동안 의심하게 된다. 그래서 지금 무엇을
/// 하고 있는지 단계로 말해 주고, 나가도 계속 만들어진다는 것을 분명히 적는다.
class CreateProgressScreen extends ConsumerStatefulWidget {
  const CreateProgressScreen({super.key, required this.worksheetId});

  final String worksheetId;

  @override
  ConsumerState<CreateProgressScreen> createState() => _CreateProgressScreenState();
}

class _CreateProgressScreenState extends ConsumerState<CreateProgressScreen> {
  /// 단계는 서버가 알려주지 않는다. 걸리는 시간이 대체로 일정해서 시간으로 나눈다.
  /// 지어낸 진행률(%)은 쓰지 않는다 — 90%에서 멈춰 있는 막대가 가장 나쁘다.
  static const _stages = <(Duration, String, String)>[
    (Duration.zero, '주제를 정리하고 있어요', '무엇부터 설명할지 순서를 잡는 중이에요.'),
    (Duration(seconds: 18), '학습지를 쓰고 있어요', '예시와 연습 문제를 함께 만들고 있어요.'),
    (Duration(seconds: 70), '품질을 검사하고 있어요', '덜 만들어진 학습지를 드리지 않으려고 한 번 더 봐요.'),
  ];

  Timer? _tick;
  Duration _elapsed = Duration.zero;
  bool _left = false;

  /// 실패 이벤트는 한 번만. build 는 여러 번 불린다.
  bool _failReported = false;

  @override
  void initState() {
    super.initState();
    // 이 화면에 들어온 것 자체는 이벤트로 남기지 않는다 — 바로 앞의 제출에서
    // worksheetCreateStart 를 이미 한 번 남겼고, 여기서 또 남기면 같은 주문이 두 번 세어진다.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed += const Duration(seconds: 1));
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  /// 생성 실패를 한 번만 기록하고 실패 화면을 돌려준다.
  /// `error_code` 는 서버가 정한 닫힌 코드(llm_refused 등)라 원문이 아니다.
  Widget _reportFailure(WorksheetSummary w) {
    if (!_failReported) {
      _failReported = true;
      ref.read(analyticsProvider).track(AnalyticsEvent.worksheetCreateFailed,
          props: {'stage': 'generate', 'error_code': w.errorCode ?? 'unknown'});
    }
    return _failed(context, w);
  }

  (String, String) get _stage {
    var current = _stages.first;
    for (final s in _stages) {
      if (_elapsed >= s.$1) current = s;
    }
    return (current.$2, current.$3);
  }

  void _openWorksheet() {
    if (_left || !mounted) return;
    _left = true;
    // 걸린 시간은 이 화면을 고칠 때 쓰는 유일한 숫자다. 주제·제목은 싣지 않는다.
    ref.read(analyticsProvider).track(AnalyticsEvent.worksheetCreateComplete,
        props: {'elapsed_sec': _elapsed.inSeconds});
    // 뒤로 가면 진행 화면이 아니라 그 앞으로 가야 한다.
    context.pushReplacement(Routes.worksheet(widget.worksheetId));
  }

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    final progress = ref.watch(worksheetProgressProvider(widget.worksheetId));

    // 완성되면 곧바로 뷰어로. build 안에서 화면을 바꾸면 안 되므로 프레임 뒤로 미룬다.
    ref.listen(worksheetProgressProvider(widget.worksheetId), (_, next) {
      final w = next.valueOrNull;
      if (w == null || w.status != WorksheetStatus.ready) return;
      WidgetsBinding.instance.addPostFrameCallback((_) => _openWorksheet());
    });

    return Scaffold(
      backgroundColor: p.surfaceBase,
      appBar: AppBar(
        title: const Text('학습지 만드는 중'),
        leading: IconButton(
          icon: DsIcon(DsIcons.back, size: 22, semanticLabel: '뒤로'),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        child: progress.when(
          // 첫 상태를 받기 전에도 사용자는 이미 기다리고 있다. 같은 진행 화면을 보여준다.
          loading: () => _working(context, null),
          error: (e, st) {
            final err = AppError.from(e, st);
            if (err.kind == AppErrorKind.timeout) return _timedOut(context, err);
            return ErrorView(
              error: err,
              onRetry: () => ref.invalidate(worksheetProgressProvider(widget.worksheetId)),
              secondaryLabel: '서재에서 보기',
              onSecondary: () => context.go(Routes.library),
            );
          },
          data: (w) => switch (w.status) {
            WorksheetStatus.failed => _reportFailure(w),
            // ready 는 위 listen 이 화면을 바꾼다. 그 한 프레임 동안 보일 그림.
            WorksheetStatus.ready => const LoadingView(label: '학습지를 여는 중'),
            _ => _working(context, w),
          },
        ),
      ),
    );
  }

  // ── 만드는 중 ────────────────────────────────────────────────────────

  Widget _working(BuildContext context, WorksheetSummary? w) {
    final p = DsTheme.of(context);
    final (title, detail) = _stage;

    return ListView(
      padding: const EdgeInsets.fromLTRB(DsSpace.s6, DsSpace.s12, DsSpace.s6, DsSpace.s8),
      children: [
        Center(child: CircularProgressIndicator(color: p.brandText, strokeWidth: 3)),
        const SizedBox(height: DsSpace.s8),

        // 단계가 바뀌면 스크린리더도 알아야 한다.
        Semantics(
          liveRegion: true,
          child: Column(
            children: [
              AnimatedSwitcher(
                duration: DsMotion.durationSlow,
                child: Text(
                  title,
                  key: ValueKey(title),
                  textAlign: TextAlign.center,
                  style: dsTextStyle(DsType.h2, p.textPrimary)
                      .copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: DsSpace.s3),
              Text(detail,
                  textAlign: TextAlign.center,
                  style: dsTextStyle(DsType.body, p.textSecondary)),
            ],
          ),
        ),

        if (w != null) ...[
          const SizedBox(height: DsSpace.s6),
          Text(w.displayTitle,
              textAlign: TextAlign.center,
              style: dsTextStyle(DsType.body, p.textTertiary)),
        ],

        const SizedBox(height: DsSpace.s8),
        _StageDots(elapsed: _elapsed, stages: _stages),

        const SizedBox(height: DsSpace.s8),
        Container(
          padding: const EdgeInsets.all(DsSpace.s4),
          decoration: BoxDecoration(
            color: p.statusBgInfo,
            borderRadius: BorderRadius.circular(DsRadius.md),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DsIcon(DsIcons.info, size: 18, color: p.statusInfo),
              const SizedBox(width: DsSpace.s2),
              Expanded(
                child: Text(
                  '보통 40~120초쯤 걸려요. 이 화면을 나가도 계속 만들어지고, '
                  '다 되면 서재에서 열 수 있어요.',
                  style: dsTextStyle(DsType.body, p.textPrimary),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: DsSpace.s4),
        OutlinedButton(
          onPressed: () => context.go(Routes.library),
          child: const Text('서재로 가기'),
        ),
      ],
    );
  }

  // ── 실패 ────────────────────────────────────────────────────────────

  Widget _failed(BuildContext context, WorksheetSummary w) {
    final p = DsTheme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(DsSpace.s6, DsSpace.s12, DsSpace.s6, DsSpace.s8),
      children: [
        Center(child: DsIcon(DsIcons.warning, size: 36, color: p.statusWarning)),
        const SizedBox(height: DsSpace.s4),
        Semantics(
          liveRegion: true,
          child: Text('학습지를 만들지 못했어요',
              textAlign: TextAlign.center,
              style: dsTextStyle(DsType.h2, p.textPrimary).copyWith(fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: DsSpace.s3),
        // failureMessage 안에 이미 "장수는 돌려드렸어요" 가 들어 있다.
        Text(w.failureMessage,
            textAlign: TextAlign.center, style: dsTextStyle(DsType.body, p.textSecondary)),
        const SizedBox(height: DsSpace.s4),
        Container(
          padding: const EdgeInsets.all(DsSpace.s3),
          decoration: BoxDecoration(
            color: p.statusBgSuccess,
            borderRadius: BorderRadius.circular(DsRadius.md),
          ),
          child: Row(
            children: [
              DsIcon(DsIcons.success, size: 18, color: p.statusSuccess),
              const SizedBox(width: DsSpace.s2),
              Expanded(
                child: Text('쿼터는 돌려드렸어요.',
                    style: dsTextStyle(DsType.body, p.textPrimary)),
              ),
            ],
          ),
        ),
        const SizedBox(height: DsSpace.s6),
        FilledButton(
          onPressed: () {
            // 환불된 쿼터가 홈에 바로 보이게 한다.
            ref.invalidate(profileProvider);
            // 다시 시도는 만들기 화면으로 돌아가는 것뿐이다. 실제 재시도는 거기서 제출할 때
            // worksheetCreateStart 로 남는다 — 여기서 또 남기면 시도 수가 부풀려진다.
            Navigator.of(context).pop();
          },
          child: const Text('다시 시도'),
        ),
        const SizedBox(height: DsSpace.s2),
        TextButton(
          onPressed: () => context.go(Routes.library),
          child: const Text('서재로 가기'),
        ),
      ],
    );
  }

  // ── 너무 오래 걸린다 ──────────────────────────────────────────────────

  Widget _timedOut(BuildContext context, AppError error) {
    final p = DsTheme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(DsSpace.s6, DsSpace.s12, DsSpace.s6, DsSpace.s8),
      children: [
        Center(child: DsIcon(DsIcons.info, size: 36, color: p.textTertiary)),
        const SizedBox(height: DsSpace.s4),
        Semantics(
          liveRegion: true,
          child: Text(error.message,
              textAlign: TextAlign.center, style: dsTextStyle(DsType.bodyLg, p.textPrimary)),
        ),
        const SizedBox(height: DsSpace.s3),
        Text('취소된 건 아니에요. 다 만들어지면 서재에 나타나요.',
            textAlign: TextAlign.center, style: dsTextStyle(DsType.body, p.textSecondary)),
        const SizedBox(height: DsSpace.s6),
        FilledButton(
          onPressed: () => context.go(Routes.library),
          child: const Text('서재에서 확인하기'),
        ),
        const SizedBox(height: DsSpace.s2),
        TextButton(
          onPressed: () => ref.invalidate(worksheetProgressProvider(widget.worksheetId)),
          child: const Text('여기서 더 기다리기'),
        ),
      ],
    );
  }
}

/// 지금 몇 번째 단계인지. 색만으로 구분하지 않게 지나온 단계엔 체크가 붙는다.
class _StageDots extends StatelessWidget {
  const _StageDots({required this.elapsed, required this.stages});

  final Duration elapsed;
  final List<(Duration, String, String)> stages;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    var currentIndex = 0;
    for (var i = 0; i < stages.length; i++) {
      if (elapsed >= stages[i].$1) currentIndex = i;
    }

    return Column(
      children: [
        for (var i = 0; i < stages.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: DsSpace.s1),
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  height: 22,
                  child: i < currentIndex
                      ? DsIcon(DsIcons.success, size: 18, color: p.statusSuccess)
                      : i == currentIndex
                          ? CircularProgressIndicator(strokeWidth: 2.4, color: p.brandText)
                          : Center(
                              child: Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  color: p.borderStrong,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                ),
                const SizedBox(width: DsSpace.s3),
                Expanded(
                  child: Text(
                    stages[i].$2,
                    style: dsTextStyle(
                      DsType.body,
                      i <= currentIndex ? p.textPrimary : p.textTertiary,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

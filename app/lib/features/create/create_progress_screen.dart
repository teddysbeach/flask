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
import '../library/library_controller.dart';

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
  /// 서버가 말한 단계를 사람 말로. **여기 있는 것만 화면에 뜬다** —
  /// 지어낸 것은 하나도 없고, 서버가 아무 말도 안 했으면 아무 말도 하지 않는다.
  static const _labels = <GenerationStage, (String, String)>{
    GenerationStage.plan: ('주제를 정리하고 있어요', '무엇부터 설명할지 순서를 잡는 중이에요.'),
    GenerationStage.draft: ('학습지를 쓰고 있어요', '예시와 연습 문제를 함께 만들고 있어요.'),
    GenerationStage.critic: ('품질을 검사하고 있어요', '덜 만들어진 학습지를 드리지 않으려고 한 번 더 봐요.'),
    GenerationStage.revise: ('다시 쓰고 있어요', '검사에서 걸린 부분을 고쳐서 다시 쓰는 중이에요.'),
    GenerationStage.render: ('학습지를 그리고 있어요', '필기할 수 있는 한 장으로 옮기는 중이에요.'),
    GenerationStage.save: ('거의 다 됐어요', '복습 일정까지 잡고 마무리하는 중이에요.'),
  };

  /// 화면에 줄지어 보여줄 단계. revise 는 뺀다 — 몇 번 돌지 정해져 있지 않아서
  /// 목록에 넣으면 진행이 뒤로 가는 것처럼 보인다(대신 지금 단계로는 표시된다).
  static const _track = <GenerationStage>[
    GenerationStage.plan,
    GenerationStage.draft,
    GenerationStage.critic,
    GenerationStage.render,
  ];

  /// 보통 걸리는 시간. 넘겼다고 실패는 아니지만, 넘겼는데도 아무 말 안 하면 그건 숨기는 것이다.
  static const _normal = Duration(minutes: 3);

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

  /// 지금 무엇을 하고 있는가. **모르면 모른다고 말한다.**
  ///
  /// 예전에는 경과 시간으로 단계를 지어냈다. 그래서 서버가 죽은 뒤에도 화면은
  /// "품질을 검사하고 있어요" 라고 13분 동안 말했다. 사용자가 잃은 것은 시간이 아니라
  /// 다음에 이 앱이 하는 말을 믿을 이유였다.
  (String, String) _stageText(WorksheetSummary? w) {
    final known = w?.stage;
    if (known != null) return _labels[known]!;
    // 서버가 아직 첫 단계를 적기 전(보통 몇 초)에는 사실만 말한다.
    return ('학습지를 만들고 있어요', '주문이 서버에 들어갔어요. 곧 어디까지 왔는지 알려 드릴게요.');
  }

  static String _elapsedText(Duration d) {
    final m = d.inMinutes;
    final sec = d.inSeconds % 60;
    return m > 0 ? '$m분 $sec초째' : '$sec초째';
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
      if (w == null || !w.isTerminal) return;
      // 홈 목록의 "만드는 중" 을 완성(또는 실패)으로 바꾼다. 안 부르면 사용자는
      // 다 만들어진 학습지를 보고 나온 뒤에도 홈에서 계속 만드는 중을 본다.
      unawaited(ref.read(libraryControllerProvider.notifier).refresh());
      if (w.status != WorksheetStatus.ready) return;
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
        child: dsAsync(progress,
          // 첫 상태를 받기 전에도 사용자는 이미 기다리고 있다. 같은 진행 화면을 보여준다.
          loading: () => _working(context, null),
          error: (e, st) {
            final err = AppError.from(e, st);
            if (err.kind == AppErrorKind.timeout) return _timedOut(context, err);
            return ErrorView(
              error: err,
              onRetry: () => ref.invalidate(worksheetProgressProvider(widget.worksheetId)),
              secondaryLabel: '홈에서 보기',
              onSecondary: () => context.go(Routes.home),
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
    final (title, detail) = _stageText(w);
    // 시간은 화면이 센 초가 아니라 **서버가 적은 시각**으로 잰다. 앱을 껐다 켜도,
    // 이 화면을 나갔다 들어와도 같은 숫자가 나와야 믿을 수 있다.
    final age = w?.age(DateTime.now()) ?? _elapsed;
    final slow = age > _normal;

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
              DsSwitcher(
                duration: DsMotion.slow,
                alignment: Alignment.center,
                child: Text(
                  title,
                  key: ValueKey(title),
                  textAlign: TextAlign.center,
                  style: dsTextStyle(DsType.h2, p.textPrimary)
                      .copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: DsSpace.s3),
              // 설명도 같이 바뀐다. 제목만 넘어가고 설명이 그대로면 둘이 어긋나 보인다.
              DsSwitcher(
                duration: DsMotion.slow,
                alignment: Alignment.center,
                child: Text(detail,
                    key: ValueKey(detail),
                    textAlign: TextAlign.center,
                    style: dsTextStyle(DsType.body, p.textSecondary)),
              ),
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
        _StageDots(current: w?.stage, track: _track),

        const SizedBox(height: DsSpace.s6),
        // 경과 시간은 늘 보인다. 감춰 두면 "얼마나 기다린 거지" 를 사용자가 세게 된다.
        Text(_elapsedText(age),
            textAlign: TextAlign.center,
            style: dsTextStyle(DsType.caption, slow ? p.statusWarning : p.textTertiary)),

        const SizedBox(height: DsSpace.s6),
        Container(
          padding: const EdgeInsets.all(DsSpace.s4),
          decoration: BoxDecoration(
            color: slow ? p.statusBgWarning : p.statusBgInfo,
            borderRadius: BorderRadius.circular(DsRadius.md),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DsIcon(slow ? DsIcons.warning : DsIcons.info,
                  size: 18, color: slow ? p.statusWarning : p.statusInfo),
              const SizedBox(width: DsSpace.s2),
              Expanded(
                child: Text(
                  slow
                      // 늦어지는 것을 늦어진다고 말한다. 그리고 **끝이 있다는 것**을 함께 말한다 —
                      // 언제 끝나는지 모르는 기다림이 사람을 앱에서 내보낸다.
                      ? '보통보다 오래 걸리고 있어요. 10분이 넘으면 자동으로 멈추고 '
                        '사용한 장수를 돌려드려요. 기다리지 않고 나가셔도 돼요.'
                      : '보통 40~120초쯤 걸려요. 이 화면을 나가도 계속 만들어지고, '
                        '다 되면 홈에서 열 수 있어요.',
                  style: dsTextStyle(DsType.body, p.textPrimary),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: DsSpace.s4),
        OutlinedButton(
          onPressed: () => context.go(Routes.home),
          child: const Text('홈으로 가기'),
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
          onPressed: () => context.go(Routes.home),
          child: const Text('홈으로 가기'),
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
        Text('취소된 건 아니에요. 다 만들어지면 홈에 나타나요.',
            textAlign: TextAlign.center, style: dsTextStyle(DsType.body, p.textSecondary)),
        const SizedBox(height: DsSpace.s6),
        FilledButton(
          onPressed: () => context.go(Routes.home),
          child: const Text('홈에서 확인하기'),
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

/// 지금 어느 단계인지. 색만으로 구분하지 않게 지나온 단계엔 체크가 붙는다.
///
/// 지나온 단계를 **서버가 말한 현재 단계**로 정한다. 예전에는 경과 시간으로 정해서,
/// 서버가 죽어도 체크가 하나씩 늘어났다 — 아무 일도 안 일어나는 동안 진행되는 척하는
/// 표시가 가장 나쁘다.
class _StageDots extends StatelessWidget {
  const _StageDots({required this.current, required this.track});

  final GenerationStage? current;
  final List<GenerationStage> track;

  static const _names = <GenerationStage, String>{
    GenerationStage.plan: '주제 정리',
    GenerationStage.draft: '학습지 쓰기',
    GenerationStage.critic: '품질 검사',
    GenerationStage.render: '한 장으로 그리기',
  };

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    // 다시 쓰는 중이면 검사 단계에 머문 것으로 본다 — 되돌아간 것이 아니라 맴도는 것이다.
    final at = current == GenerationStage.revise ? GenerationStage.critic : current;
    final idx = at == null ? -1 : track.indexOf(at);
    // save 는 목록에 없다. 거기까지 갔으면 전부 끝난 것이다.
    final currentIndex = at == GenerationStage.save ? track.length : idx;

    return Column(
      children: [
        for (var i = 0; i < track.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: DsSpace.s1),
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  height: 22,
                  // 한 단계가 끝나면 스피너가 체크로 **넘어간다.** 툭 바뀌면 진행이 아니라
                  // 화면 새로고침으로 보이고, 기다리는 사람에게 그 차이는 크다.
                  child: DsSwitcher(
                    duration: DsMotion.base,
                    alignment: Alignment.center,
                    travel: 6,
                    child: currentIndex > i
                        ? DsIcon(DsIcons.success,
                            key: const ValueKey('done'), size: 18, color: p.statusSuccess)
                        : currentIndex == i
                            ? CircularProgressIndicator(
                                key: const ValueKey('busy'),
                                strokeWidth: 2.4,
                                color: p.brandText)
                            : Center(
                                key: const ValueKey('todo'),
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
                ),
                const SizedBox(width: DsSpace.s3),
                Expanded(
                  child: AnimatedDefaultTextStyle(
                    duration: dsDuration(context, DsMotion.slow),
                    curve: DsCurve.standard,
                    style: dsTextStyle(
                      DsType.body,
                      currentIndex >= i ? p.textPrimary : p.textTertiary,
                    ),
                    child: Text(_names[track[i]]!),
                  ),
                ),
                // 다시 쓰는 중이라는 사실을 숨기지 않는다. 같은 자리에서 오래 도는 이유다.
                if (current == GenerationStage.revise && track[i] == GenerationStage.critic)
                  Text('다시 쓰는 중',
                      style: dsTextStyle(DsType.caption, p.statusWarning)),
              ],
            ),
          ),
      ],
    );
  }
}

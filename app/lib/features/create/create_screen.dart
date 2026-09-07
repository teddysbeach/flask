import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:onpar_design_system/onpar_design_system.dart';

import '../../core/app_error.dart';
import '../../core/logger.dart';
import '../../core/routes.dart';
import '../../data/profile_repository.dart';
import '../../data/worksheet_repository.dart';
import '../../ui/states/app_state_views.dart';
import '../../ui/widgets/feedback.dart';
import 'create_progress_screen.dart';

/// 서버가 받는 난이도. 화면 문구와 서버 값을 한곳에서 묶어 둔다 —
/// 두 벌로 두면 "심화" 를 골랐는데 입문이 만들어지는 사고가 조용히 난다.
enum CreateLevel {
  beginner('beginner', '입문', '처음 듣는 개념이에요'),
  intermediate('intermediate', '중급', '들어는 봤어요'),
  advanced('advanced', '심화', '설명까지 할 수 있어요');

  const CreateLevel(this.value, this.label, this.hint);
  final String value;
  final String label;
  final String hint;
}

const _topicMaxLength = 120;

const _examples = <String>[
  '미분이 왜 필요한지',
  '전기와 자기의 관계',
  '정규분포와 표준편차',
  '광합성의 명반응·암반응',
  '수요와 공급이 만나는 지점',
];

/// 학습지 한 장을 주문하는 화면. 이 버튼이 쿼터를 깎는다.
class CreateScreen extends ConsumerStatefulWidget {
  const CreateScreen({super.key, this.initialTopic});

  /// 실패한 학습지를 다시 만들 때 주제를 채워 준다.
  final String? initialTopic;

  @override
  ConsumerState<CreateScreen> createState() => _CreateScreenState();
}

class _CreateScreenState extends ConsumerState<CreateScreen> {
  late final TextEditingController _topic = TextEditingController(text: widget.initialTopic ?? '');
  final _focus = FocusNode();

  CreateLevel _level = CreateLevel.beginner;
  AppError? _error;

  @override
  void initState() {
    super.initState();
    _topic.addListener(_onTopicChanged);
    // TODO(analytics): worksheetCreateStart
  }

  @override
  void dispose() {
    _topic
      ..removeListener(_onTopicChanged)
      ..dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onTopicChanged() {
    if (_error != null) setState(() => _error = null);
    setState(() {});
  }

  String get _trimmed => _topic.text.trim();
  bool get _valid => _trimmed.isNotEmpty && _trimmed.length <= _topicMaxLength;
  bool get _dirty => _trimmed.isNotEmpty && _trimmed != (widget.initialTopic ?? '').trim();

  Future<void> _submit() async {
    if (!_valid) return;
    FocusScope.of(context).unfocus();
    setState(() => _error = null);

    try {
      // TODO(analytics): worksheetCreateSubmit — level, topicLength
      final id = await ref
          .read(worksheetRepositoryProvider)
          .create(topic: _trimmed, level: _level.value);
      if (!mounted) return;

      // 쿼터가 줄었다. 홈이 옛 숫자를 들고 있으면 사용자는 한 장을 더 쓸 수 있다고 믿는다.
      ref.invalidate(profileProvider);

      // 되돌아올 곳은 진행 화면이 아니라 여기 이전이다 — 만들기 화면은 역할을 마쳤다.
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => CreateProgressScreen(worksheetId: id)),
      );
    } catch (e, st) {
      final err = AppError.from(e, st);
      AppLogger.error('학습지 생성 실패', error: err, stack: st);
      if (!mounted) return;

      // 쿼터 소진은 실패가 아니다. 오류 화면 대신 살 수 있는 곳으로 보낸다.
      if (err.kind == AppErrorKind.quotaExhausted) {
        // TODO(analytics): paywallOpen — 진입 지점(create_quota)
        unawaited(context.push(Routes.paywall));
        return;
      }
      setState(() => _error = err);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    final profile = ref.watch(profileProvider);

    return PopScope(
      // 적다 만 주제를 실수로 날리지 않게 확인을 받는다.
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || !_dirty) return;
        final leave = await AppFeedback.confirm(
          context,
          title: '그만 만들까요?',
          message: '적으신 주제는 저장되지 않아요.',
          confirmLabel: '나가기',
          cancelLabel: '계속 쓰기',
        );
        if (leave && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: p.surfaceBase,
        appBar: AppBar(title: const Text('학습지 만들기')),
        // 키보드가 올라와도 입력칸이 가려지지 않게 본문 전체가 스크롤된다.
        body: SafeArea(
          child: profile.when(
            loading: () => const LoadingView(label: '준비하고 있어요'),
            error: (e, st) => ErrorView(
              error: AppError.from(e, st),
              onRetry: () => ref.invalidate(profileProvider),
            ),
            data: (me) => me.canCreate ? _form(context, me.quotaRemaining) : _outOfQuota(context),
          ),
        ),
      ),
    );
  }

  // ── 남은 장수가 0 ────────────────────────────────────────────────────

  Widget _outOfQuota(BuildContext context) {
    final p = DsTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DsSpace.s8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DsIcon(DsIcons.info, size: 36, color: p.textTertiary),
            const SizedBox(height: DsSpace.s4),
            Text(
              '남은 학습지를 다 쓰셨어요',
              textAlign: TextAlign.center,
              style: dsTextStyle(DsType.h3, p.textPrimary),
            ),
            const SizedBox(height: DsSpace.s2),
            Text(
              '충전하면 이어서 만들 수 있어요.',
              textAlign: TextAlign.center,
              style: dsTextStyle(DsType.body, p.textSecondary),
            ),
            const SizedBox(height: DsSpace.s6),
            FilledButton(
              onPressed: () {
                // TODO(analytics): paywallOpen — 진입 지점(create_empty)
                context.push(Routes.paywall);
              },
              child: const Text('충전하기'),
            ),
          ],
        ),
      ),
    );
  }

  // ── 입력 ────────────────────────────────────────────────────────────

  Widget _form(BuildContext context, int quotaRemaining) {
    final p = DsTheme.of(context);
    final left = _topicMaxLength - _topic.text.runes.length;
    final tooLong = left < 0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(DsSpace.s4, DsSpace.s4, DsSpace.s4, DsSpace.s12),
      children: [
        Text(
          '무엇을 배우고 싶으세요?',
          style: dsTextStyle(DsType.h2, p.textPrimary).copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: DsSpace.s2),
        Text('한 줄이면 충분해요. 개념 하나가 가장 잘 나와요.', style: dsTextStyle(DsType.body, p.textSecondary)),
        const SizedBox(height: DsSpace.s4),

        TextField(
          controller: _topic,
          focusNode: _focus,
          autofocus: widget.initialTopic == null,
          maxLines: 3,
          minLines: 2,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => unawaited(_submit()),
          // maxLength 로 잘라 버리면 붙여넣기한 글이 말없이 사라진다. 세어서 알려만 준다.
          inputFormatters: [LengthLimitingTextInputFormatter(_topicMaxLength * 2)],
          decoration: InputDecoration(
            hintText: '예) 미분이 왜 필요한지',
            errorText: tooLong ? '$_topicMaxLength자 안에서 적어 주세요.' : null,
          ),
          style: dsTextStyle(DsType.bodyLg, p.textPrimary),
        ),
        const SizedBox(height: DsSpace.s2),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            tooLong ? '${-left}자 넘었어요' : '$left자 남음',
            style: dsTextStyle(DsType.caption, tooLong ? p.statusDanger : p.textTertiary),
          ),
        ),

        const SizedBox(height: DsSpace.s4),
        Text('이런 것도 좋아요', style: dsTextStyle(DsType.caption, p.textSecondary)),
        const SizedBox(height: DsSpace.s2),
        Wrap(
          spacing: DsSpace.s2,
          runSpacing: DsSpace.s2,
          children: [
            for (final e in _examples)
              ActionChip(
                label: Text(e, style: dsTextStyle(DsType.body, p.textPrimary)),
                backgroundColor: p.surfaceRaised,
                side: BorderSide(color: p.borderSubtle),
                onPressed: () {
                  _topic.text = e;
                  _topic.selection = TextSelection.collapsed(offset: e.length);
                  _focus.requestFocus();
                },
              ),
          ],
        ),

        const SizedBox(height: DsSpace.s6),
        Text(
          '어느 정도로 만들까요?',
          style: dsTextStyle(DsType.h3, p.textPrimary).copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: DsSpace.s3),
        for (final level in CreateLevel.values) ...[
          _LevelOption(
            level: level,
            selected: level == _level,
            onTap: () => setState(() => _level = level),
          ),
          const SizedBox(height: DsSpace.s2),
        ],

        if (_error != null) ...[const SizedBox(height: DsSpace.s4), _ErrorNotice(error: _error!)],

        const SizedBox(height: DsSpace.s6),
        Semantics(
          liveRegion: true,
          child: Text(
            '만들면 $quotaRemaining장 중 1장을 써요. 40~120초쯤 걸려요.',
            textAlign: TextAlign.center,
            style: dsTextStyle(DsType.caption, p.textSecondary),
          ),
        ),
        const SizedBox(height: DsSpace.s3),
        // 연타 방지. 쿼터를 깎는 버튼이라 위젯에서도 한 겹 막는다(RequestGuard 와 두 겹).
        OnceButton(enabled: _valid, onPressed: _submit, child: const Text('학습지 만들기')),
      ],
    );
  }
}

/// 난이도 한 칸. 선택은 색이 아니라 테두리·체크 아이콘으로도 보인다.
class _LevelOption extends StatelessWidget {
  const _LevelOption({required this.level, required this.selected, required this.onTap});

  final CreateLevel level;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    // MergeSemantics 가 있어야 라벨(Semantics)과 탭 동작(InkWell)이 한 노드가 된다.
    // Semantics 만 얹고 안을 ExcludeSemantics 로 덮으면 읽히기는 해도 눌리지 않는다.
    return MergeSemantics(
      child: Semantics(
        inMutuallyExclusiveGroup: true,
        selected: selected,
        label: '${level.label}, ${level.hint}',
        child: Material(
          color: selected ? p.brandPrimarySubtle : p.surfaceRaised,
          borderRadius: BorderRadius.circular(DsRadius.lg),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(DsRadius.lg),
            child: Container(
              constraints: const BoxConstraints(minHeight: 56),
              padding: const EdgeInsets.symmetric(horizontal: DsSpace.s4, vertical: DsSpace.s3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(DsRadius.lg),
                border: Border.all(
                  color: selected ? p.brandPrimary : p.borderSubtle,
                  width: selected ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          level.label,
                          style: dsTextStyle(
                            DsType.bodyLg,
                            selected ? p.brandTextOnSubtle : p.textPrimary,
                          ).copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: DsSpace.s1),
                        Text(level.hint, style: dsTextStyle(DsType.caption, p.textSecondary)),
                      ],
                    ),
                  ),
                  if (selected) DsIcon(DsIcons.success, size: 20, color: p.brandPrimary),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 만들기가 실패했을 때 입력칸 아래에 붙는 알림. 화면을 갈아엎지 않는다 —
/// 사용자가 적은 주제는 그대로 남아 있어야 다시 누를 수 있다.
class _ErrorNotice extends StatelessWidget {
  const _ErrorNotice({required this.error});
  final AppError error;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    final inProgress = error.code == 'generation_in_progress';

    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(DsSpace.s4),
        decoration: BoxDecoration(
          color: inProgress ? p.statusBgInfo : p.statusBgDanger,
          borderRadius: BorderRadius.circular(DsRadius.md),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DsIcon(
              inProgress ? DsIcons.info : DsIcons.warning,
              size: 18,
              color: inProgress ? p.statusInfo : p.statusDanger,
            ),
            const SizedBox(width: DsSpace.s2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (inProgress)
                    Text(
                      '만드는 중인 학습지가 있어요',
                      style: dsTextStyle(
                        DsType.body,
                        p.textPrimary,
                      ).copyWith(fontWeight: FontWeight.w600),
                    ),
                  if (inProgress) const SizedBox(height: DsSpace.s1),
                  // 서버 원문이 아니라 AppError.message 만 나간다.
                  Text(error.message, style: dsTextStyle(DsType.body, p.textSecondary)),
                  if (inProgress) ...[
                    const SizedBox(height: DsSpace.s2),
                    TextButton(
                      onPressed: () => context.go(Routes.library),
                      child: const Text('서재에서 보기'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

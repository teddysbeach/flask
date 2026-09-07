import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:onpar_design_system/onpar_design_system.dart';

import '../../core/analytics.dart';
import '../../core/app_error.dart';
import '../../core/routes.dart';
import '../../data/auth_repository.dart';
import '../../data/profile_repository.dart';
import '../../ui/states/app_state_views.dart';
import '../../ui/widgets/feedback.dart';
import '../settings/settings_tile.dart';

/// 회원탈퇴.
///
/// 세 단계로 나눈 이유는 시간을 끌려는 게 아니라, **되돌릴 수 없는 일 앞에서
/// 무엇이 사라지는지 실제로 읽게 하려는 것**이다. 한 화면에 다 넣으면 아무도 안 읽는다.
///
/// 반대로 탈퇴를 막지도 않는다. 소모성 결제라 남은 구독도 없고,
/// 계정을 지우기 어렵게 만드는 앱은 심사에서도, 신뢰에서도 진다.
class WithdrawScreen extends ConsumerStatefulWidget {
  const WithdrawScreen({super.key});

  @override
  ConsumerState<WithdrawScreen> createState() => _WithdrawScreenState();
}

/// 탈퇴 사유. `reason` 으로 서버에 가는 것은 왼쪽 키다(자유 입력은 detail 로 따로 간다).
enum WithdrawReason {
  quality('만들어지는 학습지가 기대와 달라요'),
  price('가격이 부담돼요'),
  noNeed('지금은 쓸 일이 없어졌어요'),
  bug('앱이 불편하거나 오류가 잦아요'),
  privacy('개인정보가 걱정돼요'),
  alternative('다른 방법을 쓰기로 했어요'),
  other('그 밖의 이유');

  const WithdrawReason(this.label);
  final String label;
}

class _WithdrawScreenState extends ConsumerState<WithdrawScreen> {
  static const _confirmWord = '탈퇴';

  int _step = 0;
  WithdrawReason? _reason;
  final _detail = TextEditingController();
  final _confirm = TextEditingController();

  bool _working = false;
  bool _done = false;
  AppError? _error;

  @override
  void initState() {
    super.initState();
    _detail.addListener(() => setState(() {}));
    _confirm.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _detail.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return const _WithdrawDone();

    return PopScope(
      canPop: !_working,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('회원탈퇴'),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(4),
            child: _StepBar(step: _step, total: 3),
          ),
        ),
        body: SafeArea(
          child: switch (_step) {
            0 => _StepWarning(onNext: () => setState(() => _step = 1)),
            1 => _StepReason(
                reason: _reason,
                detail: _detail,
                onPick: (r) => setState(() => _reason = r),
                onBack: () => setState(() => _step = 0),
                onNext: () => setState(() => _step = 2),
              ),
            _ => _StepConfirm(
                confirm: _confirm,
                confirmWord: _confirmWord,
                working: _working,
                error: _error,
                onBack: _working ? null : () => setState(() => _step = 1),
                onSubmit: _canSubmit ? _submit : null,
              ),
          },
        ),
      ),
    );
  }

  bool get _canSubmit => !_working && _confirm.text.trim() == _confirmWord;

  Future<void> _submit() async {
    // 확인 창 **앞에서** 센다. 여기와 withdrawComplete 사이의 차이가
    // "마지막에 마음을 돌린 사람" 이고, 그게 탈퇴 흐름에서 볼 만한 유일한 숫자다.
    ref.read(analyticsProvider).track(AnalyticsEvent.withdrawStart,
        props: {'reason': (_reason ?? WithdrawReason.other).name});
    final ok = await AppFeedback.confirm(
      context,
      title: '정말 탈퇴할까요?',
      message: '학습지와 필기가 모두 지워지고 되돌릴 수 없어요. 남은 장수도 환불되지 않아요.',
      confirmLabel: '탈퇴하기',
      cancelLabel: '돌아가기',
      destructive: true,
    );
    if (!ok || !mounted) return;

    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).deleteAccount(
            reason: (_reason ?? WithdrawReason.other).name,
            detail: _detail.text.trim(),
          );
      if (!mounted) return;
      // 탈퇴 사유는 닫힌 목록(enum 키)이라 실어도 안전하다. 자유 입력(detail)은 싣지 않는다.
      ref.read(analyticsProvider).track(AnalyticsEvent.withdrawComplete,
          props: {'reason': (_reason ?? WithdrawReason.other).name});
      // 로컬 플래그·보안 저장소 정리와 화면 이동은 라우터가 authState 변화를 보고 한다.
      setState(() {
        _done = true;
        _working = false;
      });
    } on AppError catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _working = false;
      });
    } catch (e, st) {
      if (!mounted) return;
      setState(() {
        _error = AppError.from(e, st);
        _working = false;
      });
    }
  }
}

class _StepBar extends StatelessWidget {
  const _StepBar({required this.step, required this.total});
  final int step;
  final int total;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    return Semantics(
      liveRegion: true,
      label: '$total단계 중 ${step + 1}단계',
      child: Row(
        children: [
          for (var i = 0; i < total; i++)
            Expanded(
              child: Container(
                height: 4,
                margin: EdgeInsets.only(right: i == total - 1 ? 0 : 2),
                color: i <= step ? p.brandPrimary : p.borderSubtle,
              ),
            ),
        ],
      ),
    );
  }
}

/// 1단계 — 무엇이 사라지는가.
class _StepWarning extends ConsumerWidget {
  const _StepWarning({required this.onNext});
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = DsTheme.of(context);
    final profile = ref.watch(profileProvider);
    final remaining = profile.valueOrNull?.quotaRemaining;

    return ListView(
      padding: const EdgeInsets.fromLTRB(DsSpace.s4, DsSpace.s6, DsSpace.s4, DsSpace.s12),
      children: [
        Text('탈퇴하면 이런 것들이 사라져요', style: dsTextStyle(DsType.h2, p.textPrimary)),
        const SizedBox(height: DsSpace.s2),
        Text(
          '아래 내용은 되돌릴 수 없어요. 같은 이메일로 다시 가입해도 돌아오지 않아요.',
          style: dsTextStyle(DsType.body, p.textSecondary),
        ),
        const SizedBox(height: DsSpace.s6),

        // 남은 장수 경고. 구독이 아니라 소모성 결제라 탈퇴를 막지는 않지만,
        // 돈으로 산 것이 사라진다는 사실은 반드시 눈에 보여야 한다.
        if (profile.isLoading)
          const SkeletonBox(height: 64)
        else if (remaining != null && remaining > 0)
          NoticeBox(
            tone: NoticeTone.danger,
            title: '$remaining장이 남아 있어요',
            text: '탈퇴하면 남은 $remaining장은 사라지고, 환불되지 않아요. '
                '다 쓰고 나서 탈퇴하시는 편을 권해 드려요.',
          )
        else if (profile.hasError)
          NoticeBox(
            tone: NoticeTone.warning,
            title: '남은 장수를 확인하지 못했어요',
            text: '남은 장수가 있다면 탈퇴와 함께 사라지고 환불되지 않아요. '
                '확인하고 진행하고 싶으시면 잠시 뒤에 다시 들어와 주세요.',
          ),
        if (profile.isLoading || remaining != null || profile.hasError)
          const SizedBox(height: DsSpace.s6),

        _DeleteList(items: const [
          (
            '만든 학습지 전부',
            '지금까지 만든 학습지가 모두 지워져요. 보관함에서도 사라지고 다시 열 수 없어요.',
          ),
          (
            '학습지에 남긴 필기',
            '애플펜슬이나 손으로 쓴 필기, 형광펜 표시가 모두 지워져요.',
          ),
          (
            '복습 일정과 알림',
            '망각곡선에 맞춰 잡혀 있던 복습 일정이 사라지고, 알림도 더 오지 않아요.',
          ),
          (
            '문제 응답 기록',
            '풀었던 문제의 답과 맞춘 기록이 지워져요.',
          ),
          (
            '남은 학습지 장수',
            '남아 있는 장수는 사라져요. 환불되지 않아요.',
          ),
        ]),
        const SizedBox(height: DsSpace.s6),
        const NoticeBox(
          title: '구매 내역은 남아요',
          text: '전자상거래법이 정한 기간(5년) 동안 구매 내역을 보관해야 해요. '
              '이때는 누구의 것인지 알 수 없게 바꿔서 남겨요. 계정과는 더 이상 이어지지 않아요.',
        ),
        const SizedBox(height: DsSpace.s6),
        Text(
          '잠깐 쉬고 싶은 거라면 로그아웃만 하셔도 돼요. 학습지와 필기는 그대로 있어요.',
          style: dsTextStyle(DsType.body, p.textSecondary),
        ),
        const SizedBox(height: DsSpace.s6),
        FilledButton(onPressed: onNext, child: const Text('그래도 탈퇴할래요')),
        const SizedBox(height: DsSpace.s2),
        OutlinedButton(
          onPressed: () => context.pop(),
          child: const Text('돌아가기'),
        ),
        const SizedBox(height: DsSpace.s2),
        TextButton(
          onPressed: () => context.push(Routes.support),
          child: const Text('문제가 있다면 먼저 문의해 주세요'),
        ),
      ],
    );
  }
}

class _DeleteList extends StatelessWidget {
  const _DeleteList({required this.items});
  final List<(String, String)> items;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    return Column(
      children: [
        for (final (title, body) in items)
          Padding(
            padding: const EdgeInsets.only(bottom: DsSpace.s4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 아이콘 + 글자로 뜻을 말한다. 빨간색만으로는 아무 정보도 아니다.
                DsIcon(DsIcons.close, size: 18, color: p.statusDanger, semanticLabel: '삭제됨'),
                const SizedBox(width: DsSpace.s3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: dsTextStyle(DsType.bodyLg, p.textPrimary)),
                      const SizedBox(height: DsSpace.s1),
                      Text(body, style: dsTextStyle(DsType.body, p.textSecondary)),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 2단계 — 왜 떠나시나요. 답하지 않아도 넘어갈 수 있다.
class _StepReason extends StatelessWidget {
  const _StepReason({
    required this.reason,
    required this.detail,
    required this.onPick,
    required this.onBack,
    required this.onNext,
  });

  final WithdrawReason? reason;
  final TextEditingController detail;
  final ValueChanged<WithdrawReason> onPick;
  final VoidCallback onBack;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    return ListView(
      padding: EdgeInsets.fromLTRB(
        DsSpace.s4,
        DsSpace.s6,
        DsSpace.s4,
        DsSpace.s12 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      children: [
        Text('왜 떠나시나요?', style: dsTextStyle(DsType.h2, p.textPrimary)),
        const SizedBox(height: DsSpace.s2),
        Text(
          '답하지 않으셔도 탈퇴할 수 있어요. 알려 주시면 다음 사람에게 같은 일이 없도록 고칠게요.',
          style: dsTextStyle(DsType.body, p.textSecondary),
        ),
        const SizedBox(height: DsSpace.s6),
        for (final r in WithdrawReason.values)
          _ReasonRow(reason: r, selected: reason == r, onTap: () => onPick(r)),
        const SizedBox(height: DsSpace.s4),
        TextField(
          controller: detail,
          minLines: 3,
          maxLines: 6,
          maxLength: 500,
          keyboardType: TextInputType.multiline,
          decoration: const InputDecoration(
            labelText: '더 하고 싶은 말 (선택)',
            hintText: '어떤 점이 아쉬우셨는지 적어 주시면 큰 도움이 돼요.',
          ),
        ),
        const SizedBox(height: DsSpace.s6),
        FilledButton(onPressed: onNext, child: const Text('다음')),
        const SizedBox(height: DsSpace.s2),
        OutlinedButton(onPressed: onBack, child: const Text('이전')),
      ],
    );
  }
}

/// 사유 한 줄. 선택 여부를 색이 아니라 아이콘과 `Semantics.selected` 로 알린다.
class _ReasonRow extends StatelessWidget {
  const _ReasonRow({required this.reason, required this.selected, required this.onTap});

  final WithdrawReason reason;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    return Semantics(
      inMutuallyExclusiveGroup: true,
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DsRadius.md),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: DsSpace.s2),
            child: Row(
              children: [
                DsIcon(
                  selected ? DsIcons.success : DsIcons.info,
                  size: 20,
                  color: selected ? p.brandPrimary : p.textTertiary,
                ),
                const SizedBox(width: DsSpace.s3),
                Expanded(
                  child: Text(
                    reason.label,
                    style: dsTextStyle(DsType.body, selected ? p.textPrimary : p.textSecondary),
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

/// 3단계 — 마지막 확인. 손가락이 미끄러져서 지워지는 일은 없어야 한다.
class _StepConfirm extends StatelessWidget {
  const _StepConfirm({
    required this.confirm,
    required this.confirmWord,
    required this.working,
    required this.error,
    required this.onBack,
    required this.onSubmit,
  });

  final TextEditingController confirm;
  final String confirmWord;
  final bool working;
  final AppError? error;
  final VoidCallback? onBack;
  final Future<void> Function()? onSubmit;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    final typed = confirm.text.trim();
    final matched = typed == confirmWord;

    return ListView(
      padding: EdgeInsets.fromLTRB(
        DsSpace.s4,
        DsSpace.s6,
        DsSpace.s4,
        DsSpace.s12 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      children: [
        Text('마지막으로 확인할게요', style: dsTextStyle(DsType.h2, p.textPrimary)),
        const SizedBox(height: DsSpace.s2),
        Text(
          '학습지, 필기, 복습 일정, 응답 기록이 모두 지워져요. 남은 장수는 환불되지 않아요. '
          '되돌릴 수 없어요.',
          style: dsTextStyle(DsType.body, p.textSecondary),
        ),
        const SizedBox(height: DsSpace.s6),
        Text(
          '계속하시려면 아래 칸에 "$confirmWord" 를 그대로 적어 주세요.',
          style: dsTextStyle(DsType.bodyLg, p.textPrimary),
        ),
        const SizedBox(height: DsSpace.s3),
        TextField(
          controller: confirm,
          enabled: !working,
          textInputAction: TextInputAction.done,
          autocorrect: false,
          decoration: InputDecoration(
            hintText: confirmWord,
            // 틀렸다고 나무라지 않는다. 남은 조건만 알려 준다.
            helperText: typed.isEmpty || matched ? null : '"$confirmWord" 만 적어 주세요.',
            suffixIcon: matched
                ? Padding(
                    padding: const EdgeInsets.only(right: DsSpace.s3),
                    child: DsIcon(
                      DsIcons.success,
                      size: 20,
                      color: p.statusSuccess,
                      semanticLabel: '확인됨',
                    ),
                  )
                : null,
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: DsSpace.s4),
          Semantics(
            liveRegion: true,
            child: NoticeBox(tone: NoticeTone.danger, text: error!.message),
          ),
        ],
        const SizedBox(height: DsSpace.s6),
        OnceButton(
          enabled: matched && !working,
          onPressed: onSubmit,
          style: FilledButton.styleFrom(backgroundColor: p.statusDanger),
          child: Text(working ? '탈퇴하는 중' : '탈퇴하기'),
        ),
        const SizedBox(height: DsSpace.s2),
        OutlinedButton(onPressed: onBack, child: const Text('이전')),
      ],
    );
  }
}

/// 탈퇴 완료. 여기서 로그인 화면으로 보내는 것은 라우터지만,
/// 사용자가 "정말 끝났구나" 를 볼 수 있는 화면은 있어야 한다.
class _WithdrawDone extends StatelessWidget {
  const _WithdrawDone();

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(DsSpace.s6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              DsIcon(DsIcons.success, size: 40, color: p.textTertiary, semanticLabel: '완료'),
              const SizedBox(height: DsSpace.s4),
              Semantics(
                liveRegion: true,
                child: Text(
                  '탈퇴가 끝났어요',
                  textAlign: TextAlign.center,
                  style: dsTextStyle(DsType.h2, p.textPrimary),
                ),
              ),
              const SizedBox(height: DsSpace.s3),
              Text(
                '그동안 ONPAR 을 써 주셔서 고마웠어요.\n'
                '학습지와 필기는 지워졌고, 구매 내역만 법이 정한 기간 동안 익명으로 남아요.\n'
                '언젠가 다시 배우고 싶어지면 새로 가입해 주세요.',
                textAlign: TextAlign.center,
                style: dsTextStyle(DsType.body, p.textSecondary),
              ),
              const SizedBox(height: DsSpace.s8),
              FilledButton(
                onPressed: () => context.go(Routes.login),
                child: const Text('처음 화면으로'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

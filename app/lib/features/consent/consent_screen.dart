import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:onpar_design_system/onpar_design_system.dart';

import '../../core/bootstrap.dart';
import '../../core/routes.dart';
import '../../domain/models.dart';
import '../../ui/widgets/feedback.dart';

/// 약관 동의.
///
/// 필수와 선택을 섞어서 한 번에 받으면 동의가 아니라 체념이 된다.
/// 그래서 두 묶음을 시각적으로 갈라 두고, **선택은 꺼진 채로 시작**한다.
/// 전체 동의는 편의를 위한 것일 뿐이라 선택 항목까지 켜지는 것을 문구로 알린다.
class ConsentScreen extends ConsumerStatefulWidget {
  const ConsentScreen({super.key, this.onDone});

  /// 동의를 마친 뒤 갈 곳. 라우터가 정해서 넘긴다.
  /// 안 넘기면 로그인으로 — 부팅 순서상 약관 다음은 로그인이다.
  final VoidCallback? onDone;

  /// 약관 버전. 내용이 바뀌면 올리고, 그때 사용자에게 다시 받는다.
  static const version = '1';

  @override
  ConsumerState<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends ConsumerState<ConsentScreen> {
  bool _terms = false;
  bool _privacy = false;
  bool _marketing = false;

  bool get _requiredDone => _terms && _privacy;
  bool get _allChecked => _terms && _privacy && _marketing;

  void _setAll(bool value) => setState(() {
        _terms = value;
        _privacy = value;
        _marketing = value;
      });

  Future<void> _submit() async {
    if (!_requiredDone) return;
    final record = ConsentRecord(
      terms: _terms,
      privacy: _privacy,
      marketing: _marketing,
      agreedAt: DateTime.now().toUtc(),
      version: ConsentScreen.version,
    );
    try {
      await ref.read(localFlagsProvider).setConsent(record);
    } catch (_) {
      if (!mounted) return;
      AppFeedback.toast(context, '동의를 저장하지 못했어요. 다시 시도해 주세요.', danger: true);
      return;
    }
    // TODO(analytics): consentAccept
    if (!mounted) return;
    final onDone = widget.onDone;
    if (onDone != null) {
      onDone();
    } else {
      context.go(Routes.login);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    return Scaffold(
      backgroundColor: p.surfaceBase,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(DsSpace.s6, DsSpace.s8, DsSpace.s6, DsSpace.s6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('시작하기 전에\n약관에 동의해 주세요',
                        style: dsTextStyle(DsType.h1, p.textPrimary)),
                    const SizedBox(height: DsSpace.s3),
                    Text(
                      '필수 항목에 동의하셔야 ONPAR 를 쓸 수 있어요. 선택 항목은 안 하셔도 괜찮아요.',
                      style: dsTextStyle(DsType.body, p.textSecondary),
                    ),
                    const SizedBox(height: DsSpace.s6),
                    _AllAgreeTile(
                      checked: _allChecked,
                      onChanged: _setAll,
                    ),
                    const SizedBox(height: DsSpace.s6),
                    _SectionLabel(label: '필수', tone: p.statusDanger, background: p.statusBgDanger),
                    const SizedBox(height: DsSpace.s2),
                    _ConsentTile(
                      label: '이용약관에 동의해요',
                      isRequired: true,
                      checked: _terms,
                      onChanged: (v) => setState(() => _terms = v),
                      onView: () => context.push(Routes.terms),
                    ),
                    _ConsentTile(
                      label: '개인정보처리방침에 동의해요',
                      isRequired: true,
                      checked: _privacy,
                      onChanged: (v) => setState(() => _privacy = v),
                      onView: () => context.push(Routes.privacy),
                    ),
                    const SizedBox(height: DsSpace.s6),
                    _SectionLabel(label: '선택', tone: p.textSecondary, background: p.surfaceSunken),
                    const SizedBox(height: DsSpace.s2),
                    _ConsentTile(
                      label: '새 소식과 혜택을 메일로 받을게요',
                      description: '안 켜셔도 서비스는 그대로 쓸 수 있어요. 설정에서 언제든 바꿀 수 있어요.',
                      isRequired: false,
                      checked: _marketing,
                      onChanged: (v) => setState(() => _marketing = v),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(DsSpace.s6, DsSpace.s2, DsSpace.s6, DsSpace.s6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!_requiredDone)
                    Padding(
                      padding: const EdgeInsets.only(bottom: DsSpace.s2),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          '필수 항목 두 가지에 동의하시면 다음으로 갈 수 있어요.',
                          textAlign: TextAlign.center,
                          style: dsTextStyle(DsType.caption, p.textSecondary),
                        ),
                      ),
                    ),
                  OnceButton(
                    enabled: _requiredDone,
                    onPressed: _requiredDone ? _submit : null,
                    child: const Text('동의하고 시작하기'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.tone, required this.background});

  final String label;
  final Color tone;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: DsSpace.s2, vertical: 2),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(DsRadius.sm)),
      child: Text(label, style: dsTextStyle(DsType.caption, tone).copyWith(fontWeight: FontWeight.w700)),
    );
  }
}

class _AllAgreeTile extends StatelessWidget {
  const _AllAgreeTile({required this.checked, required this.onChanged});

  final bool checked;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    return InkWell(
      onTap: () => onChanged(!checked),
      borderRadius: BorderRadius.circular(DsRadius.lg),
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: DsSpace.s3, vertical: DsSpace.s3),
        decoration: BoxDecoration(
          color: p.surfaceRaised,
          border: Border.all(color: checked ? p.brandPrimary : p.borderSubtle),
          borderRadius: BorderRadius.circular(DsRadius.lg),
        ),
        child: Row(
          children: [
            Checkbox(
              value: checked,
              onChanged: (v) => onChanged(v ?? false),
              semanticLabel: '전체 동의',
            ),
            const SizedBox(width: DsSpace.s1),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('전체 동의',
                      style: dsTextStyle(DsType.bodyLg, p.textPrimary)
                          .copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text('선택 항목까지 함께 켜져요',
                      style: dsTextStyle(DsType.caption, p.textSecondary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConsentTile extends StatelessWidget {
  const _ConsentTile({
    required this.label,
    required this.isRequired,
    required this.checked,
    required this.onChanged,
    this.description,
    this.onView,
  });

  final String label;
  final String? description;
  final bool isRequired;
  final bool checked;
  final ValueChanged<bool> onChanged;
  final VoidCallback? onView;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: DsSpace.s1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: InkWell(
              onTap: () => onChanged(!checked),
              borderRadius: BorderRadius.circular(DsRadius.md),
              child: Container(
                constraints: const BoxConstraints(minHeight: 48),
                padding: const EdgeInsets.symmetric(vertical: DsSpace.s1),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Checkbox(
                      value: checked,
                      onChanged: (v) => onChanged(v ?? false),
                      // 스크린리더가 필수·선택을 함께 읽도록 이름에 담는다.
                      semanticLabel: '${isRequired ? '필수' : '선택'} · $label',
                    ),
                    const SizedBox(width: DsSpace.s1),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: DsSpace.s3),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: isRequired ? '[필수] ' : '[선택] ',
                                    style: dsTextStyle(
                                      DsType.body,
                                      isRequired ? p.statusDanger : p.textTertiary,
                                    ).copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  TextSpan(text: label, style: dsTextStyle(DsType.body, p.textPrimary)),
                                ],
                              ),
                            ),
                            if (description != null) ...[
                              const SizedBox(height: 2),
                              Text(description!, style: dsTextStyle(DsType.caption, p.textSecondary)),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (onView != null)
            TextButton(
              onPressed: onView,
              child: Text('보기', style: dsTextStyle(DsType.body, p.textSecondary)),
            ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:onpar_design_system/onpar_design_system.dart';

import '../../core/app_error.dart';
import '../../data/auth_repository.dart';
import '../../ui/widgets/feedback.dart';
import '../auth/password_policy.dart';

/// 비밀번호 변경.
///
/// 규칙은 여기서 새로 쓰지 않고 `PasswordPolicy.check()` 를 그대로 쓴다 —
/// 가입과 변경이 다른 규칙을 들면, 가입은 통과했는데 변경에서 막히는 계정이 생긴다.
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _confirmFocus = FocusNode();

  bool _obscure = true;
  bool _submitted = false;
  AppError? _error;

  @override
  void initState() {
    super.initState();
    _password.addListener(_onChanged);
    _confirm.addListener(_onChanged);
  }

  void _onChanged() => setState(() => _error = null);

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  bool get _dirty => _password.text.isNotEmpty || _confirm.text.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    final check = PasswordPolicy.check(_password.text);
    final matched = PasswordPolicy.matches(_password.text, _confirm.text);
    final canSubmit = check.ok && matched;

    return PopScope(
      // 입력하다 실수로 뒤로 가면 처음부터 다시 쳐야 한다.
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || !_dirty) return;
        final leave = await AppFeedback.confirm(
          context,
          title: '입력을 그만둘까요?',
          message: '적으신 비밀번호는 저장되지 않아요.',
          confirmLabel: '그만두기',
          cancelLabel: '계속 쓰기',
        );
        if (leave && context.mounted) context.pop();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('비밀번호 변경')),
        body: SafeArea(
          child: DsFadeSlide(
            child: ListView(
              padding: const EdgeInsets.all(DsSpace.s4),
              children: [
                Text(
                  '새로 쓸 비밀번호를 정해 주세요. 바꾸고 나면 다음 로그인부터 새 비밀번호를 쓰게 돼요.',
                  style: dsTextStyle(DsType.body, p.textSecondary),
                ),
                const SizedBox(height: DsSpace.s6),
                TextField(
                  controller: _password,
                  obscureText: _obscure,
                  autofillHints: const [AutofillHints.newPassword],
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => _confirmFocus.requestFocus(),
                  decoration: InputDecoration(
                    labelText: '새 비밀번호',
                    suffixIcon: IconButton(
                      // 48dp 기본 크기를 가진 IconButton 을 쓴다.
                      onPressed: () => setState(() => _obscure = !_obscure),
                      icon: DsIcon(
                        _obscure ? DsIcons.info : DsIcons.close,
                        size: 20,
                        color: p.textSecondary,
                      ),
                      tooltip: _obscure ? '비밀번호 보기' : '비밀번호 가리기',
                    ),
                  ),
                ),
                const SizedBox(height: DsSpace.s3),
                _Rules(rules: check.rules),
                const SizedBox(height: DsSpace.s4),
                TextField(
                  controller: _confirm,
                  focusNode: _confirmFocus,
                  obscureText: _obscure,
                  autofillHints: const [AutofillHints.newPassword],
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: '새 비밀번호 확인',
                    errorText: _confirm.text.isEmpty || matched ? null : '두 칸이 서로 달라요.',
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: DsSpace.s4),
                  Semantics(
                    liveRegion: true,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DsIcon(DsIcons.warning, size: 18, color: p.statusDanger, semanticLabel: '오류'),
                        const SizedBox(width: DsSpace.s2),
                        Expanded(
                          child: Text(_error!.message, style: dsTextStyle(DsType.body, p.statusDanger)),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: DsSpace.s6),
                OnceButton(
                  enabled: canSubmit,
                  onPressed: canSubmit ? _submit : null,
                  child: const Text('비밀번호 바꾸기'),
                ),
                const SizedBox(height: DsSpace.s4),
                Text(
                  '비밀번호가 기억나지 않으면 로그아웃한 뒤 "비밀번호 찾기" 로 다시 정할 수 있어요.',
                  style: dsTextStyle(DsType.caption, p.textTertiary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (_submitted) return;
    setState(() {
      _submitted = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).updatePassword(_password.text);
      if (!mounted) return;
      AppFeedback.toast(context, '비밀번호를 바꿨어요.');
      _password.clear();
      _confirm.clear();
      context.pop();
    } on AppError catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    } catch (e, st) {
      if (!mounted) return;
      setState(() => _error = AppError.from(e, st));
    } finally {
      if (mounted) setState(() => _submitted = false);
    }
  }
}

/// 규칙 목록. 통과 여부를 색이 아니라 아이콘과 글로 알린다.
class _Rules extends StatelessWidget {
  const _Rules({required this.rules});
  final List<PasswordRule> rules;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final r in rules)
          Padding(
            padding: const EdgeInsets.only(bottom: DsSpace.s1),
            child: Semantics(
              label: '${r.label}. ${r.met ? '충족' : '아직'}',
              excludeSemantics: true,
              child: Row(
                children: [
                  DsIcon(
                    r.met ? DsIcons.success : DsIcons.info,
                    size: 16,
                    color: r.met ? p.statusSuccess : p.textTertiary,
                  ),
                  const SizedBox(width: DsSpace.s2),
                  Expanded(
                    child: Text(
                      r.label,
                      style: dsTextStyle(DsType.caption, r.met ? p.textSecondary : p.textTertiary),
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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:onpar_design_system/onpar_design_system.dart';

import '../../ui/widgets/feedback.dart';
import 'password_policy.dart';

/// 인증 화면들이 공유하는 입력 위젯.
///
/// 화면마다 TextField 를 다시 만들면 자동완성 힌트·키보드 타입·표시 토글이
/// 화면마다 조금씩 달라진다. 비밀번호 관리자가 한 화면에서만 동작하는 앱이
/// 그렇게 만들어진다 — 그래서 여기 한 벌만 둔다.

/// 필드 아래 오류 문구. 스크린리더가 **바뀐 순간에** 읽도록 liveRegion 으로 둔다.
/// (`InputDecoration.errorText` 대신 `error` 슬롯을 쓰는 이유가 이것이다.)
Widget? authFieldError(BuildContext context, String? text) {
  if (text == null || text.isEmpty) return null;
  final p = DsTheme.of(context);
  return Semantics(
    liveRegion: true,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: DsIcon(DsIcons.warning, size: 14, color: p.statusDanger),
        ),
        const SizedBox(width: DsSpace.s1),
        Expanded(child: Text(text, style: dsTextStyle(DsType.caption, p.statusDanger))),
      ],
    ),
  );
}

/// 폼 전체에 걸리는 오류(로그인 실패 등). 필드 아래 인라인으로 놓는다.
class AuthFormError extends StatelessWidget {
  const AuthFormError({super.key, required this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final text = message;
    if (text == null || text.isEmpty) return const SizedBox.shrink();
    final p = DsTheme.of(context);
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: DsSpace.s3),
        padding: const EdgeInsets.symmetric(horizontal: DsSpace.s3, vertical: DsSpace.s3),
        decoration: BoxDecoration(
          color: p.statusBgDanger,
          borderRadius: BorderRadius.circular(DsRadius.md),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: DsIcon(DsIcons.warning, size: 16, color: p.statusDanger),
            ),
            const SizedBox(width: DsSpace.s2),
            Expanded(child: Text(text, style: dsTextStyle(DsType.body, p.statusDanger))),
          ],
        ),
      ),
    );
  }
}

/// 라벨 + 입력칸. 라벨을 `labelText` 로 띄우지 않고 위에 따로 두는 이유는
/// 글꼴을 크게 키운 사용자에게 떠 있는 라벨이 입력값을 덮기 때문이다.
class AuthFieldShell extends StatelessWidget {
  const AuthFieldShell({super.key, required this.label, required this.child, this.trailing});

  final String label;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: dsTextStyle(DsType.body, p.textSecondary).copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
        const SizedBox(height: DsSpace.s2),
        child,
      ],
    );
  }
}

class EmailField extends StatelessWidget {
  const EmailField({
    super.key,
    required this.controller,
    this.focusNode,
    this.label = '이메일',
    this.hint = 'onpar@example.com',
    this.errorText,
    this.enabled = true,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final String label;
  final String hint;
  final String? errorText;
  final bool enabled;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return AuthFieldShell(
      label: label,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        enabled: enabled,
        autofocus: autofocus,
        keyboardType: TextInputType.emailAddress,
        textInputAction: textInputAction,
        autocorrect: false,
        enableSuggestions: false,
        textCapitalization: TextCapitalization.none,
        autofillHints: const [AutofillHints.email, AutofillHints.username],
        onSubmitted: onSubmitted,
        // 이메일에 공백이 들어가면 원인을 찾기 어려운 실패가 된다. 입력 단계에서 막는다.
        inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
        decoration: InputDecoration(hintText: hint, error: authFieldError(context, errorText)),
      ),
    );
  }
}

/// 비밀번호 입력. 표시/숨김 토글에 반드시 이름이 붙는다.
class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    this.focusNode,
    this.label = '비밀번호',
    this.hint,
    this.errorText,
    this.enabled = true,
    this.isNewPassword = false,
    this.textInputAction = TextInputAction.done,
    this.onSubmitted,
    this.onChanged,
    this.trailing,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final String label;
  final String? hint;
  final String? errorText;
  final bool enabled;

  /// 새로 정하는 비밀번호면 true — 비밀번호 관리자가 '저장'을 제안하게 하는 힌트다.
  final bool isNewPassword;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;

  /// 라벨 오른쪽에 붙일 것(예: "계정 찾기").
  final Widget? trailing;
  final bool autofocus;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    return AuthFieldShell(
      label: widget.label,
      trailing: widget.trailing,
      child: TextField(
        controller: widget.controller,
        focusNode: widget.focusNode,
        enabled: widget.enabled,
        autofocus: widget.autofocus,
        obscureText: !_visible,
        keyboardType: _visible ? TextInputType.visiblePassword : null,
        textInputAction: widget.textInputAction,
        autocorrect: false,
        enableSuggestions: false,
        autofillHints: [
          widget.isNewPassword ? AutofillHints.newPassword : AutofillHints.password,
        ],
        onSubmitted: widget.onSubmitted,
        onChanged: widget.onChanged,
        decoration: InputDecoration(
          hintText: widget.hint,
          error: authFieldError(context, widget.errorText),
          // 터치 영역 48dp 를 유지하려고 IconButton 기본 크기를 줄이지 않는다.
          suffixIcon: IconButton(
            onPressed: () => setState(() => _visible = !_visible),
            tooltip: _visible ? '비밀번호 숨기기' : '비밀번호 보기',
            // 눈 아이콘은 디자인 시스템에 없어서 Material 것을 쓴다.
            // 돋보기로 대신하면 '검색'으로 읽혀서 뜻이 달라진다.
            icon: Icon(
              _visible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              size: 22,
              color: p.textSecondary,
              semanticLabel: _visible ? '비밀번호 숨기기' : '비밀번호 보기',
            ),
          ),
        ),
      ),
    );
  }
}

/// 비밀번호 규칙 체크리스트. 충족 여부를 **아이콘과 문구**로도 알려 준다 —
/// 색만 바꾸면 색을 구분하지 못하는 사용자에게는 아무 변화도 아니다.
class PasswordRulesView extends StatelessWidget {
  const PasswordRulesView({super.key, required this.password});

  final String password;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    final result = PasswordPolicy.check(password);
    return Semantics(
      liveRegion: true,
      label: result.ok ? '비밀번호 조건을 모두 채웠어요' : '비밀번호 조건이 남았어요',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final rule in result.rules)
            Padding(
              padding: const EdgeInsets.only(top: DsSpace.s2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: DsIcon(
                      rule.met ? DsIcons.success : DsIcons.info,
                      size: 16,
                      color: rule.met ? p.statusSuccess : p.textTertiary,
                    ),
                  ),
                  const SizedBox(width: DsSpace.s2),
                  Expanded(
                    child: Text(
                      '${rule.label}${rule.met ? ' (충족)' : ''}',
                      style: dsTextStyle(
                        DsType.caption,
                        rule.met ? p.statusSuccess : p.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 작성 중인 입력이 있는데 뒤로 가려 할 때 한 번 물어본다.
///
/// 비밀번호를 두 번 치고 닉네임까지 넣은 사람이 실수로 스와이프해서 전부 날리면,
/// 그 사람은 대개 다시 오지 않는다. 대신 **비어 있을 때는 묻지 않는다** —
/// 아무것도 안 쓴 사람에게 확인 창을 띄우면 그때부터 아무도 읽지 않는다.
class UnsavedInputGuard extends StatelessWidget {
  const UnsavedInputGuard({
    super.key,
    required this.dirty,
    required this.child,
    this.onLeave,
    this.message = '작성 중인 내용이 사라져요. 나가시겠어요?',
  });

  final bool dirty;
  final Widget child;

  /// 확인을 받은 뒤 실제로 나가는 방법. 기본은 이전 화면으로 돌아가기.
  final VoidCallback? onLeave;
  final String message;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !dirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final leave = await AppFeedback.confirm(
          context,
          title: '나가시겠어요?',
          message: message,
          confirmLabel: '나가기',
          cancelLabel: '계속 쓰기',
          destructive: true,
        );
        if (!leave || !context.mounted) return;
        final leaveAction = onLeave;
        if (leaveAction != null) {
          leaveAction();
        } else {
          Navigator.of(context).pop();
        }
      },
      child: child,
    );
  }
}

/// 이메일 형태만 본다. 진짜 검증은 인증 메일이 한다 —
/// 정규식으로 엄격하게 막으면 멀쩡한 주소를 가진 사람이 가입을 못 한다.
bool looksLikeEmail(String value) {
  final v = value.trim();
  if (v.length < 5 || v.contains(' ')) return false;
  final at = v.indexOf('@');
  if (at <= 0 || at != v.lastIndexOf('@')) return false;
  final domain = v.substring(at + 1);
  return domain.contains('.') && !domain.startsWith('.') && !domain.endsWith('.');
}

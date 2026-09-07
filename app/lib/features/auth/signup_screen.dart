import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:onpar_design_system/onpar_design_system.dart';

import '../../core/analytics.dart';
import '../../core/app_error.dart';
import '../../core/logger.dart';
import '../../core/routes.dart';
import '../../data/auth_repository.dart';
import '../../data/profile_repository.dart';
import '../../ui/widgets/feedback.dart';
import 'auth_form_fields.dart';
import 'password_policy.dart';
import 'verify_screen.dart';

/// 이메일 가입.
///
/// 비밀번호 규칙은 **누르기 전에** 보여 준다. 제출하고 나서야 "8자 이상" 이라고
/// 말하면 사용자는 방금 만든 비밀번호를 지우고 처음부터 다시 생각해야 한다.
class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _nickname = TextEditingController();

  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _confirmFocus = FocusNode();
  final _nicknameFocus = FocusNode();

  String? _emailError;
  String? _passwordError;
  String? _confirmError;
  String? _nicknameError;
  String? _formError;

  /// 이미 가입된 이메일일 때만 켜진다 — 그때는 가입이 아니라 로그인으로 보내야 한다.
  bool _alreadyRegistered = false;

  bool get _dirty =>
      _email.text.isNotEmpty ||
      _password.text.isNotEmpty ||
      _confirm.text.isNotEmpty ||
      _nickname.text.isNotEmpty;

  @override
  void initState() {
    super.initState();
    ref.read(analyticsProvider).track(AnalyticsEvent.signupStart);
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    _nickname.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _confirmFocus.dispose();
    _nicknameFocus.dispose();
    super.dispose();
  }

  bool _validate() {
    final email = _email.text.trim();
    final password = _password.text;
    final confirm = _confirm.text;
    final nickname = _nickname.text.trim();

    final emailError = looksLikeEmail(email) ? null : '이메일 주소를 다시 확인해 주세요.';
    final passwordError = PasswordPolicy.check(password).ok ? null : '아래 조건을 모두 채워 주세요.';
    final confirmError =
        PasswordPolicy.matches(password, confirm) ? null : '두 번 입력한 비밀번호가 서로 달라요.';
    final nicknameError = switch (nickname.runes.length) {
      < 2 => '2자 이상으로 지어 주세요.',
      > 20 => '20자 이하로 줄여 주세요.',
      _ => null,
    };

    setState(() {
      _emailError = emailError;
      _passwordError = passwordError;
      _confirmError = confirmError;
      _nicknameError = nicknameError;
      _formError = null;
      _alreadyRegistered = false;
    });
    return emailError == null &&
        passwordError == null &&
        confirmError == null &&
        nicknameError == null;
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_validate()) return;

    final email = _email.text.trim();
    final nickname = _nickname.text.trim();

    try {
      await ref
          .read(authRepositoryProvider)
          .signUpWithEmail(email: email, password: _password.text);
    } catch (e, st) {
      if (!mounted) return;
      final error = AppError.from(e, st);
      if (error.isCancelled) return;
      final exists = (error.code ?? '').contains('exists');
      // 이미 가입된 이메일은 우리 쪽 고장이 아니다 — 리포트에 남기면 진짜 고장이 묻힌다.
      if (!exists) ref.read(crashReporterProvider).recordError(e, st, context: 'signup');
      setState(() {
        _alreadyRegistered = exists;
        _emailError = exists ? error.message : null;
        _formError = exists ? null : error.message;
      });
      return;
    }

    // 이메일 확인을 켜 두면 이 시점에 세션이 없다. 그때 닉네임은 인증 후에 저장된다.
    // 확인 없이 바로 세션이 생기는 설정이면 여기서 넣어 두는 편이 사용자에게 자연스럽다.
    final repo = ref.read(authRepositoryProvider);
    if (repo.session != null) {
      try {
        await ref.read(profileRepositoryProvider).update(displayName: nickname);
      } catch (e) {
        // 닉네임은 나중에 설정에서 고칠 수 있다. 여기서 가입 흐름을 막지 않는다.
        AppLogger.error('signup: display name save failed', error: e);
      }
    }

    if (!mounted) return;
    // 이메일 주소·닉네임은 싣지 않는다. 가입이 끝났다는 사실만 남긴다.
    ref.read(analyticsProvider).track(AnalyticsEvent.signupComplete,
        props: {'method': 'password', 'has_session': repo.session != null});
    context.go(Routes.verify, extra: VerifyArgs(mode: VerifyMode.email, target: email));
  }

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    return UnsavedInputGuard(
      dirty: _dirty,
      child: Scaffold(
        backgroundColor: p.surfaceBase,
        appBar: AppBar(title: const Text('가입하기')),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              DsSpace.s6,
              DsSpace.s4,
              DsSpace.s6,
              DsSpace.s6 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: DsFadeSlide(
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('학습지를 만들려면\n계정이 하나 필요해요',
                        style: dsTextStyle(DsType.h2, p.textPrimary)),
                    const SizedBox(height: DsSpace.s8),
                    EmailField(
                      controller: _email,
                      focusNode: _emailFocus,
                      errorText: _emailError,
                      autofocus: true,
                      onSubmitted: (_) => _passwordFocus.requestFocus(),
                    ),
                    if (_alreadyRegistered)
                      Padding(
                        padding: const EdgeInsets.only(top: DsSpace.s2),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton(
                            onPressed: () => context.go(Routes.login),
                            child: const Text('이 이메일로 로그인하기'),
                          ),
                        ),
                      ),
                    const SizedBox(height: DsSpace.s4),
                    PasswordField(
                      controller: _password,
                      focusNode: _passwordFocus,
                      isNewPassword: true,
                      errorText: _passwordError,
                      textInputAction: TextInputAction.next,
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _confirmFocus.requestFocus(),
                    ),
                    const SizedBox(height: DsSpace.s2),
                    PasswordRulesView(password: _password.text),
                    const SizedBox(height: DsSpace.s4),
                    PasswordField(
                      controller: _confirm,
                      focusNode: _confirmFocus,
                      label: '비밀번호 확인',
                      isNewPassword: true,
                      errorText: _confirmError,
                      textInputAction: TextInputAction.next,
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _nicknameFocus.requestFocus(),
                    ),
                    const SizedBox(height: DsSpace.s4),
                    AuthFieldShell(
                      label: '닉네임',
                      child: TextField(
                        controller: _nickname,
                        focusNode: _nicknameFocus,
                        textInputAction: TextInputAction.done,
                        maxLength: 20,
                        autofillHints: const [AutofillHints.nickname],
                        onSubmitted: (_) => unawaited(_submit()),
                        decoration: InputDecoration(
                          hintText: '학습지에 표시될 이름이에요',
                          counterText: '',
                          error: authFieldError(context, _nicknameError),
                        ),
                      ),
                    ),
                    AuthFormError(message: _formError),
                    const SizedBox(height: DsSpace.s8),
                    OnceButton(onPressed: _submit, child: const Text('가입하기')),
                    const SizedBox(height: DsSpace.s4),
                    Text(
                      '가입하면 이메일로 인증 메일을 보내 드려요. 메일을 확인해야 학습지를 만들 수 있어요.',
                      textAlign: TextAlign.center,
                      style: dsTextStyle(DsType.caption, p.textTertiary),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:onpar_design_system/onpar_design_system.dart';

import '../../core/analytics.dart';
import '../../core/app_error.dart';
import '../../core/env.dart';
import '../../core/routes.dart';
import '../../data/auth_repository.dart';
import '../../ui/widgets/feedback.dart';
import 'auth_form_fields.dart';

/// 로그인.
///
/// **성공했을 때 이 화면은 아무 데도 가지 않는다.** 세션이 생기면 라우터가
/// 원래 가려던 곳으로 보낸다. 여기서 같이 밀면 두 번 이동해서 뒤로가기가 꼬인다.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();

  String? _emailError;
  String? _passwordError;
  String? _formError;

  bool get _dirty => _email.text.isNotEmpty || _password.text.isNotEmpty;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  void _clearErrors() => setState(() {
        _emailError = null;
        _passwordError = null;
        _formError = null;
      });

  /// 실패를 화면에 옮긴다. 서버 원문이 아니라 `AppError.message` 만 쓴다.
  void _showFailure(Object error, StackTrace stack) {
    final e = AppError.from(error, stack);
    // 사용자가 소셜 로그인 창을 스스로 닫은 것은 실패가 아니다. 아무 말도 하지 않는다.
    // 취소는 오류가 아니므로 크래시 리포트에도 남기지 않는다 — 남기면 진짜 오류가 묻힌다.
    if (e.isCancelled) return;
    ref.read(crashReporterProvider).recordError(error, stack, context: 'login');
    setState(() {
      if (e.kind == AppErrorKind.validation) {
        // 어느 쪽이 틀렸는지는 알려주지 않는다 — 알려주면 계정 존재 여부가 샌다.
        _passwordError = e.message;
        _formError = null;
      } else {
        _passwordError = null;
        _formError = e.message;
      }
    });
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final email = _email.text.trim();
    final password = _password.text;

    if (!looksLikeEmail(email) || password.isEmpty) {
      setState(() {
        _emailError = looksLikeEmail(email) ? null : '이메일 주소를 다시 확인해 주세요.';
        _passwordError = password.isEmpty ? '비밀번호를 입력해 주세요.' : null;
        _formError = null;
      });
      return;
    }

    _clearErrors();
    try {
      await ref.read(authRepositoryProvider).signInWithEmail(email: email, password: password);
      if (!mounted) return;
      ref.read(analyticsProvider).track(AnalyticsEvent.loginComplete, props: {'method': 'password'});
      // 이동은 라우터가 한다. 여기서는 입력만 정리한다.
      TextInput.finishAutofillContext();
    } catch (e, st) {
      if (!mounted) return;
      _showFailure(e, st);
    }
  }

  Future<void> _signInWithApple() async {
    _clearErrors();
    try {
      await ref.read(authRepositoryProvider).signInWithApple();
      ref.read(analyticsProvider).track(AnalyticsEvent.loginComplete, props: {'method': 'apple'});
    } catch (e, st) {
      if (!mounted) return;
      _showFailure(e, st);
    }
  }

  Future<void> _signInWithGoogle() async {
    _clearErrors();
    try {
      // 값은 진작 Env 에 있었는데 여기서 null 을 넘기고 있었다. iOS 의 google_sign_in 은
      // 클라이언트 ID 없이는 시작조차 못 하므로, 이 버튼은 눌러도 아무 일이 안 일어났다.
      await ref.read(authRepositoryProvider).signInWithGoogle(
            iosClientId: Env.googleIosClientIdOrNull,
            serverClientId: Env.googleServerClientIdOrNull,
          );
      ref.read(analyticsProvider).track(AnalyticsEvent.loginComplete, props: {'method': 'google'});
    } catch (e, st) {
      if (!mounted) return;
      _showFailure(e, st);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    final platform = Theme.of(context).platform;
    // Apple 로그인은 애플 플랫폼에서만 띄운다. 안드로이드에서는 웹 리다이렉트가 필요해
    // 지금 배선으로는 눌러도 돌아오지 못한다 — 안 되는 버튼을 두는 편이 더 나쁘다.
    final showApple = platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;

    return UnsavedInputGuard(
      dirty: _dirty,
      child: Scaffold(
        backgroundColor: p.surfaceBase,
        body: SafeArea(
          child: SingleChildScrollView(
            // 키보드가 올라와도 버튼이 가려지지 않게, 올라온 만큼 아래를 비운다.
            padding: EdgeInsets.fromLTRB(
              DsSpace.s6,
              DsSpace.s8,
              DsSpace.s6,
              DsSpace.s6 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: DsFadeSlide(
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('다시 오셨네요', style: dsTextStyle(DsType.h1, p.textPrimary)),
                    const SizedBox(height: DsSpace.s2),
                    Text('학습지와 복습 기록이 그대로 있어요.',
                        style: dsTextStyle(DsType.body, p.textSecondary)),
                    const SizedBox(height: DsSpace.s8),
                    EmailField(
                      controller: _email,
                      focusNode: _emailFocus,
                      errorText: _emailError,
                      onSubmitted: (_) => _passwordFocus.requestFocus(),
                    ),
                    const SizedBox(height: DsSpace.s4),
                    PasswordField(
                      controller: _password,
                      focusNode: _passwordFocus,
                      errorText: _passwordError,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => unawaited(_submit()),
                      trailing: TextButton(
                        onPressed: () => context.push(Routes.findAccount),
                        child: Text('계정 찾기', style: dsTextStyle(DsType.caption, p.textSecondary)),
                      ),
                    ),
                    AuthFormError(message: _formError),
                    const SizedBox(height: DsSpace.s6),
                    OnceButton(onPressed: _submit, child: const Text('로그인')),
                    const SizedBox(height: DsSpace.s4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('아직 계정이 없으세요?', style: dsTextStyle(DsType.body, p.textSecondary)),
                        TextButton(
                          onPressed: () => context.push(Routes.signup),
                          child: const Text('가입하기'),
                        ),
                      ],
                    ),
                    const SizedBox(height: DsSpace.s6),
                    const _OrDivider(),
                    const SizedBox(height: DsSpace.s6),
                    if (showApple) ...[
                      SocialButton(
                        label: 'Apple 로 계속하기',
                        icon: Icons.apple,
                        onPressed: _signInWithApple,
                      ),
                      const SizedBox(height: DsSpace.s3),
                    ],
                    // 설정이 없는 빌드에서는 아예 안 띄운다. Apple 로그인을 안드로이드에서
                    // 숨기는 것과 같은 규칙이다 — 안 되는 버튼을 두는 편이 더 나쁘다.
                    if (Env.isGoogleSignInConfigured)
                      SocialButton(
                        label: 'Google 로 계속하기',
                        icon: Icons.g_mobiledata,
                        onPressed: _signInWithGoogle,
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

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    return Row(
      children: [
        Expanded(child: Divider(color: p.borderSubtle)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: DsSpace.s3),
          child: Text('또는', style: dsTextStyle(DsType.caption, p.textTertiary)),
        ),
        Expanded(child: Divider(color: p.borderSubtle)),
      ],
    );
  }
}

/// 소셜 로그인 버튼. 누른 뒤 창이 뜨는 동안 두 번 눌리지 않게 스스로 잠근다.
class SocialButton extends StatefulWidget {
  const SocialButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final Future<void> Function() onPressed;

  @override
  State<SocialButton> createState() => _SocialButtonState();
}

class _SocialButtonState extends State<SocialButton> {
  bool _busy = false;

  Future<void> _run() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onPressed();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    return OutlinedButton(
      onPressed: _busy ? null : () => unawaited(_run()),
      child: _busy
          ? SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2.4, color: p.textSecondary),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(widget.icon, size: 22, color: p.textPrimary),
                const SizedBox(width: DsSpace.s2),
                Flexible(child: Text(widget.label, textAlign: TextAlign.center)),
              ],
            ),
    );
  }
}

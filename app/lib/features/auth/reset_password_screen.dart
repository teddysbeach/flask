import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:onpar_design_system/onpar_design_system.dart';

import '../../core/app_error.dart';
import '../../core/routes.dart';
import '../../data/auth_repository.dart';
import '../../ui/widgets/feedback.dart';
import 'auth_form_fields.dart';
import 'password_policy.dart';

/// 메일 링크(딥링크)를 타고 들어와 새 비밀번호를 정하는 화면.
///
/// 여기 들어온 사람은 이미 링크로 신원을 증명했다. 그래서 예전 비밀번호를 묻지 않는다
/// (모르니까 여기 온 것이다).
///
/// 대신 **다른 기기의 로그인이 풀린다는 것을 누르기 전에 알린다.** 비밀번호를 바꾸는
/// 이유가 "누가 내 계정에 들어온 것 같아서" 인 경우가 많고, 그때 이 동작은 기능이다.
/// 모르고 당하면 사고고, 알고 하면 안심이다 — 차이는 이 한 문장뿐이다.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  ConsumerState<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _passwordFocus = FocusNode();
  final _confirmFocus = FocusNode();

  String? _passwordError;
  String? _confirmError;
  String? _formError;
  bool _done = false;

  bool get _dirty => !_done && (_password.text.isNotEmpty || _confirm.text.isNotEmpty);

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    _passwordFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final password = _password.text;
    final confirm = _confirm.text;

    final passwordError = PasswordPolicy.check(password).ok ? null : '아래 조건을 모두 채워 주세요.';
    final confirmError =
        PasswordPolicy.matches(password, confirm) ? null : '두 번 입력한 비밀번호가 서로 달라요.';
    if (passwordError != null || confirmError != null) {
      setState(() {
        _passwordError = passwordError;
        _confirmError = confirmError;
        _formError = null;
      });
      return;
    }

    setState(() {
      _passwordError = null;
      _confirmError = null;
      _formError = null;
    });

    try {
      await ref.read(authRepositoryProvider).updatePassword(password);
    } catch (e, st) {
      if (!mounted) return;
      final error = AppError.from(e, st);
      if (error.isCancelled) return;
      setState(() {
        // 링크가 만료됐거나 이미 쓴 링크면 여기서 걸린다. 다시 받아야 한다는 것까지 알려준다.
        _formError = error.kind == AppErrorKind.unauthorized || error.kind == AppErrorKind.notFound
            ? '이 링크는 더 이상 쓸 수 없어요. 계정 찾기에서 메일을 다시 받아 주세요.'
            : error.message;
      });
      return;
    }

    if (!mounted) return;
    setState(() => _done = true);
  }

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    return UnsavedInputGuard(
      dirty: _dirty,
      child: Scaffold(
        backgroundColor: p.surfaceBase,
        appBar: AppBar(
          title: const Text('비밀번호 새로 정하기'),
          automaticallyImplyLeading: !_done,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              DsSpace.s6,
              DsSpace.s4,
              DsSpace.s6,
              DsSpace.s6 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: _done ? _doneBody(p) : _formBody(p),
          ),
        ),
      ),
    );
  }

  Widget _formBody(DsPalette p) {
    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('새 비밀번호를 정해 주세요', style: dsTextStyle(DsType.h2, p.textPrimary)),
          const SizedBox(height: DsSpace.s4),
          // 되돌릴 수 없는 결과는 버튼 옆이 아니라 **입력 전에** 놓는다.
          const _SessionResetNotice(),
          const SizedBox(height: DsSpace.s6),
          PasswordField(
            controller: _password,
            focusNode: _passwordFocus,
            label: '새 비밀번호',
            isNewPassword: true,
            errorText: _passwordError,
            autofocus: true,
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
            label: '새 비밀번호 확인',
            isNewPassword: true,
            errorText: _confirmError,
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => unawaited(_submit()),
          ),
          AuthFormError(message: _formError),
          const SizedBox(height: DsSpace.s8),
          OnceButton(onPressed: _submit, child: const Text('비밀번호 바꾸기')),
          const SizedBox(height: DsSpace.s3),
          TextButton(
            onPressed: () => context.go(Routes.findAccount),
            child: const Text('링크가 만료됐어요'),
          ),
        ],
      ),
    );
  }

  Widget _doneBody(DsPalette p) {
    return Semantics(
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: DsSpace.s6),
          Align(
            child: Container(
              padding: const EdgeInsets.all(DsSpace.s4),
              decoration: BoxDecoration(color: p.statusBgSuccess, shape: BoxShape.circle),
              child: DsIcon(DsIcons.success, size: 28, color: p.statusSuccess),
            ),
          ),
          const SizedBox(height: DsSpace.s6),
          Text('비밀번호를 바꿨어요',
              textAlign: TextAlign.center, style: dsTextStyle(DsType.h2, p.textPrimary)),
          const SizedBox(height: DsSpace.s3),
          Text(
            '다른 기기에서는 로그인이 풀렸어요. 새 비밀번호로 다시 들어와 주세요.',
            textAlign: TextAlign.center,
            style: dsTextStyle(DsType.bodyLg, p.textSecondary),
          ),
          const SizedBox(height: DsSpace.s8),
          OnceButton(
            onPressed: () async {
              // 재설정 뒤에는 이 기기의 세션도 정리하고 새 비밀번호로 다시 받는다.
              // 그래야 "다른 기기가 다 풀렸다" 는 안내와 실제 상태가 어긋나지 않는다.
              try {
                await ref.read(authRepositoryProvider).signOut();
              } catch (_) {
                // 이미 세션이 없을 수도 있다. 로그인 화면으로 가는 데는 지장이 없다.
              }
              if (!mounted) return;
              context.go(Routes.login);
            },
            child: const Text('로그인하러 가기'),
          ),
        ],
      ),
    );
  }
}

class _SessionResetNotice extends StatelessWidget {
  const _SessionResetNotice();

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(DsSpace.s4),
      decoration: BoxDecoration(
        color: p.statusBgWarning,
        borderRadius: BorderRadius.circular(DsRadius.lg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: DsIcon(DsIcons.warning, size: 18, color: p.statusWarning),
          ),
          const SizedBox(width: DsSpace.s2),
          Expanded(
            child: Text(
              '바꾸고 나면 지금 로그인되어 있는 다른 기기가 모두 로그아웃돼요.\n'
              '아이패드에서 쓰고 계셨다면 거기서도 다시 로그인해 주셔야 해요.',
              style: dsTextStyle(DsType.body, p.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

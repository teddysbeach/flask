import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:onpar_design_system/onpar_design_system.dart';

import '../../core/app_error.dart';
import '../../core/env.dart';
import '../../core/routes.dart';
import '../../data/auth_repository.dart';
import '../../ui/widgets/feedback.dart';
import 'auth_form_fields.dart';

/// 무엇을 인증하는 중인가.
enum VerifyMode {
  /// 가입 직후 보낸 인증 메일을 기다리는 중.
  email,

  /// 휴대폰으로 받은 6자리 인증번호를 넣는 중.
  phone,
}

/// 라우터가 `GoRoute.extra` 로 넘기는 값.
/// 화면이 두 가지 일을 하니, 어느 쪽인지와 대상은 반드시 같이 온다.
class VerifyArgs {
  const VerifyArgs({required this.mode, required this.target, this.codeAlreadySent = true});

  final VerifyMode mode;

  /// 이메일 주소 또는 휴대폰 번호. 화면에 그대로 보여 준다 —
  /// 오타로 엉뚱한 곳에 보냈을 때 사용자가 알아채는 유일한 단서다.
  final String target;

  /// 휴대폰 인증번호가 이미 발송된 상태로 들어왔는지.
  final bool codeAlreadySent;
}

/// 이메일 인증 안내와 휴대폰 인증번호 입력을 한 화면에서 다룬다.
///
/// 인증에 성공하면 세션이 생기고, **이동은 라우터가 한다.**
class VerifyScreen extends ConsumerStatefulWidget {
  const VerifyScreen({
    super.key,
    required this.mode,
    required this.target,
    this.codeAlreadySent = true,
  });

  VerifyScreen.fromArgs(VerifyArgs args, {Key? key})
      : this(
          key: key,
          mode: args.mode,
          target: args.target,
          codeAlreadySent: args.codeAlreadySent,
        );

  final VerifyMode mode;
  final String target;
  final bool codeAlreadySent;

  /// 재전송 쿨다운. 짧게 두면 문자 요금과 스팸 신고가 같이 늘어난다.
  static const resendCooldown = Duration(seconds: 60);

  /// 인증번호 유효 시간. 서버(Supabase) 기본값과 맞춰 둔다.
  static const codeLifetime = Duration(minutes: 5);

  static const codeLength = 6;

  @override
  ConsumerState<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends ConsumerState<VerifyScreen> {
  final _code = TextEditingController();
  final _codeFocus = FocusNode();

  Timer? _ticker;
  int _secondsLeft = 0;
  String? _codeError;
  String? _formError;
  bool _verifying = false;

  bool get _isPhone => widget.mode == VerifyMode.phone;
  bool get _canResend => _secondsLeft == 0;

  @override
  void initState() {
    super.initState();
    if (_isPhone) {
      if (widget.codeAlreadySent) {
        _startCooldown();
      } else {
        // 아직 안 보냈다면 화면에 들어오자마자 한 번 보낸다.
        // 사용자가 버튼을 찾아 누르게 만들 이유가 없다.
        unawaited(_resend(silent: true));
      }
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _code.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _ticker?.cancel();
    setState(() => _secondsLeft = VerifyScreen.resendCooldown.inSeconds);
    _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _secondsLeft = _secondsLeft <= 1 ? 0 : _secondsLeft - 1);
      if (_secondsLeft == 0) t.cancel();
    });
  }

  Future<void> _resend({bool silent = false}) async {
    if (!_canResend && !silent) return;
    setState(() {
      _codeError = null;
      _formError = null;
    });
    try {
      await ref.read(authRepositoryProvider).sendPhoneOtp(widget.target);
      if (!mounted) return;
      _startCooldown();
      if (!silent) {
        AppFeedback.toast(context, '인증번호를 다시 보냈어요.');
      }
    } catch (e, st) {
      if (!mounted) return;
      final error = AppError.from(e, st);
      if (error.isCancelled) return;
      setState(() => _formError = error.message);
    }
  }

  Future<void> _verify() async {
    final code = _code.text.trim();
    if (code.length != VerifyScreen.codeLength) {
      setState(() => _codeError = '${VerifyScreen.codeLength}자리 숫자를 모두 넣어 주세요.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _verifying = true;
      _codeError = null;
      _formError = null;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .verifyPhoneOtp(phone: widget.target, token: code);
      // 성공하면 세션이 생긴다. 이동은 라우터가 한다.
    } catch (e, st) {
      if (!mounted) return;
      final error = AppError.from(e, st);
      if (error.isCancelled) return;
      setState(() {
        // 만료·오입력 모두 사용자가 고칠 수 있는 일이라 입력칸 아래에 붙인다.
        if (error.kind == AppErrorKind.validation) {
          _codeError = error.message;
        } else {
          _formError = error.message;
        }
      });
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    return UnsavedInputGuard(
      dirty: _isPhone && _code.text.isNotEmpty,
      message: '입력하던 인증번호가 사라져요. 나가시겠어요?',
      child: Scaffold(
        backgroundColor: p.surfaceBase,
        appBar: AppBar(title: Text(_isPhone ? '휴대폰 인증' : '이메일 인증')),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              DsSpace.s6,
              DsSpace.s4,
              DsSpace.s6,
              DsSpace.s6 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _isPhone ? _phoneBody(p) : _emailBody(p),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _emailBody(DsPalette p) => [
        _Header(
          icon: DsIcons.info,
          title: '인증 메일을 보냈어요',
          body: '${widget.target} 로 보냈어요.\n메일 속 링크를 누르면 인증이 끝나고 앱으로 돌아와요.',
        ),
        const SizedBox(height: DsSpace.s8),
        _Tips(
          title: '메일이 안 보이나요',
          items: const [
            '스팸함이나 프로모션함도 한 번 봐 주세요.',
            '주소가 맞는지 확인해 주세요. 오타가 있으면 다시 가입해 주셔야 해요.',
            '메일은 보통 1~2분 안에 도착해요.',
          ],
        ),
        AuthFormError(message: _formError),
        const SizedBox(height: DsSpace.s8),
        // TODO(auth): 인증 메일 재전송 API 가 아직 리포지터리에 없다.
        // `AuthRepository.resendEmailVerification` 이 생기면 여기에 쿨다운과 함께 붙인다.
        OutlinedButton(
          onPressed: () => context.go(Routes.login),
          child: const Text('로그인 화면으로'),
        ),
        const SizedBox(height: DsSpace.s4),
        Text(
          '계속 안 오면 ${Env.supportEmail} 로 알려 주세요.',
          textAlign: TextAlign.center,
          style: dsTextStyle(DsType.caption, p.textTertiary),
        ),
      ];

  List<Widget> _phoneBody(DsPalette p) => [
        _Header(
          icon: DsIcons.info,
          title: '인증번호를 보냈어요',
          body: '${widget.target} 로 ${VerifyScreen.codeLength}자리 숫자를 보냈어요.',
        ),
        const SizedBox(height: DsSpace.s8),
        AuthFieldShell(
          label: '인증번호',
          child: TextField(
            controller: _code,
            focusNode: _codeFocus,
            autofocus: true,
            enabled: !_verifying,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            maxLength: VerifyScreen.codeLength,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: dsTextStyle(DsType.h2, p.textPrimary).copyWith(letterSpacing: 8),
            onChanged: (v) {
              setState(() => _codeError = null);
              // 다 채우면 바로 확인한다 — 여섯 자리를 넣고 버튼을 또 찾게 하지 않는다.
              if (v.length == VerifyScreen.codeLength) unawaited(_verify());
            },
            onSubmitted: (_) => unawaited(_verify()),
            decoration: InputDecoration(
              hintText: '000000',
              counterText: '',
              error: authFieldError(context, _codeError),
            ),
          ),
        ),
        const SizedBox(height: DsSpace.s2),
        Text(
          '인증번호는 ${VerifyScreen.codeLifetime.inMinutes}분 동안 쓸 수 있어요. '
          '시간이 지나면 다시 받아 주세요.',
          style: dsTextStyle(DsType.caption, p.textSecondary),
        ),
        AuthFormError(message: _formError),
        const SizedBox(height: DsSpace.s6),
        OnceButton(
          enabled: !_verifying,
          onPressed: _verify,
          child: const Text('확인'),
        ),
        const SizedBox(height: DsSpace.s3),
        _ResendRow(
          secondsLeft: _secondsLeft,
          onResend: () => unawaited(_resend()),
        ),
      ];
}

class _Header extends StatelessWidget {
  const _Header({required this.icon, required this.title, required this.body});

  final List<String> icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(DsSpace.s3),
          decoration: BoxDecoration(color: p.brandPrimarySubtle, shape: BoxShape.circle),
          child: DsIcon(icon, size: 24, color: p.brandPrimary),
        ),
        const SizedBox(height: DsSpace.s4),
        Text(title, style: dsTextStyle(DsType.h2, p.textPrimary)),
        const SizedBox(height: DsSpace.s2),
        Text(body, style: dsTextStyle(DsType.bodyLg, p.textSecondary)),
      ],
    );
  }
}

class _Tips extends StatelessWidget {
  const _Tips({required this.title, required this.items});

  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(DsSpace.s4),
      decoration: BoxDecoration(
        color: p.surfaceSunken,
        borderRadius: BorderRadius.circular(DsRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: dsTextStyle(DsType.body, p.textPrimary).copyWith(fontWeight: FontWeight.w700)),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(top: DsSpace.s2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('· ', style: dsTextStyle(DsType.body, p.textTertiary)),
                  Expanded(child: Text(item, style: dsTextStyle(DsType.body, p.textSecondary))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 재전송 줄. 쿨다운 동안 버튼을 잠그고 **남은 초를 글자로** 보여 준다 —
/// 회색으로만 두면 사용자는 버튼이 고장 난 줄 안다.
class _ResendRow extends StatelessWidget {
  const _ResendRow({required this.secondsLeft, required this.onResend});

  final int secondsLeft;
  final VoidCallback onResend;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    final waiting = secondsLeft > 0;
    return Semantics(
      liveRegion: true,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Text(
              waiting ? '$secondsLeft초 뒤에 다시 보낼 수 있어요' : '문자가 안 왔나요?',
              style: dsTextStyle(DsType.body, p.textSecondary),
            ),
          ),
          const SizedBox(width: DsSpace.s1),
          TextButton(
            onPressed: waiting ? null : onResend,
            child: const Text('다시 보내기'),
          ),
        ],
      ),
    );
  }
}

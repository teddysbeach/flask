import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:onpar_design_system/onpar_design_system.dart';

import '../../core/app_error.dart';
import '../../core/connectivity.dart';
import '../../core/env.dart';
import '../../core/logger.dart';
import '../../core/routes.dart';
import '../../data/auth_repository.dart';
import '../../ui/states/app_state_views.dart';
import '../../ui/widgets/feedback.dart';
import 'auth_form_fields.dart';

/// 계정 찾기 = 비밀번호 재설정 메일 보내기.
///
/// **가입된 주소인지 알려주지 않는다.** "그런 계정 없어요" 는 친절해 보이지만,
/// 남의 이메일을 하나씩 넣어 보면 누가 이 서비스를 쓰는지 알아낼 수 있는 창구가 된다.
/// 그래서 보내기를 누른 뒤에는 언제나 같은 문구가 나온다.
///
/// 대신 여기서 진짜로 막히는 사람은 따로 있다 — 소셜로 가입해서 비밀번호가
/// 아예 없는 사람. 그 사람에게 메일을 아무리 보내도 오지 않으니 미리 알려준다.
class FindAccountScreen extends ConsumerStatefulWidget {
  const FindAccountScreen({super.key});

  @override
  ConsumerState<FindAccountScreen> createState() => _FindAccountScreenState();
}

class _FindAccountScreenState extends ConsumerState<FindAccountScreen> {
  final _email = TextEditingController();
  final _emailFocus = FocusNode();

  String? _emailError;
  String? _formError;
  bool _sent = false;

  @override
  void dispose() {
    _email.dispose();
    _emailFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final email = _email.text.trim();
    if (!looksLikeEmail(email)) {
      setState(() {
        _emailError = '이메일 주소를 다시 확인해 주세요.';
        _formError = null;
      });
      return;
    }

    // 오프라인은 보내기 전에 거른다. 끊긴 채로 "보냈어요" 라고 하면 거짓말이 되고,
    // 연결 상태는 계정이 있는지와 아무 상관이 없어서 알려줘도 새는 것이 없다.
    final net = ref.read(netStatusProvider).value;
    if (net == NetStatus.offline) {
      setState(() {
        _emailError = null;
        _formError = AppError.of(AppErrorKind.offline).message;
      });
      return;
    }

    setState(() {
      _emailError = null;
      _formError = null;
    });

    try {
      await ref.read(authRepositoryProvider).sendPasswordReset(email);
    } catch (e) {
      // 실패해도 화면은 성공과 똑같이 말한다. 원인은 로그에만 남긴다 —
      // 여기서 갈라지면 그 차이가 곧 "이 주소는 가입되어 있다" 는 신호가 된다.
      AppLogger.error('find account: reset mail failed', error: e);
    }

    if (!mounted) return;
    setState(() => _sent = true);
  }

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    final offline = ref.watch(netStatusProvider).value == NetStatus.offline;

    return UnsavedInputGuard(
      dirty: !_sent && _email.text.isNotEmpty,
      child: Scaffold(
        backgroundColor: p.surfaceBase,
        appBar: AppBar(title: const Text('계정 찾기')),
        body: SafeArea(
          child: Column(
            children: [
              if (offline) const OfflineBanner(),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    DsSpace.s6,
                    DsSpace.s4,
                    DsSpace.s6,
                    DsSpace.s6 + MediaQuery.viewInsetsOf(context).bottom,
                  ),
                  child: _sent ? _sentBody(p) : _formBody(p),
                ),
              ),
            ],
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
          Text('비밀번호를 새로 정할게요', style: dsTextStyle(DsType.h2, p.textPrimary)),
          const SizedBox(height: DsSpace.s2),
          Text(
            '가입할 때 쓰신 이메일 주소를 넣어 주세요. 비밀번호를 새로 정하는 링크를 보내 드려요.',
            style: dsTextStyle(DsType.body, p.textSecondary),
          ),
          const SizedBox(height: DsSpace.s8),
          EmailField(
            controller: _email,
            focusNode: _emailFocus,
            errorText: _emailError,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => unawaited(_submit()),
          ),
          AuthFormError(message: _formError),
          const SizedBox(height: DsSpace.s6),
          OnceButton(onPressed: _submit, child: const Text('메일 보내기')),
          const SizedBox(height: DsSpace.s8),
          const _SocialNotice(),
        ],
      ),
    );
  }

  Widget _sentBody(DsPalette p) {
    return Semantics(
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: DsSpace.s4),
          Align(
            child: Container(
              padding: const EdgeInsets.all(DsSpace.s4),
              decoration: BoxDecoration(color: p.statusBgSuccess, shape: BoxShape.circle),
              child: DsIcon(DsIcons.success, size: 28, color: p.statusSuccess),
            ),
          ),
          const SizedBox(height: DsSpace.s6),
          Text(
            '메일을 보냈다면 곧 도착해요',
            textAlign: TextAlign.center,
            style: dsTextStyle(DsType.h2, p.textPrimary),
          ),
          const SizedBox(height: DsSpace.s3),
          Text(
            '${_email.text.trim()} 앞으로 보냈어요.\n'
            '메일함에 없으면 스팸함도 한 번 봐 주세요. 링크는 잠시 뒤에 만료돼요.',
            textAlign: TextAlign.center,
            style: dsTextStyle(DsType.bodyLg, p.textSecondary),
          ),
          const SizedBox(height: DsSpace.s8),
          const _SocialNotice(),
          const SizedBox(height: DsSpace.s8),
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
        ],
      ),
    );
  }
}

/// 소셜로 가입한 사람에게는 비밀번호가 없다. 그 사실을 여기서 말해 주지 않으면
/// 오지 않는 메일을 계속 기다리게 된다.
class _SocialNotice extends StatelessWidget {
  const _SocialNotice();

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(DsSpace.s4),
      decoration: BoxDecoration(
        color: p.statusBgInfo,
        borderRadius: BorderRadius.circular(DsRadius.lg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: DsIcon(DsIcons.info, size: 18, color: p.statusInfo),
          ),
          const SizedBox(width: DsSpace.s2),
          Expanded(
            child: Text(
              'Apple 이나 Google 로 가입하셨다면 비밀번호가 따로 없어요.\n'
              '로그인 화면에서 그 버튼으로 들어와 주세요.',
              style: dsTextStyle(DsType.body, p.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

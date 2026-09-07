import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:onpar_design_system/onpar_design_system.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/app_error.dart';
import '../../core/env.dart';
import '../../core/logger.dart';
import '../../core/version_gate.dart';
import '../../data/app_config_repository.dart';
import '../../data/supabase.dart';
import '../../ui/widgets/feedback.dart';
import '../settings/settings_tile.dart';
import 'support_screen.dart';

/// 문의하기.
///
/// 앱에서 바로 접수하고(`submit-support-ticket`), **접수 번호를 보여준다.**
/// 보냈는지 아닌지 모르는 채로 답을 기다리게 하지 않는다.
///
/// 서버를 못 부르면 예전처럼 **메일 앱을 연다.** 폴백을 없애면 서버가 죽은 날
/// 사용자가 우리에게 닿을 길이 함께 사라진다 — 그날이야말로 문의가 몰리는 날이다.
/// 사진은 어느 쪽으로 보내도 자동으로 붙지 않는다. 그 사실도 미리 말한다.
class ContactScreen extends ConsumerStatefulWidget {
  const ContactScreen({super.key});

  @override
  ConsumerState<ContactScreen> createState() => _ContactScreenState();
}

/// 문의 유형. 라벨은 메일 제목에, **enum 이름은 서버 `support_tickets.topic` 으로** 간다.
/// 서버의 check 제약도 같은 목록이다 — 두 벌로 두면 분류가 조용히 어긋난다.
enum ContactTopic {
  payment('결제·환불'),
  generation('학습지 만들기'),
  annotation('필기'),
  review('복습 알림'),
  account('계정·로그인'),
  other('그 밖의 것');

  const ContactTopic(this.label);
  final String label;
}

class _ContactScreenState extends ConsumerState<ContactScreen> {
  final _message = TextEditingController();
  final _picker = ImagePicker();

  ContactTopic? _topic;
  XFile? _screenshot;
  bool _sending = false;

  /// 접수 번호. 채워지면 화면은 "접수됐어요" 로 바뀐다.
  String? _ticketId;

  static const _minLength = 10;

  /// 서버 응답을 기다리는 한계. 넘으면 메일 폴백으로 넘어간다 —
  /// 스피너를 오래 보여주면 사용자는 앱이 멈췄다고 생각하고 앱을 끈다.
  static const _timeout = Duration(seconds: 12);

  @override
  void initState() {
    super.initState();
    _message.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  /// 접수가 끝났으면 더 지킬 입력이 없다 — 나갈 때 붙잡지 않는다.
  bool get _dirty =>
      _ticketId == null &&
      (_message.text.trim().isNotEmpty || _topic != null || _screenshot != null);
  bool get _canSend => _topic != null && _message.text.trim().runes.length >= _minLength;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    final version = ref.watch(appInfoProvider).valueOrNull?.display ?? '알 수 없음';

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || !_dirty) return;
        final leave = await AppFeedback.confirm(
          context,
          title: '문의를 그만둘까요?',
          message: '적으신 내용은 저장되지 않아요.',
          confirmLabel: '그만두기',
          cancelLabel: '계속 쓰기',
        );
        if (leave && context.mounted) context.pop();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('문의하기')),
        body: SafeArea(
          child: _ticketId != null ? _received(p) : _form(p, version),
        ),
      ),
    );
  }

  /// 접수됐다. **번호를 보여준다** — 번호가 없으면 사용자는 보냈는지 아닌지 모른 채로 기다린다.
  Widget _received(DsPalette p) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(DsSpace.s6, DsSpace.s12, DsSpace.s6, DsSpace.s8),
      children: [
        Center(child: DsIcon(DsIcons.success, size: 36, color: p.statusSuccess)),
        const SizedBox(height: DsSpace.s4),
        Semantics(
          liveRegion: true,
          child: Text('문의가 접수됐어요',
              textAlign: TextAlign.center, style: dsTextStyle(DsType.h2, p.textPrimary)),
        ),
        const SizedBox(height: DsSpace.s3),
        Text('접수 번호 ${_receiptNumber(_ticketId!)}',
            textAlign: TextAlign.center, style: dsTextStyle(DsType.body, p.textSecondary)),
        const SizedBox(height: DsSpace.s2),
        Text(
          '평일에는 하루 안에 답을 드리려고 해요. 답은 가입하신 이메일로 갑니다.'
          '${_screenshot == null ? '' : '\n사진은 함께 전송되지 않았어요. 필요하면 답장에 붙여 주세요.'}',
          textAlign: TextAlign.center,
          style: dsTextStyle(DsType.caption, p.textTertiary),
        ),
        const SizedBox(height: DsSpace.s8),
        FilledButton(
          onPressed: () => context.pop(),
          child: const Text('닫기'),
        ),
      ],
    );
  }

  /// 접수 번호는 uuid 앞부분만. 전부 읽어 주면 아무도 못 옮겨 적는다.
  static String _receiptNumber(String id) {
    final flat = id.replaceAll('-', '');
    return flat.substring(0, flat.length < 8 ? flat.length : 8).toUpperCase();
  }

  Widget _form(DsPalette p, String version) {
    return ListView(
      // 키보드가 올라와도 버튼까지 스크롤할 수 있어야 한다.
      padding: EdgeInsets.fromLTRB(
        DsSpace.s4,
        DsSpace.s4,
        DsSpace.s4,
        DsSpace.s12 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      children: [
        Text('어떤 일인가요?', style: dsTextStyle(DsType.h3, p.textPrimary)),
        const SizedBox(height: DsSpace.s3),
        Wrap(
          spacing: DsSpace.s2,
          runSpacing: DsSpace.s2,
          children: [
            for (final t in ContactTopic.values)
              ChoiceChip(
                label: Text(t.label),
                selected: _topic == t,
                // 선택 여부는 스크린리더가 selected 로 읽는다 — 색에만 기대지 않는다.
                onSelected: (_) => setState(() => _topic = t),
                padding: const EdgeInsets.symmetric(
                  horizontal: DsSpace.s3,
                  vertical: DsSpace.s2,
                ),
              ),
          ],
        ),
        const SizedBox(height: DsSpace.s6),
        Text('무슨 일이 있었나요?', style: dsTextStyle(DsType.h3, p.textPrimary)),
        const SizedBox(height: DsSpace.s2),
        Text(
          '언제, 무엇을 하다가 그렇게 됐는지 적어 주시면 훨씬 빨리 찾을 수 있어요.',
          style: dsTextStyle(DsType.caption, p.textTertiary),
        ),
        const SizedBox(height: DsSpace.s3),
        TextField(
          controller: _message,
          minLines: 6,
          maxLines: 12,
          maxLength: 2000,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          decoration: InputDecoration(
            hintText: '예) 어제 저녁에 "광합성" 으로 학습지를 만들었는데 계속 만드는 중이에요.',
            errorText: _message.text.isEmpty ||
                    _message.text.trim().runes.length >= _minLength
                ? null
                : '조금만 더 자세히 적어 주세요($_minLength자 이상).',
          ),
        ),
        const SizedBox(height: DsSpace.s4),
        _ScreenshotField(
          file: _screenshot,
          onPick: () => unawaited(_pickScreenshot()),
          onRemove: () => setState(() => _screenshot = null),
        ),
        const SizedBox(height: DsSpace.s6),
        NoticeBox(
          text: '앱 버전($version)과 기기 종류가 함께 접수돼요. 이메일·닉네임 같은 계정 정보는 넣지 않아요. '
              '보내지 못하면 메일 앱으로 이어서 보내드려요.'
              '${_screenshot == null ? '' : '\n\n사진은 자동으로 붙지 않아요. '
                  '답장에 직접 첨부해 주세요.'}',
        ),
        const SizedBox(height: DsSpace.s6),
        OnceButton(
          enabled: _canSend && !_sending,
          onPressed: _canSend ? () => _send(version) : null,
          child: const Text('문의 보내기'),
        ),
      ],
    );
  }

  Future<void> _send(String version) async {
    setState(() => _sending = true);
    try {
      final id = await _submit(version);
      if (!mounted) return;
      if (id != null) {
        setState(() => _ticketId = id);
        return;
      }
      // 서버에 못 넣었다. 여기서 멈추면 사용자는 보낸 줄 알고 답을 기다린다 —
      // 메일 앱을 열어 **적은 내용을 그대로 들고** 나가게 한다.
      AppFeedback.toast(context, '지금은 앱에서 접수가 안 돼요. 메일 앱으로 이어서 보내드릴게요.');
      await openSupportMail(
        context,
        version: version,
        category: _topic?.label,
        body: _message.text.trim(),
      );
    } on AppError catch (e) {
      // 사용자가 고칠 수 있는 실패(너무 잦음·형식)는 그대로 말한다. 메일로 밀지 않는다 —
      // 1분에 세 번을 넘긴 사람에게 메일 앱을 열어 주는 건 도배를 도와주는 것이다.
      if (mounted) AppFeedback.toast(context, e.message, danger: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// 서버 접수. 성공하면 접수 번호, **서버를 못 부르면 null**(→ 메일 폴백).
  ///
  /// 로그인 여부와 무관하게 부른다. 로그아웃 상태면 서버가 user_id 를 비워 두고 받는다 —
  /// 로그인이 안 돼서 문의하는 사람을 로그인 화면으로 돌려보내지 않는다.
  Future<String?> _submit(String version) async {
    if (!Env.isConfigured) return null;
    try {
      final res = await ref.read(supabaseProvider).functions.invoke(
        'submit-support-ticket',
        body: {
          // 유형은 라벨이 아니라 enum 이름으로 보낸다(서버의 닫힌 목록과 같은 값).
          'topic': _topic!.name,
          'body': _message.text.trim(),
          'app_version': version,
          'platform': ref.read(appPlatformProvider),
        },
      ).timeout(_timeout);
      final data = res.data;
      final id = data is Map ? data['ticket_id'] as String? : null;
      if (id == null || id.length < 8) {
        AppLogger.error('support ticket: 접수 번호가 없다', error: res.status);
        return null;
      }
      return id;
    } catch (e, st) {
      final err = mapSupabaseError(e, st);
      // 다시 눌러도 소용없는 실패만 화면이 말한다. 나머지는 조용히 메일 폴백으로.
      if (err.kind == AppErrorKind.rateLimited || err.kind == AppErrorKind.validation) throw err;
      AppLogger.error('support ticket submit failed (${err.kind.name})', error: e, stack: st);
      return null;
    }
  }

  Future<void> _pickScreenshot() async {
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 80,
        requestFullMetadata: false,
      );
      if (file == null || !mounted) return;
      setState(() => _screenshot = file);
    } on PlatformException catch (e) {
      if (!mounted) return;
      if (e.code == 'photo_access_denied') {
        final go = await AppFeedback.confirm(
          context,
          title: '사진 접근이 꺼져 있어요',
          message: '설정에서 ONPAR 의 사진 접근을 켜면 스크린샷을 붙일 수 있어요. 지금 설정을 열어 드릴까요?',
          confirmLabel: '설정 열기',
          cancelLabel: '나중에',
        );
        if (go) await openAppSettings();
        return;
      }
      AppLogger.error('screenshot pick failed', error: e);
      if (mounted) AppFeedback.toast(context, '사진을 불러오지 못했어요.', danger: true);
    } catch (e, st) {
      AppLogger.error('screenshot pick failed', error: e, stack: st);
      if (mounted) AppFeedback.toast(context, '사진을 불러오지 못했어요.', danger: true);
    }
  }
}

class _ScreenshotField extends StatelessWidget {
  const _ScreenshotField({required this.file, required this.onPick, required this.onRemove});

  final XFile? file;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (file != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(DsRadius.md),
            child: Image.file(
              File(file!.path),
              width: 64,
              height: 64,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 64,
                height: 64,
                color: p.surfaceSunken,
                alignment: Alignment.center,
                child: DsIcon(DsIcons.warning, size: 20, color: p.textTertiary),
              ),
            ),
          ),
          const SizedBox(width: DsSpace.s3),
          Expanded(
            child: Text('스크린샷 1장', style: dsTextStyle(DsType.body, p.textSecondary)),
          ),
          IconButton(
            onPressed: onRemove,
            tooltip: '스크린샷 빼기',
            icon: DsIcon(DsIcons.close, size: 20, color: p.textSecondary),
          ),
        ] else
          Expanded(
            child: OutlinedButton(
              onPressed: onPick,
              child: const Text('스크린샷 붙이기 (선택)'),
            ),
          ),
      ],
    );
  }
}

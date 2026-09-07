import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:onpar_design_system/onpar_design_system.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/logger.dart';
import '../../core/version_gate.dart';
import '../../ui/widgets/feedback.dart';
import '../settings/settings_tile.dart';
import 'support_screen.dart';

/// 문의하기.
///
/// 지금은 문의를 받아 줄 서버가 없어서 **메일로 보낸다.** 폼을 그대로 두고
/// 전송만 막아 두면 사용자는 보냈다고 믿고 답을 기다린다 — 그게 최악이다.
/// 그래서 메일 앱을 실제로 열고, 사진은 붙지 않는다는 것도 미리 말한다.
class ContactScreen extends ConsumerStatefulWidget {
  const ContactScreen({super.key});

  @override
  ConsumerState<ContactScreen> createState() => _ContactScreenState();
}

/// 문의 유형. 값이 그대로 메일 제목에 들어간다.
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

  static const _minLength = 10;

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

  bool get _dirty => _message.text.trim().isNotEmpty || _topic != null || _screenshot != null;
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
          child: ListView(
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
                text: '메일 앱으로 보내드려요. 제목에 앱 버전($version)과 기기 종류가 미리 들어가요. '
                    '계정 정보는 넣지 않아요.'
                    '${_screenshot == null ? '' : '\n\n사진은 메일에 자동으로 붙지 않아요. '
                        '메일 앱에서 직접 첨부해 주세요.'}',
              ),
              const SizedBox(height: DsSpace.s6),
              OnceButton(
                enabled: _canSend && !_sending,
                onPressed: _canSend ? () => _send(version) : null,
                child: const Text('메일 앱으로 보내기'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _send(String version) async {
    setState(() => _sending = true);
    try {
      // TODO(server): support_tickets 테이블 + `submit-support-ticket` Edge Function 이 생기면
      //   여기서 바로 보내고(스크린샷은 Storage 에 올린 뒤 경로만 전달) 접수 번호를 보여준다.
      //   메일은 그때도 남긴다 — 서버가 죽었을 때 사용자가 우리에게 닿을 마지막 길이다.
      await openSupportMail(
        context,
        version: version,
        category: _topic?.label,
        body: _message.text.trim(),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
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

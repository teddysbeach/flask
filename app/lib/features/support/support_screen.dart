import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:onpar_design_system/onpar_design_system.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/env.dart';
import '../../core/logger.dart';
import '../../core/routes.dart';
import '../../data/supabase.dart';
import '../../core/version_gate.dart';
import '../../ui/widgets/feedback.dart';
import '../settings/settings_tile.dart';
import 'support_mail.dart';

/// 고객센터. 답을 스스로 찾는 길(FAQ)을 먼저 두고, 그다음 사람에게 닿는 길을 둔다.
class SupportScreen extends ConsumerWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = DsTheme.of(context);
    final info = ref.watch(appInfoProvider);
    final version = info.valueOrNull?.display ?? '알 수 없음';
    final signedIn = ref.watch(currentUserProvider) != null;

    return Scaffold(
      appBar: AppBar(title: const Text('고객센터')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: DsSpace.s12),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(DsSpace.s4, DsSpace.s6, DsSpace.s4, 0),
              child: Text(
                '무엇을 도와드릴까요?',
                style: dsTextStyle(DsType.h2, p.textPrimary),
              ),
            ),
            SettingsSection(
              children: [
                SettingsTile(
                  label: '자주 묻는 질문',
                  description: '충전, 필기, 복습 알림에 대한 답이 있어요',
                  icon: DsIcons.glossary,
                  onTap: () => context.push(Routes.faq),
                ),
                SettingsTile(
                  label: '문의하기',
                  description: '앱에서 바로 남기기',
                  icon: DsIcons.guide,
                  onTap: () => context.push(Routes.contact),
                ),
                // 로그인했을 때만. 로그아웃 상태에서 보낸 문의는 계정에 안 붙어서
                // 여기 나올 것이 없다 — 빈 화면으로 보내는 길을 만들지 않는다.
                if (signedIn)
                  SettingsTile(
                    label: '내 문의',
                    description: '보낸 문의와 받은 답',
                    icon: DsIcons.glossary,
                    onTap: () => context.push(Routes.tickets),
                  ),
                SettingsTile(
                  label: '이메일로 문의하기',
                  description: Env.supportEmail,
                  icon: DsIcons.info,
                  onTap: () => unawaited(openSupportMail(context, version: version)),
                ),
              ],
            ),
            SettingsSection(
              title: '약관과 정책',
              children: [
                SettingsTile(
                  label: '이용약관',
                  icon: DsIcons.guide,
                  onTap: () => context.push(Routes.terms),
                ),
                SettingsTile(
                  label: '개인정보처리방침',
                  icon: DsIcons.guide,
                  onTap: () => context.push(Routes.privacy),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(DsSpace.s6),
              child: Text(
                '평일에 보내주시면 하루 안에 답을 드리려고 해요. 주말과 공휴일은 조금 늦어질 수 있어요.',
                textAlign: TextAlign.center,
                style: dsTextStyle(DsType.caption, p.textTertiary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 메일 앱 열기. 문의 화면과 고객센터가 같이 쓴다.
///
/// 메일 앱이 없는 기기가 있다(회사 관리 기기, 메일 앱을 지운 사람). 그때 아무 일도
/// 안 일어나면 사용자는 앱이 고장 났다고 생각한다 — 그래서 주소를 대신 보여준다.
Future<void> openSupportMail(
  BuildContext context, {
  required String version,
  String? category,
  String? body,
}) async {
  final uri = SupportMail.build(
    email: Env.supportEmail,
    version: version,
    platform: SupportMail.platformLabel(),
    category: category,
    body: body,
  );
  try {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (ok || !context.mounted) return;
  } catch (e, st) {
    AppLogger.error('mailto launch failed', error: e, stack: st);
    if (!context.mounted) return;
  }
  await AppFeedback.confirm(
    context,
    title: '메일 앱을 열지 못했어요',
    message: '${Env.supportEmail} 으로 보내주시면 저희가 확인할게요. '
        '앱 버전($version)도 같이 적어 주시면 더 빨라요.',
    confirmLabel: '알겠어요',
    cancelLabel: '닫기',
  );
}

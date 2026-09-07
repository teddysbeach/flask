import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:onpar_design_system/onpar_design_system.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_error.dart';
import '../../core/routes.dart';
import '../../data/data_export.dart';
import '../../data/supabase.dart';
import '../../ui/states/app_state_views.dart';
import '../../ui/widgets/feedback.dart';
import 'settings_tile.dart';

/// 계정. 로그인 수단과 데이터 내보내기, 탈퇴가 여기 모인다.
///
/// 이메일을 그대로 찍지 않는다 — 카페에서 화면을 보이며 문의하는 사람이 있고,
/// 스크린샷은 어디로든 간다. 본인 확인에는 앞 두 글자와 도메인이면 충분하다.
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = DsTheme.of(context);
    final user = ref.watch(currentUserProvider);

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('계정')),
        body: SafeArea(
          child: ErrorView(
            error: AppError.of(AppErrorKind.unauthorized),
            onSecondary: () => context.go(Routes.login),
            secondaryLabel: '로그인하러 가기',
          ),
        ),
      );
    }

    final providers = linkedProviders(user);
    final hasPassword = providers.contains('email');

    return Scaffold(
      appBar: AppBar(title: const Text('계정')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: DsSpace.s12),
          children: [
            SettingsSection(
              title: '로그인 정보',
              children: [
                SettingsTile(
                  label: '이메일',
                  value: maskEmail(user.email),
                  icon: DsIcons.profile,
                  showChevron: false,
                ),
                SettingsTile(
                  label: '연결된 로그인 수단',
                  value: providers.isEmpty
                      ? '확인할 수 없어요'
                      : providers.map(providerLabel).join(' · '),
                  icon: DsIcons.guide,
                  showChevron: false,
                ),
              ],
            ),
            if (hasPassword)
              SettingsSection(
                children: [
                  SettingsTile(
                    label: '비밀번호 변경',
                    icon: DsIcons.settings,
                    onTap: () => context.push(Routes.changePassword),
                  ),
                ],
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(DsSpace.s4, DsSpace.s6, DsSpace.s4, 0),
                child: NoticeBox(
                  text: '${providers.map(providerLabel).join(' · ')}(으)로 로그인하는 계정이라 '
                      '앱에서 관리할 비밀번호가 없어요. 비밀번호는 해당 서비스에서 바꿀 수 있어요.',
                ),
              ),
            SettingsSection(
              title: '내 데이터',
              children: [
                _ExportTile(),
              ],
            ),
            SettingsSection(
              title: '계정 정리',
              children: [
                SettingsTile(
                  label: '회원탈퇴',
                  description: '계정과 학습지가 모두 지워져요',
                  icon: DsIcons.danger,
                  danger: true,
                  onTap: () => context.push(Routes.withdraw),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(DsSpace.s6),
              child: Text(
                '계정에 문제가 있으면 고객센터로 알려 주세요. 저희가 확인해 드릴게요.',
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

/// `hong@onpar.app` → `ho***@onpar.app`. 도메인은 남긴다 — 어느 계정인지 본인은 알아야 한다.
String maskEmail(String? email) {
  if (email == null || email.isEmpty) return '없음';
  final at = email.indexOf('@');
  if (at <= 0) return '***';
  final head = email.substring(0, at);
  final domain = email.substring(at);
  final keep = head.length <= 2 ? head : head.substring(0, 2);
  return '$keep***$domain';
}

/// 연결된 로그인 수단. `identities` 가 비어 있는 세션이 있어서 appMetadata 도 같이 본다.
List<String> linkedProviders(User user) {
  final found = <String>{};
  for (final id in user.identities ?? const <UserIdentity>[]) {
    if (id.provider.isNotEmpty) found.add(id.provider);
  }
  final meta = user.appMetadata['providers'];
  if (meta is List) {
    for (final v in meta) {
      if (v is String && v.isNotEmpty) found.add(v);
    }
  }
  final single = user.appMetadata['provider'];
  if (single is String && single.isNotEmpty) found.add(single);
  const order = ['apple', 'google', 'email', 'phone'];
  int rank(String v) {
    final i = order.indexOf(v);
    return i < 0 ? order.length : i;
  }

  return found.toList()..sort((a, b) => rank(a).compareTo(rank(b)));
}

String providerLabel(String provider) => switch (provider) {
      'apple' => 'Apple',
      'google' => 'Google',
      'email' => '이메일',
      'phone' => '휴대폰',
      _ => provider,
    };

/// 내 데이터 내보내기.
///
/// 지우는 길(회원탈퇴)만 있고 **가져가는 길**이 없었다 — 지우기 전에 자기 것을 챙길
/// 방법이 없다는 뜻이다. 그래서 탈퇴 바로 위에 둔다. 여기가 사람이 그것을 찾는 자리다.
class _ExportTile extends ConsumerStatefulWidget {
  @override
  ConsumerState<_ExportTile> createState() => _ExportTileState();
}

class _ExportTileState extends ConsumerState<_ExportTile> {
  bool _busy = false;

  Future<void> _run() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final file = await ref.read(dataExportProvider).writeFile();
      if (!mounted) return;
      // 어디로 보낼지는 사용자가 고른다 — 메일·파일 앱·클라우드. 우리가 정할 일이 아니다.
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/json')],
        subject: 'ONPAR 내 데이터',
      );
    } on AppError catch (e) {
      if (mounted) AppFeedback.toast(context, e.message, danger: true);
    } catch (e, st) {
      if (mounted) AppFeedback.toast(context, AppError.from(e, st).message, danger: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SettingsTile(
        label: '내 데이터 내보내기',
        description: _busy ? '만드는 중이에요' : '학습지·답·복습 기록·결제 내역을 파일로',
        icon: DsIcons.library,
        enabled: !_busy,
        onTap: () => unawaited(_run()),
      );
}

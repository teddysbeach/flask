import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:onpar_design_system/onpar_design_system.dart';

import '../../core/app_error.dart';
import '../../core/connectivity.dart';
import '../../core/routes.dart';
import '../../core/version_gate.dart';
import '../../data/auth_repository.dart';
import '../../data/profile_repository.dart';
import '../../ui/states/app_state_views.dart';
import '../../ui/widgets/feedback.dart';
import 'settings_tile.dart';
import 'theme_controller.dart';

/// 설정. 사용자가 "이 앱을 어떻게 그만두는가" 까지 찾을 수 있어야 하는 화면이다.
///
/// 계정 삭제와 약관을 설정 안쪽 깊이 숨기면 심사에서 반려된다.
/// 그래서 계정 → 회원탈퇴 경로가 두 번 만에 닿는다.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = DsTheme.of(context);
    final offline = ref.watch(netStatusProvider).valueOrNull == NetStatus.offline;
    final themeMode = ref.watch(themeModeProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: SafeArea(
        child: Column(
          children: [
            if (offline) const OfflineBanner(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: DsSpace.s12),
                children: [
                  const _QuotaCard(),
                  SettingsSection(
                    title: '계정',
                    children: [
                      SettingsTile(
                        label: '계정',
                        icon: DsIcons.profile,
                        onTap: () => context.push(Routes.accountSettings),
                      ),
                      SettingsTile(
                        label: '프로필',
                        description: '닉네임과 프로필 사진',
                        icon: DsIcons.profile,
                        onTap: () => context.push(Routes.profile),
                      ),
                      SettingsTile(
                        label: '알림',
                        description: '복습 알림 시간',
                        icon: DsIcons.review,
                        onTap: () => context.push(Routes.notificationSettings),
                      ),
                    ],
                  ),
                  SettingsSection(
                    title: '학습지',
                    children: [
                      SettingsTile(
                        label: '남은 장수 · 충전',
                        icon: DsIcons.create,
                        onTap: () => context.push(Routes.paywall),
                      ),
                      SettingsTile(
                        label: '구매 내역',
                        icon: DsIcons.library,
                        onTap: () => context.push(Routes.purchases),
                      ),
                    ],
                  ),
                  SettingsSection(
                    title: '앱',
                    children: [
                      SettingsTile(
                        label: '화면',
                        value: themeModeLabel(themeMode),
                        icon: DsIcons.settings,
                        onTap: () => unawaited(_pickTheme(context, ref, themeMode)),
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
                      SettingsTile(
                        label: '오픈소스 라이선스',
                        icon: DsIcons.glossary,
                        onTap: () => context.push(Routes.licenses),
                      ),
                    ],
                  ),
                  SettingsSection(
                    title: '도움',
                    children: [
                      SettingsTile(
                        label: '학습 기록',
                        description: '연속 학습일과 떠올린 비율',
                        icon: DsIcons.review,
                        onTap: () => context.push(Routes.stats),
                      ),
                      SettingsTile(
                        label: '공지',
                        description: '점검과 중요한 변경',
                        icon: DsIcons.info,
                        onTap: () => context.push(Routes.notices),
                      ),
                      SettingsTile(
                        label: '고객센터',
                        description: '자주 묻는 질문과 문의하기',
                        icon: DsIcons.info,
                        onTap: () => context.push(Routes.support),
                      ),
                      const _VersionTile(),
                    ],
                  ),
                  SettingsSection(
                    children: [
                      SettingsTile(
                        label: '로그아웃',
                        icon: DsIcons.back,
                        showChevron: false,
                        onTap: () => unawaited(_signOut(context, ref)),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.all(DsSpace.s6),
                    child: Text(
                      '만든 학습지와 필기는 결제와 상관없이 계속 볼 수 있어요.',
                      textAlign: TextAlign.center,
                      style: dsTextStyle(DsType.caption, p.textTertiary),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickTheme(BuildContext context, WidgetRef ref, ThemeMode current) async {
    final picked = await AppFeedback.sheet<ThemeMode>(
      context,
      builder: (ctx) {
        final p = DsTheme.of(ctx);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(DsSpace.s4, DsSpace.s6, DsSpace.s4, DsSpace.s2),
                child: Text('화면', style: dsTextStyle(DsType.h3, p.textPrimary)),
              ),
              for (final mode in ThemeMode.values)
                SettingsTile(
                  label: themeModeLabel(mode),
                  showChevron: false,
                  // 선택 표시는 색이 아니라 아이콘이다.
                  trailing: mode == current
                      ? DsIcon(DsIcons.success, size: 20, color: p.brandText, semanticLabel: '선택됨')
                      : const SizedBox(width: 20, height: 20),
                  onTap: () => Navigator.of(ctx).pop(mode),
                ),
              const SizedBox(height: DsSpace.s4),
            ],
          ),
        );
      },
    );
    if (picked == null) return;
    await ref.read(themeModeProvider.notifier).set(picked);
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final ok = await AppFeedback.confirm(
      context,
      title: '로그아웃할까요?',
      message: '만든 학습지와 필기는 그대로 남아요. 다시 로그인하면 이어서 볼 수 있어요.',
      confirmLabel: '로그아웃',
    );
    if (!ok) return;
    try {
      await ref.read(authRepositoryProvider).signOut();
    } on AppError catch (e) {
      if (context.mounted) AppFeedback.toast(context, e.message, danger: true);
    }
    // 로그아웃 뒤 화면 이동과 로컬 정리는 라우터가 authState 를 보고 한다.
  }
}

/// 남은 장수. 설정 맨 위에 둔다 — 사용자가 설정에 들어오는 이유 1위다.
class _QuotaCard extends ConsumerWidget {
  const _QuotaCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = DsTheme.of(context);
    final profile = ref.watch(profileProvider);

    return Container(
      margin: const EdgeInsets.fromLTRB(DsSpace.s4, DsSpace.s4, DsSpace.s4, 0),
      padding: const EdgeInsets.all(DsSpace.s4),
      decoration: BoxDecoration(
        color: p.brandPrimarySubtle,
        borderRadius: BorderRadius.circular(DsRadius.lg),
      ),
      child: dsAsync(
        profile,
        alignment: Alignment.center,
        travel: 8,
        loading: () => const Row(
          children: [
            Expanded(child: SkeletonBox(height: 22)),
            SizedBox(width: DsSpace.s4),
            SkeletonBox(height: 36, width: 84),
          ],
        ),
        error: (e, st) {
          final err = AppError.from(e, st);
          return Row(
            children: [
              Expanded(
                child: Text(
                  err.kind == AppErrorKind.offline
                      ? '오프라인이라 남은 장수를 못 읽었어요.'
                      : '남은 장수를 불러오지 못했어요.',
                  style: dsTextStyle(DsType.body, p.textPrimary),
                ),
              ),
              TextButton(
                onPressed: () => ref.invalidate(profileProvider),
                child: const Text('다시 시도'),
              ),
            ],
          );
        },
        data: (me) => Row(
          children: [
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('남은 학습지', style: dsTextStyle(DsType.caption, p.brandTextOnSubtle)),
                    const SizedBox(height: DsSpace.s1),
                    // 장수는 이 화면에서 유일하게 '바뀌는 숫자'다. 결제하고 돌아왔을 때
                    // 같은 자리에 다른 숫자가 그냥 앉아 있으면 늘어난 줄 모른다.
                    DsCounterText('${me.quotaRemaining}장',
                        style: dsTextStyle(DsType.h2, p.textPrimary)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: DsSpace.s3),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(96, 48)),
              onPressed: () => context.push(Routes.paywall),
              child: const Text('충전'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 앱 버전. 문의할 때 우리가 가장 먼저 묻는 값이라 눌러서 복사할 수 있게 둔다.
class _VersionTile extends ConsumerWidget {
  const _VersionTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(appInfoProvider);
    return SettingsTile(
      label: '앱 버전',
      icon: DsIcons.info,
      showChevron: false,
      value: info.when(
        loading: () => '확인 중',
        error: (_, __) => '확인할 수 없어요',
        data: (v) => v.display,
      ),
    );
  }
}

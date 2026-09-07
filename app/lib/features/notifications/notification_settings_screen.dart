import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:onpar_design_system/onpar_design_system.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/app_error.dart';
import '../../core/bootstrap.dart';
import '../../core/notifications.dart';
import '../../data/profile_repository.dart';
import '../../data/review_repository.dart';
import '../../domain/models.dart';
import '../../ui/states/app_state_views.dart';
import '../../ui/widgets/feedback.dart';
import 'notification_prefs.dart';
import 'notification_sync.dart';

/// 알림 설정.
///
/// 앱 안의 스위치와 OS 권한은 다른 것이다. **OS 가 꺼져 있으면 앱 스위치를 켜도 알림은 안 온다** —
/// 그 사실을 숨기면 사용자는 "알림이 안 와요"라고 생각하고 기능을 통째로 신뢰하지 않게 된다.
/// 그래서 권한 상태를 화면 위에 먼저 보여 주고 설정으로 가는 길을 준다.
class NotificationSettingsScreen extends ConsumerStatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  ConsumerState<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends ConsumerState<NotificationSettingsScreen>
    with WidgetsBindingObserver {
  NotificationPermission? _permission;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refreshPermission());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 설정에서 권한을 켜고 돌아오면 화면이 바로 그 사실을 반영해야 한다.
    if (state == AppLifecycleState.resumed) unawaited(_refreshPermission());
  }

  Future<void> _refreshPermission() async {
    final status = await ref.read(notificationServiceProvider).permissionStatus();
    if (mounted) setState(() => _permission = status);
  }

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    final prefsAsync = ref.watch(sharedPrefsProvider);
    final profileAsync = ref.watch(profileProvider);

    return Scaffold(
      backgroundColor: p.surfaceBase,
      appBar: AppBar(title: const Text('알림 설정')),
      body: SafeArea(
        child: prefsAsync.when(
          loading: () => const LoadingView(),
          error: (e, st) => ErrorView(
            error: AppError.from(e, st),
            onRetry: () => ref.invalidate(sharedPrefsProvider),
          ),
          data: (rawPrefs) => profileAsync.when(
            loading: () => const LoadingView(),
            error: (e, st) => ErrorView(
              error: AppError.from(e, st),
              onRetry: () => ref.invalidate(profileProvider),
            ),
            data: (profile) => _form(NotificationPrefs(rawPrefs), profile),
          ),
        ),
      ),
    );
  }

  Widget _form(NotificationPrefs prefs, Profile profile) {
    final p = DsTheme.of(context);
    final consent = ref.read(localFlagsProvider).consent;
    final marketing = prefs.marketingChoice ?? consent?.marketing ?? false;
    final blocked = _permission == NotificationPermission.blocked ||
        _permission == NotificationPermission.denied;

    return ListView(
      padding: const EdgeInsets.only(bottom: DsSpace.s8),
      children: [
        if (blocked) _PermissionNotice(onOpenSettings: _openSettings),
        _SwitchRow(
          title: '전체 알림',
          description: '이걸 끄면 아래 알림이 모두 멈춰요.',
          value: prefs.allEnabled,
          onChanged: _busy ? null : (v) => _setAll(v, prefs, profile),
        ),
        const Divider(height: 1),
        _SwitchRow(
          title: '복습 알림',
          description: '망각곡선에 맞춰 하루 최대 $kMaxReviewsPerDay개까지만 보내요.',
          value: prefs.allEnabled && prefs.reviewEnabled,
          onChanged: _busy || !prefs.allEnabled ? null : (v) => _setReview(v, prefs, profile),
        ),
        _HourRow(
          hour: clampReviewHour(profile.reviewHour),
          enabled: !_busy && prefs.reviewNotificationsOn,
          onTap: () => _pickHour(prefs, profile),
        ),
        const Divider(height: 1),
        _SwitchRow(
          title: '마케팅 정보 알림',
          description: '새 기능·혜택 소식을 보내 드려요. 안 받아도 복습 알림은 그대로 와요.',
          value: prefs.allEnabled && marketing,
          onChanged: _busy || !prefs.allEnabled ? null : (v) => _setMarketing(v, prefs, consent),
        ),
        if (consent != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(DsSpace.s4, 0, DsSpace.s4, DsSpace.s4),
            child: Text(
              '마케팅 수신 동의는 ${_dateLabel(consent.agreedAt)}에 기록했어요.',
              style: dsTextStyle(DsType.caption, p.textTertiary),
            ),
          ),
      ],
    );
  }

  static String _dateLabel(DateTime d) => '${d.year}년 ${d.month}월 ${d.day}일';

  Future<void> _openSettings() async {
    try {
      await openAppSettings();
    } catch (e, st) {
      if (mounted) AppFeedback.toast(context, AppError.from(e, st).message, danger: true);
    }
  }

  Future<void> _setAll(bool value, NotificationPrefs prefs, Profile profile) async {
    await prefs.setAllEnabled(value);
    if (value) await _askPermissionIfNeeded();
    if (mounted) setState(() {});
    await _sync(prefs, profile);
  }

  Future<void> _setReview(bool value, NotificationPrefs prefs, Profile profile) async {
    await prefs.setReviewEnabled(value);
    if (value) await _askPermissionIfNeeded();
    if (mounted) setState(() {});
    await _sync(prefs, profile);
  }

  /// 마케팅 스위치는 동의 이력과 한 몸이다. 스위치만 바꾸고 이력을 안 남기면
  /// 나중에 "언제 동의했는지"를 증명할 수 없다.
  Future<void> _setMarketing(bool value, NotificationPrefs prefs, ConsentRecord? consent) async {
    await prefs.setMarketingEnabled(value);
    final flags = ref.read(localFlagsProvider);
    await flags.setConsent(ConsentRecord(
      terms: consent?.terms ?? true,
      privacy: consent?.privacy ?? true,
      marketing: value,
      agreedAt: DateTime.now(),
      version: consent?.version ?? '1',
    ));
    if (value) await _askPermissionIfNeeded();
    if (!mounted) return;
    setState(() {});
    AppFeedback.toast(context, value ? '마케팅 정보 알림을 받기로 했어요.' : '마케팅 정보 알림을 끄었어요.');
  }

  Future<void> _askPermissionIfNeeded() async {
    final service = ref.read(notificationServiceProvider);
    if (await service.permissionStatus() == NotificationPermission.granted) {
      await _refreshPermission();
      return;
    }
    await service.requestPermission();
    await _refreshPermission();
    if (!mounted) return;
    if (_permission != NotificationPermission.granted) {
      AppFeedback.toast(context, '휴대폰 설정에서 알림을 켜 주셔야 알림을 보낼 수 있어요.');
    }
  }

  Future<void> _pickHour(NotificationPrefs prefs, Profile profile) async {
    final current = clampReviewHour(profile.reviewHour);
    final picked = await AppFeedback.sheet<int>(
      context,
      builder: (ctx) => _HourSheet(current: current),
    );
    if (picked == null || picked == profile.reviewHour) return;

    setState(() => _busy = true);
    try {
      await ref.read(profileRepositoryProvider).update(reviewHour: picked);
      ref.invalidate(profileProvider);
      // 서버가 준 프로필을 다시 기다리지 않고, 방금 고른 값으로 바로 다시 예약한다.
      await _sync(prefs, profile.copyWith(reviewHour: picked));
      if (mounted) AppFeedback.toast(context, '${_hourLabel(picked)}에 알려 드릴게요.');
    } on AppError catch (e) {
      if (mounted) AppFeedback.toast(context, e.message, danger: true);
    } catch (e, st) {
      if (mounted) AppFeedback.toast(context, AppError.from(e, st).message, danger: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 설정이 바뀔 때마다 예약을 통째로 다시 건다. 스위치와 실제 알림이 어긋나는 순간이 없어야 한다.
  Future<void> _sync(NotificationPrefs prefs, Profile profile) => syncReviewNotifications(
        service: ref.read(notificationServiceProvider),
        reviews: ref.read(reviewRepositoryProvider),
        prefs: prefs,
        profile: profile,
      );
}

String _hourLabel(int hour) {
  final period = hour < 12 ? '오전' : '오후';
  final shown = hour % 12 == 0 ? 12 : hour % 12;
  return '$period $shown시';
}

class _PermissionNotice extends StatelessWidget {
  const _PermissionNotice({required this.onOpenSettings});
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    return Semantics(
      liveRegion: true,
      child: Container(
        margin: const EdgeInsets.all(DsSpace.s4),
        padding: const EdgeInsets.all(DsSpace.s4),
        decoration: BoxDecoration(
          color: p.statusBgWarning,
          borderRadius: BorderRadius.circular(DsRadius.xl),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DsIcon(DsIcons.warning, size: 20, color: p.statusWarning, semanticLabel: '주의'),
                const SizedBox(width: DsSpace.s2),
                Expanded(
                  child: Text(
                    '휴대폰 설정에서 ONPAR 알림이 꺼져 있어요.\n여기 스위치를 켜도 알림이 오지 않아요.',
                    style: dsTextStyle(DsType.body, p.textPrimary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: DsSpace.s3),
            FilledButton(onPressed: onOpenSettings, child: const Text('설정 열기')),
          ],
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    return SwitchListTile.adaptive(
      value: value,
      onChanged: onChanged,
      contentPadding: const EdgeInsets.symmetric(horizontal: DsSpace.s4, vertical: DsSpace.s2),
      title: Text(title, style: dsTextStyle(DsType.bodyLg, p.textPrimary)),
      subtitle: Text(description, style: dsTextStyle(DsType.caption, p.textSecondary)),
      activeThumbColor: p.brandText,
    );
  }
}

class _HourRow extends StatelessWidget {
  const _HourRow({required this.hour, required this.enabled, required this.onTap});

  final int hour;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    return ListTile(
      enabled: enabled,
      onTap: enabled ? onTap : null,
      contentPadding: const EdgeInsets.symmetric(horizontal: DsSpace.s4, vertical: DsSpace.s2),
      title: Text('복습 알림 시각',
          style: dsTextStyle(DsType.bodyLg, enabled ? p.textPrimary : p.textDisabled)),
      subtitle: Text(
        '밤 $kQuietStartHour시부터 아침 $kQuietEndHour시까지는 보내지 않아요.',
        style: dsTextStyle(DsType.caption, p.textSecondary),
      ),
      trailing: Text(_hourLabel(hour),
          style: dsTextStyle(DsType.bodyLg, enabled ? p.brandText : p.textDisabled)),
    );
  }
}

class _HourSheet extends StatelessWidget {
  const _HourSheet({required this.current});
  final int current;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(DsSpace.s4),
            child: Text('복습 알림을 언제 받을까요?', style: dsTextStyle(DsType.h3, p.textPrimary)),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (var h = kEarliestReviewHour; h <= kLatestReviewHour; h++)
                  ListTile(
                    title: Text(_hourLabel(h), style: dsTextStyle(DsType.bodyLg, p.textPrimary)),
                    trailing: h == current
                        ? DsIcon(DsIcons.success,
                            size: 20, color: p.brandText, semanticLabel: '선택됨')
                        : null,
                    onTap: () => Navigator.of(context).pop(h),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

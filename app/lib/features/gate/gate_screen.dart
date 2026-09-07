import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:onpar_design_system/onpar_design_system.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/bootstrap.dart';
import '../../core/env.dart';
import '../../core/version_gate.dart';
import '../../ui/widgets/feedback.dart';

/// 관문 화면 — 점검 · 강제 업데이트 · 선택 업데이트.
///
/// 판정(`AppGate`)은 서버가 하고 라우터가 들고 온다. 이 화면은 그 판정을 그리기만 한다.
/// 여기서 다시 판정하면 서버가 점검을 풀어도 앱이 안 열리는 날이 온다.
class GateScreen extends ConsumerWidget {
  const GateScreen({super.key, required this.gate, this.onDismiss});

  final AppGate gate;

  /// 선택 업데이트에서 "나중에" 를 눌렀을 때. 라우터가 원래 가려던 곳으로 보낸다.
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final force = gate.decision == GateDecision.forceUpdate;
    return PopScope(
      // 강제 업데이트는 닫을 수 없다. 뒤로가기로 빠져나갈 수 있으면 막는 의미가 없다.
      canPop: !force,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(DsSpace.s6),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: switch (gate.decision) {
                  GateDecision.maintenance => _Maintenance(
                      gate: gate,
                      onRetry: () async => ref.invalidate(appGateProvider),
                    ),
                  GateDecision.forceUpdate => _Update(gate: gate, force: true),
                  GateDecision.optionalUpdate =>
                    _Update(gate: gate, force: false, onLater: onDismiss),
                  // 통과 판정이면 라우터가 곧 다른 곳으로 보낸다. 여기서 붙잡지 않는다.
                  GateDecision.ok => const _Passing(),
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Passing extends StatelessWidget {
  const _Passing();

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    return Semantics(
      liveRegion: true,
      label: '들어가는 중',
      child: Center(child: CircularProgressIndicator(color: p.brandText, strokeWidth: 3)),
    );
  }
}

class _GateBody extends StatelessWidget {
  const _GateBody({
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    required this.title,
    required this.body,
    required this.actions,
    this.footnote,
  });

  final List<String> icon;
  final Color iconColor;
  final Color iconBackground;
  final String title;
  final String body;
  final List<Widget> actions;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          child: Container(
            padding: const EdgeInsets.all(DsSpace.s4),
            decoration: BoxDecoration(color: iconBackground, shape: BoxShape.circle),
            child: DsIcon(icon, size: 28, color: iconColor),
          ),
        ),
        const SizedBox(height: DsSpace.s6),
        Text(title, textAlign: TextAlign.center, style: dsTextStyle(DsType.h2, p.textPrimary)),
        const SizedBox(height: DsSpace.s3),
        Text(body, textAlign: TextAlign.center, style: dsTextStyle(DsType.bodyLg, p.textSecondary)),
        const SizedBox(height: DsSpace.s8),
        ...actions,
        if (footnote != null) ...[
          const SizedBox(height: DsSpace.s6),
          Text(
            footnote!,
            textAlign: TextAlign.center,
            style: dsTextStyle(DsType.caption, p.textTertiary),
          ),
        ],
      ],
    );
  }
}

class _Maintenance extends StatelessWidget {
  const _Maintenance({required this.gate, required this.onRetry});

  final AppGate gate;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final until = gate.until;
    final when = until == null ? null : formatGateUntil(until);
    return _GateBody(
      icon: DsIcons.settings,
      iconColor: DsTheme.of(context).statusWarning,
      iconBackground: DsTheme.of(context).statusBgWarning,
      title: '지금은 점검 중이에요',
      // 서버가 준 안내가 있으면 그것을 쓰되, 없으면 시간을 지어내지 않는다.
      body: [
        gate.message ?? '더 안정적으로 쓰실 수 있도록 손보고 있어요.',
        if (when != null) '$when쯤 끝날 것 같아요.' else '끝나는 대로 바로 열어 드릴게요.',
      ].join('\n'),
      actions: [
        OnceButton(onPressed: onRetry, child: const Text('다시 확인하기')),
      ],
      footnote: '오래 걸린다면 ${Env.supportEmail} 로 알려 주세요.',
    );
  }
}

class _Update extends StatelessWidget {
  const _Update({required this.gate, required this.force, this.onLater});

  final AppGate gate;
  final bool force;
  final VoidCallback? onLater;

  Future<void> _openStore(BuildContext context) async {
    final url = gate.storeUrl;
    if (url == null || url.isEmpty) {
      if (context.mounted) {
        AppFeedback.toast(context, '스토어 주소를 아직 받지 못했어요. 잠시 뒤에 다시 시도해 주세요.', danger: true);
      }
      return;
    }
    final uri = Uri.tryParse(url);
    final opened = uri == null ? false : await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      AppFeedback.toast(context, '스토어를 열지 못했어요. 앱스토어에서 ONPAR 를 찾아 주세요.', danger: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    return _GateBody(
      icon: DsIcons.info,
      iconColor: p.brandText,
      iconBackground: p.brandPrimarySubtle,
      title: force ? '업데이트가 필요해요' : '새 버전이 나왔어요',
      body: gate.message ??
          (force
              ? '지금 버전으로는 학습지를 열 수 없어요. 스토어에서 업데이트하고 다시 들어와 주세요.'
              : '고친 것과 새로 생긴 것이 있어요. 지금 받으셔도 되고, 나중에 받으셔도 돼요.'),
      actions: [
        OnceButton(
          onPressed: () => _openStore(context),
          child: const Text('스토어로 가기'),
        ),
        if (!force && onLater != null) ...[
          const SizedBox(height: DsSpace.s2),
          TextButton(onPressed: onLater, child: const Text('나중에')),
        ],
      ],
      footnote: force ? null : '나중에 눌러도 설정에서 다시 받을 수 있어요.',
    );
  }
}

/// 점검 종료 예정 시각을 사람이 읽는 말로. 모르면 부르는 쪽이 아예 쓰지 않는다.
///
/// intl 의 로케일 데이터를 켜지 않아도 되게 손으로 만든다 —
/// 이 한 줄 때문에 앱 시작에 초기화 단계를 하나 더 두고 싶지는 않다.
String formatGateUntil(DateTime until, {DateTime? now}) {
  final t = until.toLocal();
  final base = (now ?? DateTime.now()).toLocal();
  final today = DateTime(base.year, base.month, base.day);
  final day = DateTime(t.year, t.month, t.day);
  final diff = day.difference(today).inDays;

  final ampm = t.hour < 12 ? '오전' : '오후';
  final hour12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final minute = t.minute == 0 ? '' : ' ${t.minute}분';

  final prefix = switch (diff) {
    0 => '오늘',
    1 => '내일',
    _ => '${t.month}월 ${t.day}일',
  };
  return '$prefix $ampm $hour12시$minute';
}

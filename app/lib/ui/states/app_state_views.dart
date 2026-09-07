import 'package:flutter/material.dart';
import 'package:onpar_design_system/onpar_design_system.dart';

import '../../core/app_error.dart';

/// 모든 화면이 쓰는 네 가지 얼굴: 로딩·빈 상태·오류·오프라인.
///
/// 화면마다 다르게 만들면 같은 오류가 화면마다 다른 말을 한다.
/// 여기 하나만 두면 문구·아이콘·재시도 동작이 앱 전체에서 같다.

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.label});
  final String? label;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    return Semantics(
      label: label ?? '불러오는 중',
      liveRegion: true,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: p.brandText, strokeWidth: 3),
            if (label != null) ...[
              const SizedBox(height: DsSpace.s4),
              Text(label!, style: dsTextStyle(DsType.body, p.textSecondary)),
            ],
          ],
        ),
      ),
    );
  }
}

/// 목록이 길어질 때 쓰는 뼈대. 로딩 스피너보다 체감 대기가 짧다.
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({super.key, this.height = 16, this.width, this.radius = DsRadius.md});
  final double height;
  final double? width;
  final double radius;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    // 접근성: 움직임을 줄이라고 설정한 사용자에게는 깜빡이지 않는다.
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Opacity(
          opacity: reduce ? 1 : 0.55 + _c.value * 0.35,
          child: Container(
            height: widget.height,
            width: widget.width,
            decoration: BoxDecoration(
              color: p.surfaceSunken,
              borderRadius: BorderRadius.circular(widget.radius),
            ),
          ),
        ),
      ),
    );
  }
}

class EmptyView extends StatelessWidget {
  const EmptyView({
    super.key,
    required this.title,
    this.description,
    this.actionLabel,
    this.onAction,
    this.icon,
  });

  final String title;
  final String? description;
  final String? actionLabel;
  final VoidCallback? onAction;
  final List<String>? icon;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DsSpace.s8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              DsIcon(icon!, size: 40, color: p.textTertiary),
              const SizedBox(height: DsSpace.s4),
            ],
            Text(title, textAlign: TextAlign.center, style: dsTextStyle(DsType.h3, p.textPrimary)),
            if (description != null) ...[
              const SizedBox(height: DsSpace.s2),
              Text(description!,
                  textAlign: TextAlign.center, style: dsTextStyle(DsType.body, p.textSecondary)),
            ],
            if (onAction != null && actionLabel != null) ...[
              const SizedBox(height: DsSpace.s6),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

/// 오류 화면. 언제나 다음 행동이 있어야 한다 — 재시도든, 로그인이든, 문의든.
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, this.onRetry, this.onSecondary, this.secondaryLabel});

  final AppError error;
  final VoidCallback? onRetry;
  final VoidCallback? onSecondary;
  final String? secondaryLabel;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    final isOffline = error.kind == AppErrorKind.offline;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DsSpace.s8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DsIcon(isOffline ? DsIcons.warning : DsIcons.info, size: 36, color: p.textTertiary),
            const SizedBox(height: DsSpace.s4),
            Text(
              error.message,
              textAlign: TextAlign.center,
              style: dsTextStyle(DsType.bodyLg, p.textPrimary),
            ),
            if (onRetry != null && error.retryable) ...[
              const SizedBox(height: DsSpace.s6),
              FilledButton(onPressed: onRetry, child: const Text('다시 시도')),
            ],
            if (onSecondary != null && secondaryLabel != null) ...[
              const SizedBox(height: DsSpace.s2),
              TextButton(onPressed: onSecondary, child: Text(secondaryLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

/// 화면 위에 얇게 뜨는 오프라인 배너. 내용을 가리지 않는다.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        color: p.statusBgWarning,
        padding: const EdgeInsets.symmetric(horizontal: DsSpace.s4, vertical: DsSpace.s2),
        child: Row(
          children: [
            DsIcon(DsIcons.warning, size: 16, color: p.statusWarning),
            const SizedBox(width: DsSpace.s2),
            Expanded(
              child: Text('오프라인이에요. 저장한 학습지는 계속 볼 수 있어요.',
                  style: dsTextStyle(DsType.caption, p.textPrimary)),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
      AnimationController(vsync: this, duration: DsMotion.slower * 2)..repeat(reverse: true);

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
          // 선형으로 깜빡이면 형광등이 된다. 곡선을 태우면 숨을 쉬는 것처럼 보인다.
          opacity: reduce ? 1 : 0.55 + DsCurve.standard.transform(_c.value) * 0.35,
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
    // 빈 화면은 앱에서 가장 자주 오해받는 화면이다 — 사용자는 "안 불러와졌나" 로 읽는다.
    // 위에서부터 차례로 놓이면 "이건 결과다" 로 읽힌다.
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DsSpace.s8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              DsFadeSlide(
                duration: DsMotion.slower,
                curve: DsCurve.emphasized,
                child: DsIcon(icon!, size: 40, color: p.textTertiary),
              ),
              const SizedBox(height: DsSpace.s4),
            ],
            DsFadeSlide(
              delay: dsStaggerDelay(1),
              child: Text(title,
                  textAlign: TextAlign.center, style: dsTextStyle(DsType.h3, p.textPrimary)),
            ),
            if (description != null) ...[
              const SizedBox(height: DsSpace.s2),
              DsFadeSlide(
                delay: dsStaggerDelay(2),
                child: Text(description!,
                    textAlign: TextAlign.center, style: dsTextStyle(DsType.body, p.textSecondary)),
              ),
            ],
            if (onAction != null && actionLabel != null) ...[
              const SizedBox(height: DsSpace.s6),
              DsFadeSlide(
                delay: dsStaggerDelay(3),
                child: FilledButton(onPressed: onAction, child: Text(actionLabel!)),
              ),
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
    // 오류는 조용히 들어온다. 튀어나오면 사용자는 자기가 뭘 잘못했다고 느낀다.
    return DsFadeSlide(
      duration: DsMotion.base,
      travel: 8,
      child: Center(
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
    // 배너는 위에서 끼어드는 것이라 위에서 내려온다. 아래에서 올라오면
    // 내용이 아니라 '알림이 하나 더 생긴 것' 처럼 보인다.
    return DsFadeSlide(
      from: DsFrom.above,
      duration: DsMotion.base,
      child: Semantics(
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
      ),
    );
  }
}

/// 비동기 상태를 그릴 때 **갈아 끼우지 않고 넘긴다.**
///
/// `AsyncValue.when` 을 그대로 쓰면 로딩 → 내용이 한 프레임에 바뀐다. 사용자에게는
/// 그것이 "빠르다" 가 아니라 "화면이 한 번 깜빡였다" 로 보인다. 특히 서버가 빠를 때 —
/// 뼈대가 30ms 떴다가 사라지는 것이 가장 어지럽다.
///
/// 세 상태에 각각 키를 달아 [DsSwitcher] 가 바뀐 것을 알아채게 한다. 키가 없으면
/// 로딩과 내용이 같은 위젯 종류일 때(둘 다 Column 인 경우가 많다) 전환이 그냥 안 일어난다.
Widget dsAsync<T>(
  AsyncValue<T> value, {
  required Widget Function(T data) data,
  required Widget Function() loading,
  required Widget Function(Object error, StackTrace stack) error,
  Duration duration = DsMotion.base,
  Alignment alignment = Alignment.topCenter,
  double travel = DsMotion.travel,
}) {
  final child = value.when(
    skipLoadingOnRefresh: true,
    loading: () => KeyedSubtree(key: const ValueKey('loading'), child: loading()),
    error: (e, st) => KeyedSubtree(key: const ValueKey('error'), child: error(e, st)),
    data: (v) => KeyedSubtree(key: const ValueKey('data'), child: data(v)),
  );
  return DsSwitcher(duration: duration, alignment: alignment, travel: travel, child: child);
}

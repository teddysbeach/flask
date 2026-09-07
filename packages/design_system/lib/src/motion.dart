import 'dart:async';

import 'package:flutter/material.dart';

import 'tokens/tokens.g.dart';

/// 움직임의 규칙.
///
/// 기준은 애플이다. 곡선과 시간은 `design/design_tokens.json` 에서 나오고
/// 학습지 HTML 도 같은 값을 쓴다 — 앱과 학습지가 다른 속도로 움직이면 다른 제품이 된다.
///
/// 이 파일이 지키는 것은 세 가지다.
///
///   1. **감속.** 들어오는 것은 빠르게 출발해 천천히 놓는다(easeOut 계열).
///      나가는 것은 기다리게 하지 않는다.
///   2. **동작 줄이기를 존중한다.** OS 에서 켜 두었으면 시간이 0 이 된다.
///      취향이 아니라 요청이고, 어떤 화면에서도 예외를 두지 않는다.
///   3. **움직여도 읽힌다.** 페이드는 [FadeTransition] 의 의미론 포함 옵션을 켜서
///      투명한 동안에도 스크린리더가 내용을 읽는다.

/// OS 의 "동작 줄이기". 켜져 있으면 이 파일의 모든 움직임이 즉시 끝난다.
bool dsReduceMotion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// 동작 줄이기를 반영한 시간. 위젯이 직접 [DsMotion] 을 쓰지 않고 이걸 쓴다.
Duration dsDuration(BuildContext context, Duration d) =>
    dsReduceMotion(context) ? Duration.zero : d;

/// 등장 방향. 값은 "어디에서 오는가" 다.
enum DsFrom {
  /// 아래에서 올라온다. 목록·본문·카드의 기본값 — 종이가 놓이는 방향이다.
  below,

  /// 위에서 내려온다. 배너·알림처럼 위에서 끼어드는 것.
  above,

  /// 움직이지 않고 밝아지기만 한다. 글만 있는 화면(약관·FAQ)은 이쪽이 조용하다.
  none,
}

/// 한 번 등장하는 것. 페이드 + 짧은 이동.
///
/// 이동 거리는 [DsMotion.travel] (12dp) 이다. 이보다 크면 '나타남'이 아니라 '이동'으로
/// 보이고, 눈이 그 궤적을 따라가느라 정작 내용을 늦게 읽는다.
class DsFadeSlide extends StatefulWidget {
  const DsFadeSlide({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = DsMotion.slow,
    this.curve = DsCurve.enter,
    this.from = DsFrom.below,
    this.travel = DsMotion.travel,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;
  final Curve curve;
  final DsFrom from;
  final double travel;

  @override
  State<DsFadeSlide> createState() => _DsFadeSlideState();
}

class _DsFadeSlideState extends State<DsFadeSlide> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _c.forward();
    } else {
      _timer = Timer(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 동작 줄이기: 애니메이션을 끝난 상태로 둔다. 숨기지 않는다 —
    // 움직임을 줄여 달라는 요청이지 내용을 빼 달라는 요청이 아니다.
    if (dsReduceMotion(context)) {
      if (_c.value != 1) _c.value = 1;
      return widget.child;
    }

    final curved = _c.drive(CurveTween(curve: widget.curve));
    final dy = switch (widget.from) {
      DsFrom.below => widget.travel,
      DsFrom.above => -widget.travel,
      DsFrom.none => 0.0,
    };

    return FadeTransition(
      opacity: curved,
      // 투명한 동안에도 읽힌다. 끄면 등장 중인 화면이 스크린리더에게 빈 화면이다.
      alwaysIncludeSemantics: true,
      child: dy == 0
          ? widget.child
          : AnimatedBuilder(
              animation: curved,
              builder: (_, child) => Transform.translate(
                offset: Offset(0, dy * (1 - curved.value)),
                child: child,
              ),
              child: widget.child,
            ),
    );
  }
}

/// 목록이 차례로 들어온다.
///
/// 시차는 [DsMotion.stagger] 다. 다만 **앞의 몇 개까지만** 준다 — 끝까지 주면
/// 스무 번째 항목은 0.8초 뒤에 나타나고, 그건 등장이 아니라 로딩으로 읽힌다.
Duration dsStaggerDelay(int index, {int cap = 6}) =>
    DsMotion.stagger * (index < cap ? index : cap);

/// 눌리는 것. 애플의 촉감은 물결이 아니라 **크기**다.
///
/// 손끝이 닿는 순간 3% 줄었다가 [DsCurve.spring] 으로 돌아온다. 되돌아올 때만
/// 살짝 넘기는 이유는, 그래야 '눌렸다 놓였다'가 한 동작으로 읽히기 때문이다.
///
/// 두 가지로 쓴다.
///   * `onTap` 을 주면 **탭을 여기서 받는다.** 그냥 눌리는 카드·타일용.
///   * `onTap` 없이 감싸면 **눌린 티만 낸다.** 안쪽 버튼이 탭과 접근성을 그대로 갖는다 —
///     버튼을 [IgnorePointer] 로 덮으면 스크린리더가 그 버튼을 누를 수 없게 된다.
class DsPressable extends StatefulWidget {
  const DsPressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.enabled = true,
    this.scale = DsMotion.pressScale,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool enabled;
  final double scale;

  @override
  State<DsPressable> createState() => _DsPressableState();
}

class _DsPressableState extends State<DsPressable> {
  bool _down = false;

  bool get _handlesTap => widget.onTap != null || widget.onLongPress != null;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final pressed = _down && widget.enabled && !dsReduceMotion(context);
    final child = AnimatedScale(
      scale: pressed ? widget.scale : 1,
      duration: dsDuration(context, _down ? DsMotion.fast : DsMotion.base),
      curve: _down ? DsCurve.standard : DsCurve.spring,
      child: widget.child,
    );

    if (!widget.enabled) return child;

    if (_handlesTap) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: child,
      );
    }

    // Listener 는 제스처 경기에 참여하지 않는다. 안쪽 버튼의 탭·스크롤·접근성이 그대로 산다.
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: child,
    );
  }
}

/// 내용이 바뀔 때 갈아 끼우지 않고 **넘긴다.**
///
/// 로딩 → 목록이 툭 바뀌면 사용자는 화면이 한 번 깜빡였다고 느낀다.
/// 들어오는 것은 [DsCurve.enter], 나가는 것은 [DsCurve.exit] 로 서로 다른 곡선을 쓴다.
class DsSwitcher extends StatelessWidget {
  const DsSwitcher({
    super.key,
    required this.child,
    this.duration = DsMotion.base,
    this.alignment = Alignment.topCenter,
    this.travel = DsMotion.travel,
  });

  final Widget child;
  final Duration duration;
  final Alignment alignment;
  final double travel;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: dsDuration(context, duration),
      reverseDuration: dsDuration(context, DsMotion.fast),
      switchInCurve: DsCurve.enter,
      switchOutCurve: DsCurve.exit,
      layoutBuilder: (current, previous) => Stack(
        alignment: alignment,
        children: [...previous, if (current != null) current],
      ),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        alwaysIncludeSemantics: true,
        child: travel == 0
            ? child
            : SlideTransition(
                position: animation.drive(
                  Tween(begin: Offset(0, travel / 100), end: Offset.zero),
                ),
                child: child,
              ),
      ),
      child: child,
    );
  }
}

/// 숫자가 바뀌는 자리. 장수·개수처럼 **값 자체가 소식**인 곳에 쓴다.
///
/// 같은 자리에서 글자만 바뀌면 사용자는 바뀐 줄 모른다. 위로 흘려 보내면 안다.
class DsCounterText extends StatelessWidget {
  const DsCounterText(this.value, {super.key, this.style, this.textAlign});

  final String value;
  final TextStyle? style;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return DsSwitcher(
      duration: DsMotion.base,
      alignment: Alignment.center,
      travel: 8,
      child: Text(value, key: ValueKey(value), style: style, textAlign: textAlign),
    );
  }
}

/// 화면이 밀려 들어온다.
///
/// iOS 의 push 를 따른다 — 새 화면이 오른쪽에서 들어오고, **이전 화면은 그보다
/// 느리게 왼쪽으로 밀린다**(시차). 두 장이 같은 속도로 움직이면 종이 한 장처럼 보이고,
/// 그러면 "어디에서 왔는지" 가 사라진다.
///
/// 되돌아갈 때는 같은 곡선이 거꾸로 흐른다. 감속 곡선을 뒤집으면 가속이 되므로
/// 뒤로 가기가 저절로 빨라진다 — 나가는 것은 기다리게 하지 않는다는 규칙 그대로다.
class DsPageTransitionsBuilder extends PageTransitionsBuilder {
  const DsPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T>? route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (dsReduceMotion(context)) {
      return FadeTransition(opacity: animation, alwaysIncludeSemantics: true, child: child);
    }

    final curve = CurveTween(curve: DsCurve.standard);
    final incoming = animation.drive(
      Tween(begin: const Offset(1, 0), end: Offset.zero).chain(curve),
    );
    // 0.2 는 '따라 움직이지만 같이 가지는 않는' 거리다. 1 을 주면 두 장이 붙어 다닌다.
    final outgoing = secondaryAnimation.drive(
      Tween(begin: Offset.zero, end: const Offset(-0.2, 0)).chain(curve),
    );

    return SlideTransition(
      position: outgoing,
      child: SlideTransition(position: incoming, child: child),
    );
  }
}

/// 아래에서 올라오는 화면(결제·안내처럼 "잠깐 얹히는" 것).
///
/// iOS 의 시트다. 밀려 들어오는 화면과 구분되어야 "이건 잠깐 보는 것" 으로 읽힌다.
class DsSheetTransitionsBuilder extends PageTransitionsBuilder {
  const DsSheetTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T>? route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (dsReduceMotion(context)) {
      return FadeTransition(opacity: animation, alwaysIncludeSemantics: true, child: child);
    }
    return SlideTransition(
      position: animation.drive(
        Tween(begin: const Offset(0, 1), end: Offset.zero)
            .chain(CurveTween(curve: DsCurve.standard)),
      ),
      child: child,
    );
  }
}

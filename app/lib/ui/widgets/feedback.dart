import 'package:flutter/material.dart';
import 'package:onpar_design_system/onpar_design_system.dart';

/// 사용자에게 말을 거는 표준 방법 네 가지.
///
/// 화면마다 SnackBar 를 직접 만들면 문구 톤과 지속 시간이 제각각이 된다.
/// 그리고 "실패는 언제나 우리 탓" 규칙을 여기서 한 번에 지킬 수 있다.
class AppFeedback {
  const AppFeedback._();

  static void toast(BuildContext context, String message, {bool danger = false}) {
    final p = DsTheme.of(context);
    final m = ScaffoldMessenger.maybeOf(context);
    if (m == null) return;
    m
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message, style: dsTextStyle(DsType.body, p.neutralPrimaryOnBase)),
          backgroundColor: danger ? p.statusDanger : p.neutralPrimaryBase,
          duration: const Duration(seconds: 3),
        ),
      );
  }

  /// 되돌릴 수 없는 행동에만 쓴다. 확인 창을 남발하면 사용자는 읽지 않고 누른다.
  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = '확인',
    String cancelLabel = '취소',
    bool destructive = false,
  }) async {
    final p = DsTheme.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: dsTextStyle(DsType.h3, p.textPrimary)),
        content: Text(message, style: dsTextStyle(DsType.body, p.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(cancelLabel, style: dsTextStyle(DsType.body, p.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              confirmLabel,
              style: dsTextStyle(DsType.body, destructive ? p.statusDanger : p.brandText)
                  .copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  static Future<T?> sheet<T>(BuildContext context, {required WidgetBuilder builder}) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: builder(ctx),
      ),
    );
  }
}

/// 한 번만 눌리는 버튼. 연타로 같은 요청이 두 번 나가는 것을 위젯 층에서도 막는다.
/// (진짜 방어는 RequestGuard 지만, 두 겹이 맞다 — 쿼터를 깎는 버튼이 여기 있다.)
class OnceButton extends StatefulWidget {
  const OnceButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.enabled = true,
    this.style,
  });

  final Future<void> Function()? onPressed;
  final Widget child;
  final bool enabled;
  final ButtonStyle? style;

  @override
  State<OnceButton> createState() => _OnceButtonState();
}

class _OnceButtonState extends State<OnceButton> {
  bool _busy = false;

  Future<void> _run() async {
    if (_busy || widget.onPressed == null) return;
    setState(() => _busy = true);
    try {
      await widget.onPressed!();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    final on = widget.enabled && !_busy && widget.onPressed != null;
    return FilledButton(
      style: widget.style,
      onPressed: on ? _run : null,
      child: _busy
          ? SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2.4, color: p.brandOnPrimary),
            )
          : widget.child,
    );
  }
}

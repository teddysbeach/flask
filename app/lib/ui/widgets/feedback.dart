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

  /// 한 줄을 고쳐 받는 창. 취소하면 null 이다.
  ///
  /// 이름을 바꾸는 일은 화면을 새로 띄울 만큼 크지 않다. 그렇다고 목록에서 바로 편집하게
  /// 하면 잘못 눌러 고쳐 놓고 모른다 — 확인 버튼이 있는 창이 그 중간이다.
  static Future<String?> prompt(
    BuildContext context, {
    required String title,
    required String initial,
    String? hint,
    String confirmLabel = '저장',
    String cancelLabel = '취소',
    int maxLength = 120,
  }) async {
    final p = DsTheme.of(context);
    final controller = TextEditingController(text: initial);
    // 창을 열면 바로 고칠 수 있게 전체를 선택해 둔다.
    controller.selection = TextSelection(baseOffset: 0, extentOffset: initial.length);

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: dsTextStyle(DsType.h3, p.textPrimary)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: maxLength,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(hintText: hint),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(cancelLabel)),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    controller.dispose();
    final trimmed = result?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
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
    // 눌림은 크기로 알린다(애플의 촉감). 물결은 어디를 눌렀는지 알려 주지만
    // 손끝이 닿았다는 것을 알려 주지는 않는다.
    return DsPressable(
      enabled: on,
      child: FilledButton(
        style: widget.style,
        onPressed: on ? _run : null,
        // 글자 ↔ 스피너가 툭 바뀌면 버튼이 한 번 깜빡인 것처럼 보인다.
        child: DsSwitcher(
          duration: DsMotion.fast,
          alignment: Alignment.center,
          travel: 0,
          child: _busy
              ? SizedBox(
                  key: const ValueKey('busy'),
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.4, color: p.brandOnPrimary),
                )
              : KeyedSubtree(key: const ValueKey('label'), child: widget.child),
        ),
      ),
    );
  }
}

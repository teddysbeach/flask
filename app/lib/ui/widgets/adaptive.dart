import 'package:flutter/material.dart';
import 'package:onpar_design_system/onpar_design_system.dart';

/// 화면 크기 대응. ONPAR 은 아이패드가 1순위지만 폰에서도 열린다.
///
/// 브레이크포인트를 화면마다 적으면 반드시 갈라진다.
enum ScreenSize { compact, medium, expanded }

ScreenSize screenSizeOf(BuildContext context) {
  final w = MediaQuery.sizeOf(context).width;
  if (w < 600) return ScreenSize.compact;   // 폰
  if (w < 900) return ScreenSize.medium;    // 작은 태블릿 · 분할 화면
  return ScreenSize.expanded;               // 아이패드 전체 화면
}

/// 본문 최대 폭. 넓은 화면에서 글줄이 끝까지 늘어지면 읽기가 어렵다.
class ReadableWidth extends StatelessWidget {
  const ReadableWidth({super.key, required this.child, this.maxWidth = 640});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      );
}

/// 키보드가 올라와도 내용이 가려지지 않는 폼 화면의 기본 골격.
///
/// `resizeToAvoidBottomInset` 만 믿으면 작은 화면에서 버튼이 잘린다.
class FormScaffold extends StatelessWidget {
  const FormScaffold({
    super.key,
    required this.child,
    this.title,
    this.actions,
    this.bottom,
    this.leading,
  });

  final Widget child;
  final String? title;
  final List<Widget>? actions;

  /// 화면 아래에 고정할 것(주요 버튼). 키보드 위로 밀려 올라간다.
  final Widget? bottom;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    return Scaffold(
      backgroundColor: p.surfaceBase,
      appBar: title == null
          ? null
          : AppBar(title: Text(title!), actions: actions, leading: leading),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                // 키보드를 내리려고 빈 곳을 눌렀을 때 반응하도록
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.symmetric(
                  horizontal: DsSpace.s4,
                  vertical: DsSpace.s6,
                ),
                child: ReadableWidth(child: child),
              ),
            ),
            if (bottom != null)
              Padding(
                padding: EdgeInsets.only(
                  left: DsSpace.s4,
                  right: DsSpace.s4,
                  top: DsSpace.s2,
                  bottom: DsSpace.s4 + MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: ReadableWidth(child: bottom!),
              ),
          ],
        ),
      ),
    );
  }
}

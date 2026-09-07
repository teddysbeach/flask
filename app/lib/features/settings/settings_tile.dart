/// 설정·계정·고객지원 화면이 공유하는 목록 부품.
///
/// 화면마다 ListTile 을 직접 그리면 높이와 여백이 조금씩 어긋나고,
/// 무엇보다 터치 영역 48dp 를 한 군데서 놓치게 된다. 그래서 여기 하나만 둔다.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:onpar_design_system/onpar_design_system.dart';

/// 오른쪽 꺾쇠. `DsIcons.back`(왼쪽 꺾쇠)을 뒤집어 쓴다 —
/// 디자인 시스템에 없는 아이콘을 새로 그려 넣으면 그때부터 두 벌이 된다.
class ChevronRight extends StatelessWidget {
  const ChevronRight({super.key, this.color});
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    return Transform.rotate(
      angle: math.pi,
      child: DsIcon(DsIcons.back, size: 18, color: color ?? p.textTertiary),
    );
  }
}

/// 설정 목록 한 줄.
///
/// [value] 는 오른쪽에 붙는 현재 값(테마 이름, 앱 버전 …).
/// [danger] 는 색만 바꾸지 않는다 — 스크린리더에도 위험하다고 알린다.
class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.label,
    this.value,
    this.description,
    this.icon,
    this.onTap,
    this.trailing,
    this.danger = false,
    this.showChevron = true,
    this.enabled = true,
  });

  final String label;
  final String? value;
  final String? description;
  final List<String>? icon;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool danger;
  final bool showChevron;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    final on = enabled && onTap != null;
    final labelColor = danger
        ? p.statusDanger
        : enabled
            ? p.textPrimary
            : p.textDisabled;

    return Semantics(
      button: onTap != null,
      enabled: on,
      // 색이 빨갛다는 것은 스크린리더에 전달되지 않는다. 말로 붙여 준다.
      label: danger ? '$label. 되돌릴 수 없어요' : null,
      value: value,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: on ? onTap : null,
          child: ConstrainedBox(
            // 터치 영역 최소 48dp. 글꼴이 커지면 아래로 늘어난다.
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: DsSpace.s4,
                vertical: DsSpace.s3,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    DsIcon(icon!, size: 20, color: danger ? p.statusDanger : p.textSecondary),
                    const SizedBox(width: DsSpace.s3),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(label, style: dsTextStyle(DsType.bodyLg, labelColor)),
                        if (description != null) ...[
                          const SizedBox(height: DsSpace.s1),
                          Text(description!, style: dsTextStyle(DsType.caption, p.textSecondary)),
                        ],
                      ],
                    ),
                  ),
                  if (value != null) ...[
                    const SizedBox(width: DsSpace.s3),
                    Flexible(
                      child: Text(
                        value!,
                        textAlign: TextAlign.end,
                        style: dsTextStyle(DsType.body, p.textSecondary),
                      ),
                    ),
                  ],
                  if (trailing != null) ...[
                    const SizedBox(width: DsSpace.s2),
                    trailing!,
                  ],
                  if (showChevron && onTap != null) ...[
                    const SizedBox(width: DsSpace.s2),
                    const ChevronRight(),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 제목이 붙은 카드 묶음.
class SettingsSection extends StatelessWidget {
  const SettingsSection({super.key, this.title, required this.children});

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(DsSpace.s4, DsSpace.s6, DsSpace.s4, DsSpace.s2),
            child: Text(title!, style: dsTextStyle(DsType.caption, p.textTertiary)),
          )
        else
          const SizedBox(height: DsSpace.s4),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: DsSpace.s4),
          decoration: BoxDecoration(
            color: p.surfaceRaised,
            borderRadius: BorderRadius.circular(DsRadius.lg),
            border: Border.all(color: p.borderSubtle),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) Divider(height: 1, thickness: 1, color: p.borderSubtle),
                children[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// 안내 상자. 색만으로 뜻을 전하지 않으려고 아이콘과 글을 함께 둔다.
class NoticeBox extends StatelessWidget {
  const NoticeBox({
    super.key,
    required this.text,
    this.tone = NoticeTone.info,
    this.title,
  });

  final String text;
  final String? title;
  final NoticeTone tone;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    final (bg, fg, icon, semantic) = switch (tone) {
      NoticeTone.info => (p.statusBgInfo, p.statusInfo, DsIcons.info, '안내'),
      NoticeTone.warning => (p.statusBgWarning, p.statusWarning, DsIcons.warning, '주의'),
      NoticeTone.danger => (p.statusBgDanger, p.statusDanger, DsIcons.danger, '경고'),
      NoticeTone.success => (p.statusBgSuccess, p.statusSuccess, DsIcons.success, '완료'),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(DsSpace.s4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(DsRadius.md),
        border: Border.all(color: fg.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DsIcon(icon, size: 18, color: fg, semanticLabel: semantic),
          const SizedBox(width: DsSpace.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(title!, style: dsTextStyle(DsType.body, p.textPrimary).copyWith(
                        fontWeight: FontWeight.w700,
                      )),
                  const SizedBox(height: DsSpace.s1),
                ],
                Text(text, style: dsTextStyle(DsType.body, p.textPrimary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum NoticeTone { info, warning, danger, success }

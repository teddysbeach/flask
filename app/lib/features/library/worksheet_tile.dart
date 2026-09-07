import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:onpar_design_system/onpar_design_system.dart';

import '../../core/routes.dart';
import '../../domain/models.dart';
import '../../ui/states/app_state_views.dart';
import '../create/create_progress_screen.dart';
import '../create/create_screen.dart';

/// 목록에 학습지 한 장을 그리는 방법. 홈과 서재가 같은 걸 쓴다 —
/// 두 벌로 두면 "만드는 중" 배지가 한쪽에만 생기는 일이 반드시 생긴다.
class WorksheetTile extends StatelessWidget {
  const WorksheetTile({
    super.key,
    required this.worksheet,
    required this.onTap,
    this.onRetry,
  });

  final WorksheetSummary worksheet;

  /// 상태에 따라 갈 곳이 다르다(뷰어 · 진행 화면). 판단은 화면이 한다.
  final VoidCallback onTap;

  /// 실패한 학습지의 "다시 만들기". 없으면 버튼이 안 나온다.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    final failed = worksheet.status == WorksheetStatus.failed;

    return Semantics(
      button: true,
      label: '${worksheet.displayTitle}, ${_statusLabel(worksheet.status)}',
      child: ExcludeSemantics(
        child: Material(
          color: p.surfaceRaised,
          borderRadius: BorderRadius.circular(DsRadius.lg),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(DsRadius.lg),
            child: Container(
              padding: const EdgeInsets.all(DsSpace.s4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(DsRadius.lg),
                border: Border.all(color: p.borderSubtle),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          worksheet.displayTitle,
                          style: dsTextStyle(DsType.bodyLg, p.textPrimary)
                              .copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: DsSpace.s2),
                      WorksheetStatusBadge(status: worksheet.status),
                    ],
                  ),
                  const SizedBox(height: DsSpace.s2),
                  Text(
                    _when(worksheet.createdAt),
                    style: dsTextStyle(DsType.caption, p.textTertiary),
                  ),
                  if (failed) ...[
                    const SizedBox(height: DsSpace.s3),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(DsSpace.s3),
                      decoration: BoxDecoration(
                        color: p.statusBgDanger,
                        borderRadius: BorderRadius.circular(DsRadius.md),
                      ),
                      child: Text(
                        worksheet.failureMessage,
                        style: dsTextStyle(DsType.caption, p.textPrimary),
                      ),
                    ),
                    if (onRetry != null) ...[
                      const SizedBox(height: DsSpace.s2),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(onPressed: onRetry, child: const Text('다시 만들기')),
                      ),
                    ],
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

/// 상태 배지. 색만으로 구분하지 않는다 — 아이콘·점·글자가 같이 간다.
class WorksheetStatusBadge extends StatelessWidget {
  const WorksheetStatusBadge({super.key, required this.status});

  final WorksheetStatus status;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    final (bg, fg) = switch (status) {
      WorksheetStatus.ready => (p.statusBgSuccess, p.statusSuccess),
      WorksheetStatus.failed => (p.statusBgDanger, p.statusDanger),
      _ => (p.statusBgInfo, p.statusInfo),
    };
    final busy = status == WorksheetStatus.queued || status == WorksheetStatus.generating;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: DsSpace.s2, vertical: DsSpace.s1),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(DsRadius.full)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy)
            SizedBox(
              width: 11,
              height: 11,
              child: CircularProgressIndicator(strokeWidth: 2, color: fg),
            )
          else
            DsIcon(
              status == WorksheetStatus.ready ? DsIcons.success : DsIcons.warning,
              size: 13,
              color: fg,
            ),
          const SizedBox(width: DsSpace.s1),
          Text(_statusLabel(status), style: dsTextStyle(DsType.caption, fg)),
        ],
      ),
    );
  }
}

String _statusLabel(WorksheetStatus s) => switch (s) {
      WorksheetStatus.queued => '기다리는 중',
      WorksheetStatus.generating => '만드는 중',
      WorksheetStatus.ready => '완성',
      WorksheetStatus.failed => '실패',
    };

/// 목록에서는 "언제" 가 몇 시 몇 분보다 중요하다.
String _when(DateTime at) {
  final d = DateTime.now().difference(at);
  if (d.inMinutes < 1) return '방금';
  if (d.inHours < 1) return '${d.inMinutes}분 전';
  if (d.inDays < 1) return '${d.inHours}시간 전';
  if (d.inDays < 7) return '${d.inDays}일 전';
  return '${at.year}.${at.month.toString().padLeft(2, '0')}.${at.day.toString().padLeft(2, '0')}';
}

/// 목록이 로딩 중일 때 보여줄 뼈대 한 장.
class WorksheetTileSkeleton extends StatelessWidget {
  const WorksheetTileSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(DsSpace.s4),
      decoration: BoxDecoration(
        color: p.surfaceRaised,
        borderRadius: BorderRadius.circular(DsRadius.lg),
        border: Border.all(color: p.borderSubtle),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(height: 18, width: 190),
          SizedBox(height: DsSpace.s3),
          SkeletonBox(height: 13, width: 72),
        ],
      ),
    );
  }
}

/// 학습지를 눌렀을 때 갈 곳. 상태마다 다르다 — 만드는 중인 학습지를 뷰어로 열면
/// 빈 화면이 뜬다. 홈과 서재가 이 규칙을 공유해야 두 곳이 다르게 굴지 않는다.
void openWorksheet(BuildContext context, WorksheetSummary w) {
  switch (w.status) {
    case WorksheetStatus.ready:
      context.push(Routes.worksheet(w.id));
    case WorksheetStatus.queued:
    case WorksheetStatus.generating:
      unawaited(Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => CreateProgressScreen(worksheetId: w.id),
      )));
    case WorksheetStatus.failed:
      // 실패한 학습지는 열 것이 없다. 같은 주제로 다시 만들 수 있게 입력을 채워 준다.
      unawaited(Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => CreateScreen(initialTopic: w.topic),
      )));
  }
}

import 'package:flutter/material.dart';
import 'package:onpar_design_system/onpar_design_system.dart';

import '../../domain/models.dart';

/// 날짜 묶음 하나.
class WorksheetGroup {
  const WorksheetGroup(this.label, this.items);
  final String label;
  final List<WorksheetSummary> items;
}

/// 학습지를 날짜로 묶는다. **순수 함수** — 규칙이 틀리면 목록이 통째로 이상해 보이는데,
/// 그건 화면을 띄워서 눈으로 잡기 어렵다.
///
/// 왜 묶는가: 시간순으로 쭉 늘어놓으면 스무 장쯤부터 "언제 만든 것인지" 가 사라진다.
/// 사람은 자기 학습지를 제목이 아니라 **그때 무엇을 하고 있었는지**로 기억한다.
///
/// 경계는 사람의 말로 잡는다. "3일 전" 은 날짜지만 "이번 주" 는 기억이다.
List<WorksheetGroup> groupWorksheetsByDate(
  List<WorksheetSummary> items, {
  DateTime? now,
}) {
  if (items.isEmpty) return const [];
  final today = _dateOnly(now ?? DateTime.now());

  final order = <String>[];
  final buckets = <String, List<WorksheetSummary>>{};
  for (final w in items) {
    final label = _labelFor(_dateOnly(w.createdAt), today);
    if (!buckets.containsKey(label)) {
      order.add(label);
      buckets[label] = [];
    }
    buckets[label]!.add(w);
  }
  // 목록은 이미 최신순이라 순서를 다시 정렬하지 않는다 —
  // 여기서 또 정렬하면 서버 순서와 화면 순서가 두 벌이 된다.
  return [for (final label in order) WorksheetGroup(label, buckets[label]!)];
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

String _labelFor(DateTime day, DateTime today) {
  final diff = today.difference(day).inDays;
  if (diff <= 0) return '오늘';
  if (diff == 1) return '어제';
  if (diff < 7) return '지난 7일';
  if (day.year == today.year && day.month == today.month) return '이번 달';
  if (day.year == today.year) return '${day.month}월';
  return '${day.year}년 ${day.month}월';
}

/// 날짜 묶음의 머리글. 목록 안에 섞이므로 카드처럼 보이면 안 된다 —
/// 얇은 글자 한 줄이 "여기서부터 다른 날" 을 말하는 가장 조용한 방법이다.
class DateGroupHeader extends StatelessWidget {
  const DateGroupHeader({super.key, required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(DsSpace.s1, DsSpace.s4, DsSpace.s1, DsSpace.s2),
      child: Semantics(
        header: true,
        label: '$label, $count장',
        child: ExcludeSemantics(
          child: Row(
            children: [
              Text(
                label,
                style: dsTextStyle(DsType.caption, p.textSecondary)
                    .copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: DsSpace.s2),
              Text('$count', style: dsTextStyle(DsType.caption, p.textTertiary)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 남은 장수. 예전에는 큰 카드였는데, 홈에 들어올 때마다 보기에는 크다.
/// 한 줄로 줄이고 대신 **0장일 때만** 눈에 띄게 한다 — 그때가 알아야 하는 순간이다.
class QuotaBar extends StatelessWidget {
  const QuotaBar({
    super.key,
    required this.remaining,
    required this.onCharge,
    this.loading = false,
  });

  final int? remaining;
  final VoidCallback onCharge;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    final empty = remaining == 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(DsSpace.s4, DsSpace.s3, DsSpace.s3, DsSpace.s3),
      decoration: BoxDecoration(
        color: empty ? p.brandPrimarySubtle : p.surfaceRaised,
        borderRadius: BorderRadius.circular(DsRadius.lg),
        border: Border.all(color: empty ? p.brandText : p.borderSubtle),
      ),
      child: Row(
        children: [
          Expanded(
            child: loading
                ? const SkeletonLine()
                : Semantics(
                    liveRegion: true,
                    label: remaining == null
                        ? '남은 학습지를 불러오지 못했어요'
                        : '남은 학습지 $remaining장',
                    child: ExcludeSemantics(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text('남은 학습지',
                              style: dsTextStyle(DsType.body, p.textSecondary)),
                          const SizedBox(width: DsSpace.s2),
                          DsCounterText(
                            remaining == null ? '—' : '$remaining장',
                            style: dsTextStyle(
                              DsType.bodyLg,
                              empty ? p.brandTextOnSubtle : p.textPrimary,
                            ).copyWith(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
          TextButton(
            onPressed: onCharge,
            child: Text(empty ? '충전하기' : '충전'),
          ),
        ],
      ),
    );
  }
}

/// 뼈대 한 줄. 남은 장수 자리처럼 높이가 정해진 곳에 쓴다.
class SkeletonLine extends StatelessWidget {
  const SkeletonLine({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox(
        height: 24,
        child: Align(alignment: Alignment.centerLeft, child: SizedBox(width: 140, height: 16)),
      );
}

/// 홈의 큰 카드 한 장. 색과 테두리만 다르고 나머지는 같다.
class HomeCard extends StatelessWidget {
  const HomeCard({
    super.key,
    required this.child,
    this.accent = false,
    this.onTap,
  });

  final Widget child;
  final bool accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    final body = AnimatedContainer(
      duration: dsDuration(context, DsMotion.base),
      curve: DsCurve.standard,
      padding: const EdgeInsets.all(DsSpace.s4),
      decoration: BoxDecoration(
        color: accent ? p.brandPrimarySubtle : p.surfaceRaised,
        borderRadius: BorderRadius.circular(DsRadius.lg),
        border: Border.all(color: accent ? p.brandText : p.borderSubtle),
      ),
      child: child,
    );
    if (onTap == null) return body;
    return DsPressable(
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(DsRadius.lg),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(DsRadius.lg),
          child: body,
        ),
      ),
    );
  }
}

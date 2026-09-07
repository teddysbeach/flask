import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:onpar_design_system/onpar_design_system.dart';

import '../../core/app_error.dart';
import '../../data/notice_repository.dart';
import '../../ui/states/app_state_views.dart';
import '../../ui/widgets/adaptive.dart';

/// 공지.
///
/// 이 화면이 없어서 그동안 공지 링크(딥링크·이메일)를 누르면 "없는 페이지" 에 떨어졌다.
/// **로그인 없이 열린다** — 점검 공지는 로그인이 안 될 때 가장 필요하다.
class NoticeListScreen extends ConsumerWidget {
  const NoticeListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = DsTheme.of(context);
    final notices = ref.watch(noticesProvider);

    return Scaffold(
      backgroundColor: p.surfaceBase,
      appBar: AppBar(title: const Text('공지')),
      body: SafeArea(
        child: RefreshIndicator(
          color: p.brandText,
          onRefresh: () async => ref.invalidate(noticesProvider),
          child: dsAsync(
            notices,
            loading: () => ListView(
              padding: const EdgeInsets.all(DsSpace.s4),
              children: const [
                SkeletonBox(height: 72),
                SizedBox(height: DsSpace.s2),
                SkeletonBox(height: 72),
              ],
            ),
            error: (e, st) => ErrorView(
              error: AppError.from(e, st),
              onRetry: () => ref.invalidate(noticesProvider),
            ),
            data: (items) {
              if (items.isEmpty) {
                return const _Scrollable(
                  child: EmptyView(
                    icon: DsIcons.info,
                    title: '아직 공지가 없어요',
                    description: '점검이나 중요한 변경이 있으면 여기에 올려 드릴게요.',
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(
                    DsSpace.s4, DsSpace.s4, DsSpace.s4, DsSpace.s12),
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: DsSpace.s2),
                itemBuilder: (context, i) => DsFadeSlide(
                  delay: dsStaggerDelay(i),
                  child: ReadableWidth(child: _NoticeCard(notice: items[i])),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// 당겨서 새로고침은 스크롤이 가능해야 동작한다. 빈 화면도 스크롤되게 감싼다.
class _Scrollable extends StatelessWidget {
  const _Scrollable({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (_, c) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: c.maxHeight),
            child: child,
          ),
        ),
      );
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.notice});
  final Notice notice;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(DsSpace.s4),
      decoration: BoxDecoration(
        color: p.surfaceRaised,
        borderRadius: BorderRadius.circular(DsRadius.lg),
        border: Border.all(color: notice.pinned ? p.brandText : p.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // 고정 표시는 색만으로 말하지 않는다 — 글자를 같이 둔다.
              if (notice.pinned) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: DsSpace.s2, vertical: DsSpace.s1),
                  decoration: BoxDecoration(
                    color: p.brandPrimarySubtle,
                    borderRadius: BorderRadius.circular(DsRadius.full),
                  ),
                  child: Text('중요',
                      style: dsTextStyle(DsType.caption, p.brandTextOnSubtle)
                          .copyWith(fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: DsSpace.s2),
              ],
              Expanded(
                child: Text(
                  notice.title,
                  style: dsTextStyle(DsType.bodyLg, p.textPrimary)
                      .copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: DsSpace.s2),
          Text(notice.body, style: dsTextStyle(DsType.body, p.textSecondary)),
          const SizedBox(height: DsSpace.s3),
          Text(_when(notice.publishedAt), style: dsTextStyle(DsType.caption, p.textTertiary)),
        ],
      ),
    );
  }
}

String _when(DateTime at) =>
    '${at.year}.${at.month.toString().padLeft(2, '0')}.${at.day.toString().padLeft(2, '0')}';

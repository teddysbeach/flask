import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:onpar_design_system/onpar_design_system.dart';

import '../../core/routes.dart';
import '../../domain/models.dart';
import '../../ui/states/app_state_views.dart';
import 'library_controller.dart';
import 'worksheet_tile.dart';

/// 만든 학습지가 전부 쌓이는 곳. 무한 스크롤이지만 요청은 한 번에 하나만 나간다.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  /// 바닥에서 480px 남았을 때 다음 페이지를 부른다.
  /// 중복 요청 방지는 컨트롤러가 한다 — 이 콜백은 스크롤 한 번에 수십 번 불린다.
  void _onScroll() {
    if (!_scroll.hasClients) return;
    final left = _scroll.position.maxScrollExtent - _scroll.position.pixels;
    if (left > 480) return;
    // 스크롤 중에는 기다릴 것이 없다. 결과는 state 로 온다.
    unawaited(ref.read(libraryControllerProvider.notifier).loadMore());
  }

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    final state = ref.watch(libraryControllerProvider);
    final controller = ref.read(libraryControllerProvider.notifier);
    final visible = state.visible;

    return Scaffold(
      backgroundColor: p.surfaceBase,
      appBar: AppBar(title: const Text('서재')),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            _FilterBar(
              value: state.filter,
              onChanged: controller.setFilter,
            ),
            Expanded(
              child: RefreshIndicator(
                color: p.brandPrimary,
                onRefresh: controller.refresh,
                child: _body(context, state, controller, visible),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    LibraryState state,
    LibraryController controller,
    List<WorksheetSummary> visible,
  ) {
    // 첫 페이지를 받는 중.
    if (state.loading) {
      return ListView.separated(
        padding: const EdgeInsets.all(DsSpace.s4),
        itemCount: 6,
        separatorBuilder: (_, __) => const SizedBox(height: DsSpace.s2),
        itemBuilder: (_, __) => const WorksheetTileSkeleton(),
      );
    }

    // 첫 페이지가 실패했다.
    if (state.error != null && state.items.isEmpty) {
      return _scrollable(
        ErrorView(error: state.error!, onRetry: controller.refresh),
      );
    }

    if (visible.isEmpty) {
      // 필터를 걸었는데 이번 페이지에 없을 뿐일 수 있다. 그럴 땐 더 불러올 길을 준다.
      final filtered = state.filter != LibraryFilter.all;
      if (filtered && !state.endReached) {
        return _scrollable(
          EmptyView(
            icon: DsIcons.library,
            title: '여기까지는 ${state.filter.label} 학습지가 없어요',
            description: '더 불러와서 찾아볼 수 있어요.',
            actionLabel: state.loadingMore ? '불러오는 중' : '더 불러오기',
            onAction: state.loadingMore ? null : controller.retryMore,
          ),
        );
      }
      return _scrollable(
        filtered
            ? EmptyView(
                icon: DsIcons.library,
                title: '${state.filter.label} 학습지가 없어요',
                actionLabel: '전체 보기',
                onAction: () => controller.setFilter(LibraryFilter.all),
              )
            : EmptyView(
                icon: DsIcons.create,
                title: '아직 학습지가 없어요',
                description: '배우고 싶은 걸 한 줄 적으면 6단계 학습지를 만들어 드려요.',
                actionLabel: '첫 학습지 만들기',
                onAction: () => context.push(Routes.create),
              ),
      );
    }

    return ListView.separated(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(DsSpace.s4, DsSpace.s4, DsSpace.s4, DsSpace.s8),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: visible.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: DsSpace.s2),
      itemBuilder: (context, i) {
        if (i == visible.length) return _Footer(state: state, controller: controller);
        final w = visible[i];
        return WorksheetTile(
          worksheet: w,
          onTap: () => openWorksheet(context, w),
          onRetry: () => openWorksheet(context, w),
        );
      },
    );
  }

  /// 당겨서 새로고침은 스크롤이 가능해야 동작한다. 빈 화면·오류 화면도 스크롤되게 감싼다.
  Widget _scrollable(Widget child) => LayoutBuilder(
        builder: (context, c) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: c.maxHeight),
            child: child,
          ),
        ),
      );
}

/// 목록 아래에 붙는 칸: 더 불러오는 중 · 실패 · 끝.
class _Footer extends StatelessWidget {
  const _Footer({required this.state, required this.controller});

  final LibraryState state;
  final LibraryController controller;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);

    if (state.moreError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: DsSpace.s6),
        child: Column(
          children: [
            Text(state.moreError!.message,
                textAlign: TextAlign.center,
                style: dsTextStyle(DsType.body, p.textSecondary)),
            const SizedBox(height: DsSpace.s3),
            OutlinedButton(onPressed: controller.retryMore, child: const Text('더 불러오기')),
          ],
        ),
      );
    }

    if (state.loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: DsSpace.s6),
        child: Center(child: LoadingView(label: '더 불러오는 중')),
      );
    }

    if (state.endReached) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: DsSpace.s6),
        child: Center(
          child: Text('여기까지예요', style: dsTextStyle(DsType.caption, p.textTertiary)),
        ),
      );
    }

    return const SizedBox(height: DsSpace.s6);
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.value, required this.onChanged});

  final LibraryFilter value;
  final ValueChanged<LibraryFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: DsSpace.s4, vertical: DsSpace.s2),
        children: [
          for (final f in LibraryFilter.values) ...[
            // 선택 상태는 색뿐 아니라 체크 표시와 테두리로도 보인다.
            FilterChip(
              label: Text(f.label),
              selected: f == value,
              showCheckmark: true,
              onSelected: (_) => onChanged(f),
              backgroundColor: p.surfaceRaised,
              selectedColor: p.brandPrimarySubtle,
              checkmarkColor: p.brandTextOnSubtle,
              side: BorderSide(color: f == value ? p.brandPrimary : p.borderSubtle),
              labelStyle: dsTextStyle(
                DsType.body,
                f == value ? p.brandTextOnSubtle : p.textSecondary,
              ),
            ),
            const SizedBox(width: DsSpace.s2),
          ],
        ],
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_error.dart';
import '../../data/worksheet_repository.dart';
import '../../domain/models.dart';

/// 서재 필터. 검색은 없다 — 목록이 짧고, 검색은 커서 페이징과 섞이면 규칙이 두 벌이 된다.
enum LibraryFilter { all, ready, failed }

extension LibraryFilterLabel on LibraryFilter {
  String get label => switch (this) {
        LibraryFilter.all => '전체',
        LibraryFilter.ready => '완성',
        LibraryFilter.failed => '실패',
      };

  bool matches(WorksheetSummary w) => switch (this) {
        LibraryFilter.all => true,
        LibraryFilter.ready => w.status == WorksheetStatus.ready,
        LibraryFilter.failed => w.status == WorksheetStatus.failed,
      };
}

/// 무한 스크롤의 전부. 화면은 이 값만 보고 그린다.
class LibraryState {
  const LibraryState({
    this.items = const [],
    this.filter = LibraryFilter.all,
    this.loading = true,
    this.loadingMore = false,
    this.endReached = false,
    this.error,
    this.moreError,
  });

  /// 서버에서 받은 순서 그대로(최신순). 필터는 화면에서만 건다.
  final List<WorksheetSummary> items;
  final LibraryFilter filter;

  /// 첫 페이지를 받는 중. 이때만 뼈대를 보여준다.
  final bool loading;
  final bool loadingMore;

  /// 마지막 페이지까지 왔다. 이 뒤로는 스크롤해도 요청하지 않는다.
  final bool endReached;

  /// 첫 페이지 실패 — 화면 전체가 오류다.
  final AppError? error;

  /// 다음 페이지 실패 — 이미 받은 목록은 그대로 두고 아래에만 알린다.
  final AppError? moreError;

  List<WorksheetSummary> get visible => items.where(filter.matches).toList(growable: false);

  /// 지금 요청을 하나라도 보내고 있으면 새 요청을 만들지 않는다.
  bool get busy => loading || loadingMore;

  LibraryState copyWith({
    List<WorksheetSummary>? items,
    LibraryFilter? filter,
    bool? loading,
    bool? loadingMore,
    bool? endReached,
    AppError? error,
    AppError? moreError,
    bool clearError = false,
    bool clearMoreError = false,
  }) =>
      LibraryState(
        items: items ?? this.items,
        filter: filter ?? this.filter,
        loading: loading ?? this.loading,
        loadingMore: loadingMore ?? this.loadingMore,
        endReached: endReached ?? this.endReached,
        error: clearError ? null : (error ?? this.error),
        moreError: clearMoreError ? null : (moreError ?? this.moreError),
      );
}

/// 커서 페이징. offset 을 쓰면 새 학습지가 하나 생기는 순간 한 장을 건너뛰거나
/// 같은 장을 두 번 보게 된다. 그래서 마지막 항목의 `createdAt` 을 커서로 쓴다.
class LibraryController extends StateNotifier<LibraryState> {
  LibraryController(this._repo) : super(const LibraryState()) {
    // 생성 즉시 첫 페이지를 받는다. 실패는 예외가 아니라 state 로 들어간다.
    unawaited(refresh());
  }

  final WorksheetRepository _repo;

  Future<void> refresh() async {
    // 첫 페이지를 다시 받는 동안에는 이전 목록을 그대로 보여준다(화면이 깜빡이지 않게).
    state = state.copyWith(
      loading: state.items.isEmpty,
      loadingMore: false,
      clearError: true,
      clearMoreError: true,
    );
    try {
      final page = await _repo.list();
      state = state.copyWith(
        items: page,
        loading: false,
        endReached: page.length < WorksheetRepository.pageSize,
        clearError: true,
      );
    } catch (e, st) {
      state = state.copyWith(loading: false, error: AppError.from(e, st));
    }
  }

  /// 다음 페이지. **이미 요청 중이거나 끝까지 왔으면 아무것도 하지 않는다** —
  /// 스크롤 콜백은 프레임마다 불리므로 여기서 막지 않으면 요청이 수십 개 나간다.
  Future<void> loadMore() async {
    if (state.busy || state.endReached || state.items.isEmpty) return;
    // 직전 페이지가 실패한 상태에서 스크롤만으로 재시도가 반복되면 오류가 무한히 쌓인다.
    // 재시도는 사용자가 버튼으로 시킨다(retryMore).
    if (state.moreError != null) return;

    state = state.copyWith(loadingMore: true);
    final cursor = state.items.last.createdAt;
    try {
      final page = await _repo.list(before: cursor);
      state = state.copyWith(
        items: [...state.items, ...page],
        loadingMore: false,
        endReached: page.length < WorksheetRepository.pageSize,
      );
    } catch (e, st) {
      state = state.copyWith(loadingMore: false, moreError: AppError.from(e, st));
    }
  }

  /// 다음 페이지 실패 후의 명시적 재시도.
  Future<void> retryMore() async {
    if (state.busy) return;
    state = state.copyWith(clearMoreError: true);
    await loadMore();
  }

  void setFilter(LibraryFilter filter) {
    if (filter == state.filter) return;
    state = state.copyWith(filter: filter);
  }
}

final libraryControllerProvider =
    StateNotifierProvider.autoDispose<LibraryController, LibraryState>(
  (ref) => LibraryController(ref.watch(worksheetRepositoryProvider)),
);

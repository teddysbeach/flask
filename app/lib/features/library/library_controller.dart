import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_error.dart';
import '../../data/supabase.dart';
import '../../data/worksheet_repository.dart';
import '../../domain/models.dart';

/// 서재 필터.
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
    this.query = '',
    this.loading = true,
    this.loadingMore = false,
    this.endReached = false,
    this.error,
    this.moreError,
  });

  /// 서버에서 받은 순서 그대로(최신순). 필터는 화면에서만 건다.
  final List<WorksheetSummary> items;
  final LibraryFilter filter;

  /// 제목·주제에서 찾을 말. 빈 문자열이면 검색하지 않는 것과 같다.
  ///
  /// **받아 온 것 안에서만** 찾는다. 서버 검색을 붙이면 커서 페이징과 규칙이 두 벌이
  /// 되는데, 그 복잡함은 학습지 수백 장부터 값을 한다. 대신 화면이 "더 불러오기" 로
  /// 범위를 넓힐 수 있게 두었다 — 지금 규모에서는 이쪽이 정직하다.
  final String query;

  /// 첫 페이지를 받는 중. 이때만 뼈대를 보여준다.
  final bool loading;
  final bool loadingMore;

  /// 마지막 페이지까지 왔다. 이 뒤로는 스크롤해도 요청하지 않는다.
  final bool endReached;

  /// 첫 페이지 실패 — 화면 전체가 오류다.
  final AppError? error;

  /// 다음 페이지 실패 — 이미 받은 목록은 그대로 두고 아래에만 알린다.
  final AppError? moreError;

  List<WorksheetSummary> get visible {
    final q = query.trim().toLowerCase();
    return items.where((w) {
      if (!filter.matches(w)) return false;
      if (q.isEmpty) return true;
      // 제목과 주제를 같이 본다. 모델이 붙인 제목만 보면 "내가 뭘 적었는지" 로는 못 찾는다.
      return w.displayTitle.toLowerCase().contains(q) || w.topic.toLowerCase().contains(q);
    }).toList(growable: false);
  }

  /// 검색어나 필터가 걸려 있는가. 빈 화면의 문구가 이걸로 갈린다 —
  /// "학습지가 없어요" 와 "찾는 학습지가 없어요" 는 다른 말이다.
  bool get narrowed => filter != LibraryFilter.all || query.trim().isNotEmpty;

  /// 지금 요청을 하나라도 보내고 있으면 새 요청을 만들지 않는다.
  bool get busy => loading || loadingMore;

  LibraryState copyWith({
    List<WorksheetSummary>? items,
    LibraryFilter? filter,
    String? query,
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
        query: query ?? this.query,
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

  void setQuery(String query) {
    if (query == state.query) return;
    state = state.copyWith(query: query);
  }
}

/// 홈과 찾기 탭이 **함께 보는** 목록.
///
/// 두 벌로 두면 한쪽에서 지운 학습지가 다른 쪽에 남고, 같은 페이지를 두 번 받아 온다.
/// 홈은 `items`(거르지 않은 전부)를, 찾기는 `visible`(검색·필터를 건 것)을 그린다.
///
/// autoDispose 가 아니다. 탭 두 개가 IndexedStack 안에서 살아 있어 어차피 안 죽고,
/// 죽지 않는 것을 autoDispose 로 두면 "계정이 바뀌어도 안 비워진다" 는 사실이 숨는다.
/// 그래서 계정을 **명시적으로** 지켜본다 — 로그아웃하고 다른 계정으로 들어왔는데
/// 앞사람의 학습지 목록이 그대로 남아 있으면 안 된다.
final libraryControllerProvider =
    StateNotifierProvider<LibraryController, LibraryState>((ref) {
  ref.watch(currentUserProvider);
  return LibraryController(ref.watch(worksheetRepositoryProvider));
});

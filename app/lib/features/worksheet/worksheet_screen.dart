import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:onpar_design_system/onpar_design_system.dart';

import '../../core/analytics.dart';
import '../../core/app_error.dart';
import '../../core/connectivity.dart';
import '../../core/logger.dart';
import '../../core/request_guard.dart';
import '../../core/routes.dart';
import '../../data/offline_store.dart';
import '../../data/storage_repository.dart';
import '../../data/supabase.dart';
import '../../data/worksheet_repository.dart';
import '../../domain/models.dart';
import '../../ui/states/app_state_views.dart';
import '../home/home_prefs.dart';
import '../library/library_controller.dart';
import 'worksheet_assets.dart';
import '../../ui/widgets/feedback.dart';
import 'worksheet_response_mapping.dart';

/// 뷰어를 열기 위해 필요한 것 전부. 한 번에 모아서 받는다 —
/// 셋을 따로 받으면 "본문은 떴는데 필기가 안 붙는" 중간 상태가 생긴다.
class WorksheetViewData {
  const WorksheetViewData({
    required this.sheet,
    required this.html,
    required this.rev,
    required this.strokesPath,
    required this.formatVersion,
    this.fromCache = false,
  });

  final WorksheetSummary sheet;

  /// 학습지 본문 그 자체. URL 이 아니라 문자열인 이유는 두 가지다 —
  /// 외부 요청이 0회인 자족 문서라 통째로 넘겨도 되고, 그래야 오프라인에서도 열린다.
  final String html;

  /// 기기에 보관해 둔 것을 열었는가. 서버를 못 불렀다는 뜻이라 화면이 그렇게 말해 준다.
  final bool fromCache;

  /// 필기 낙관적 잠금의 기준. 0 이면 아직 저장된 필기가 없다.
  final int rev;
  final String? strokesPath;

  /// 저장된 필기의 포맷. 1 이면 옛 문서 좌표다 — 앱은 손대지 않고 그대로 런타임에 넘긴다.
  final int formatVersion;
}

final worksheetViewProvider =
    FutureProvider.autoDispose.family<WorksheetViewData, String>((ref, id) async {
  final repo = ref.watch(worksheetRepositoryProvider);
  final sheet = await repo.get(id);

  final path = sheet.htmlPath;
  if (sheet.status != WorksheetStatus.ready || path == null || path.isEmpty) {
    throw AppError.of(
      AppErrorKind.notFound,
      message: '아직 열 수 있는 학습지가 아니에요. 다 만들어지면 서재에서 열 수 있어요.',
    );
  }

  // 본문은 기기에 있으면 그걸 쓴다. 학습지 HTML 은 한 번 만들어지고 바뀌지 않으므로
  // 다시 확인할 이유가 없다 — 확인하러 가는 순간 오프라인에서 못 열게 된다.
  final store = ref.watch(offlineStoreProvider);
  var fromCache = false;
  var html = await store.readSheet(id);
  if (html == null) {
    html = await ref.watch(storageRepositoryProvider).getWorksheetHtml(path);
    await store.writeSheet(id, html);
  }

  // 필기 메타는 서버에 물어야 한다. 못 물으면 rev 0 으로 두지 않는다 —
  // 0 으로 두면 남의 기기가 저장해 둔 필기를 이 기기가 덮어쓴다.
  ({String? path, int rev, int formatVersion}) meta;
  try {
    meta = await repo.annotationMeta(id);
  } on AppError catch (e) {
    if (!e.retryable) rethrow;
    fromCache = true;
    meta = (path: null, rev: -1, formatVersion: 2);   // rev -1 = 모른다. 저장을 잠근다.
  }

  return WorksheetViewData(
    sheet: sheet,
    html: html,
    rev: meta.rev,
    strokesPath: meta.path,
    formatVersion: meta.formatVersion,
    fromCache: fromCache,
  );
});

/// 필기 도구. 기본은 `none` — 펜을 들기 전에는 캔버스가 포인터를 먹지 않아 본문이 스크롤된다.
enum InkTool { none, pen, highlighter, eraser }

/// 학습지 뷰어. 본문·필기·응답이 전부 WebView 안에서 돌고,
/// Flutter 는 도구 막대와 **저장**을 맡는다.
///
/// 이 화면의 진짜 일은 저장이다. 사용자가 40분 필기하고 앱을 죽여도 남아야 한다.
class WorksheetScreen extends ConsumerStatefulWidget {
  const WorksheetScreen({super.key, required this.worksheetId, this.quizId});

  final String worksheetId;

  /// 복습 알림·딥링크로 들어왔을 때 바로 스크롤할 문제.
  final String? quizId;

  @override
  ConsumerState<WorksheetScreen> createState() => _WorksheetScreenState();
}

class _WorksheetScreenState extends ConsumerState<WorksheetScreen>
    with WidgetsBindingObserver {
  InAppWebViewController? _web;

  /// 아직 서버에 못 올린 응답. `response_id` 로 덮어쓴다 — 마지막 스냅샷만 의미가 있다.
  final _pendingResponses = <String, Map<String, Object?>>{};

  // 3초. 타이핑 한 글자마다 올리면 요청이 폭발하고, 10초면 앱을 닫을 때 너무 많이 잃는다.
  final _responseDebounce = Debouncer(const Duration(seconds: 3));
  final _inkDebounce = Debouncer(const Duration(seconds: 3));

  int _rev = 0;
  bool _inkDirty = false;
  int _strokeCount = 0;
  bool _canUndo = false;
  bool _canRedo = false;

  InkTool _tool = InkTool.none;
  Color? _penColor;
  bool _fingerDrawing = false;

  bool _pageLoaded = false;
  AppError? _pageError;
  bool _saving = false;

  /// 필기 저장을 멈춘 이유. null 이면 정상이고, 값이 있으면 그 문구가 배너로 뜬다.
  ///
  /// 저장을 멈추는 상황은 둘이다: 다른 기기와 충돌했을 때, 그리고 **저장된 필기를 못 불러왔을 때**.
  /// 두 번째가 더 위험하다 — 못 불러온 채로 계속 저장하면 빈 캔버스가 옛 필기를 덮는다.
  String? _inkSaveBlocked;

  /// 서버에서 받은 필기를 화면에 넣는 중. 이때 오는 strokesChanged 는 사용자가 그린 게 아니다.
  bool _applyingRemoteInk = false;

  /// 아직 못 올려 기기에 보관 중인 필기가 있는가. 화면이 그렇게 말해 준다 —
  /// "저장됨" 도 "사라짐" 도 아닌 상태를 사용자가 알아야 앱을 지울지 말지 정할 수 있다.
  bool _spooled = false;

  /// 저장이 겹치지 않게. 두 저장이 같은 rev 로 나가면 하나는 반드시 충돌한다.
  Future<void>? _inFlightSave;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 학습지 id 는 싣지 않는다. 무엇을 몇 번 열었는지는 재지 않고, 열렸다는 것만 센다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(analyticsProvider).track(AnalyticsEvent.worksheetOpen);
      // 홈의 "이어서 하기" 가 여기서 나온다. 서버의 응답·필기 시각으로도 알 수 있지만
      // 그건 **쓴 것**이고 이건 **본 것**이다 — 읽기만 하고 나온 학습지도 이어서 볼 대상이다.
      unawaited(rememberOpenedWorksheet(ref, widget.worksheetId));
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _responseDebounce.dispose();
    _inkDebounce.dispose();
    super.dispose();
  }

  /// 앱이 뒤로 넘어가면 디바운스를 기다리지 않는다. 여기서 안 쓰면
  /// iOS 가 프로세스를 정리할 때 마지막 3초가 사라진다.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(_flush(reason: 'lifecycle:${state.name}'));
    }
  }

  // ── WebView 브리지 ──────────────────────────────────────────────────

  void _registerBridges(InAppWebViewController c) {
    // 학습 응답: 무엇을 골랐고 무엇을 썼는지.
    c.addJavaScriptHandler(
      handlerName: 'learn',
      callback: (args) {
        _onLearnMessage(args.isEmpty ? null : args.first);
        return null;
      },
    );

    // 필기: 획이 바뀔 때마다 개수와 undo/redo 가능 여부가 온다.
    c.addJavaScriptHandler(
      handlerName: 'ink',
      callback: (args) {
        _onInkMessage(args.isEmpty ? null : args.first);
        return null;
      },
    );
  }

  void _onLearnMessage(Object? message) {
    if (message is! Map) return;
    // {type: 'choice'|'written'|'slider', payload: {...}}
    final row = mapLearnResponse(message['payload']);
    if (row == null) return; // slider 등 저장 대상이 아닌 것

    final wasClean = _pendingResponses.isEmpty;
    _pendingResponses[row['response_id']! as String] = row;
    // "저장 대기 중" 표시를 바로 띄운다 — 사용자는 이걸 보고 앱을 닫아도 되는지 판단한다.
    if (wasClean && mounted) setState(() {});
    _responseDebounce.run(() => unawaited(_flush(reason: 'learn')));
  }

  void _onInkMessage(Object? message) {
    if (message is! Map) return;
    if (message['type'] != 'strokesChanged') return;
    final payload = message['payload'];
    if (payload is! Map) return;

    final count = (payload['count'] as num?)?.toInt() ?? 0;
    final canUndo = payload['canUndo'] == true;
    final canRedo = payload['canRedo'] == true;

    // 방금 우리가 loadStrokes 로 넣은 것이면 "바뀜" 이 아니다.
    // 여기서 dirty 로 세면 열자마자 같은 필기를 그대로 되올리고, rev 만 계속 올라간다.
    if (!_applyingRemoteInk) _inkDirty = true;
    if (mounted &&
        (count != _strokeCount || canUndo != _canUndo || canRedo != _canRedo)) {
      setState(() {
        _strokeCount = count;
        _canUndo = canUndo;
        _canRedo = canRedo;
      });
    }
    if (!_applyingRemoteInk) _inkDebounce.run(() => unawaited(_flush(reason: 'ink')));
  }

  // ── 저장 ────────────────────────────────────────────────────────────

  /// 밀린 것을 지금 전부 올린다. 디바운스 타이머는 취소한다 — 두 번 올릴 이유가 없다.
  Future<void> _flush({required String reason}) {
    _responseDebounce.dispose();
    _inkDebounce.dispose();

    // 이미 저장 중이면 그게 끝난 뒤에 이어서 한 번 더 돈다. 두 저장이 같은 rev 로
    // 동시에 나가면 하나는 반드시 충돌하고, 사용자는 이유 없는 경고를 본다.
    final running = _inFlightSave;
    final chained = running == null ? _runSave(reason) : running.then((_) => _runSave(reason));
    late final Future<void> wrapped;
    wrapped = chained.whenComplete(() {
      if (identical(_inFlightSave, wrapped)) _inFlightSave = null;
    });
    _inFlightSave = wrapped;
    return wrapped;
  }

  Future<void> _runSave(String reason) async {
    if (_pendingResponses.isEmpty && !_inkDirty) return;
    if (mounted) setState(() => _saving = true);
    try {
      await _saveResponses();
      await _saveInk();
    } finally {
      if (mounted) setState(() => _saving = false);
      AppLogger.debug('학습지 저장 시도 ($reason)');
    }
  }

  Future<void> _saveResponses() async {
    if (_pendingResponses.isEmpty) return;
    final rows = _pendingResponses.values.toList(growable: false);
    _pendingResponses.clear();

    try {
      await ref.read(worksheetRepositoryProvider).saveResponses(widget.worksheetId, rows);
    } catch (e, st) {
      // 실패한 행을 버리면 학생이 쓴 답이 사라진다. 되돌려 놓고 다음 기회에 다시 올린다.
      // 그 사이 더 새로운 스냅샷이 왔다면 그쪽이 이긴다.
      for (final r in rows) {
        _pendingResponses.putIfAbsent(r['response_id']! as String, () => r);
      }
      final err = AppError.from(e, st);
      AppLogger.error('학습 응답 저장 실패', error: err, stack: st);
      _notify(err.message);
    }
  }

  Future<void> _saveInk() async {
    final web = _web;
    if (web == null || !_inkDirty || _inkSaveBlocked != null) return;

    final json = await _exportStrokes(web);
    if (json == null) return;

    // 스냅샷을 떴다. 여기부터 그리는 획은 "다음 저장분" 이므로 dirty 를 지금 내린다 —
    // 저장이 끝난 뒤에 내리면 업로드하는 동안 그은 획이 통째로 사라진다.
    _inkDirty = false;
    try {
      await _commitInk(json: json, rev: _rev);
    } on AppError catch (e, st) {
      _inkDirty = true; // 못 올렸다. 다음 기회에 다시 올린다.
      if (e.code == 'annotation_conflict') {
        // 다른 기기가 먼저 저장했다. 덮어쓰면 그쪽 필기가 말없이 사라진다 — 합치거나 물어본다.
        await _onAnnotationConflict(localJson: json);
        return;
      }
      await _spool(json, e, st);
    } catch (e, st) {
      _inkDirty = true;
      await _spool(json, AppError.from(e, st), st);
    }
  }

  /// 못 올린 필기를 기기에 적는다.
  ///
  /// 여기가 없으면 지하철에서 40분 필기하고 앱이 죽는 순간 그게 전부 사라진다.
  /// 메모리에만 들고 있는 것은 "다음에 다시 올린다" 가 아니라 "앱이 살아 있는 동안만" 이다.
  Future<void> _spool(String json, AppError err, StackTrace st) async {
    AppLogger.error('필기 저장 실패 — 기기에 보관한다', error: err, stack: st);
    try {
      await ref.read(offlineStoreProvider)
          .writeInkSpool(widget.worksheetId, json: json, rev: _rev);
      if (mounted) {
        setState(() => _spooled = true);
      }
    } catch (e2, st2) {
      // 기기에도 못 적었다. 이때는 숨기지 않고 그대로 말한다.
      AppLogger.error('필기를 기기에도 못 적었다', error: e2, stack: st2);
      _notify(err.message);
    }
  }

  /// 기기에 남아 있는 필기를 올린다. 학습지를 열 때와 연결이 돌아왔을 때 부른다.
  Future<void> _flushSpool() async {
    final store = ref.read(offlineStoreProvider);
    final spool = await store.readInkSpool(widget.worksheetId);
    if (spool == null) return;

    try {
      if (spool.rev < 0) {
        // 그릴 때 서버 판을 몰랐다(오프라인으로 열었다). 덮어쓰지 않고 합치는 길로 간다.
        await _onAnnotationConflict(localJson: spool.json);
      } else {
        await _commitInk(json: spool.json, rev: spool.rev);
      }
      await store.clearInkSpool(widget.worksheetId);
      if (mounted) {
        setState(() => _spooled = false);
        _notify('기기에 있던 필기를 올렸어요.');
      }
    } on AppError catch (e, st) {
      if (e.code == 'annotation_conflict') {
        await _onAnnotationConflict(localJson: spool.json);
        return;
      }
      // 아직도 못 올린다. 보관물은 그대로 둔다 — 지우는 순간 그 필기는 사라진다.
      AppLogger.error('보관한 필기를 아직 못 올렸다', error: e, stack: st);
    } catch (e, st) {
      AppLogger.error('보관한 필기를 아직 못 올렸다', error: e, stack: st);
    }
  }

  /// 필기 한 벌을 서버에 올린다. **파일 먼저, DB 나중.**
  ///
  /// 순서를 뒤집으면 DB 는 "저장됨(rev+1)" 인데 파일이 없는 상태가 생기고,
  /// 다음에 열 때 필기가 통째로 사라진 것처럼 보인다 — 되돌릴 수 없는 손상이다.
  /// 이 순서면 최악이라도 "파일은 올라갔는데 rev 가 안 오른" 상태고, 다음 저장이 같은 경로를 덮어 고친다.
  ///
  /// 실패는 그대로 던진다(호출한 쪽이 충돌과 그 밖을 갈라 처리한다).
  Future<void> _commitInk({required String json, required int rev}) async {
    final userId = ref.read(currentUserProvider)?.id;
    if (userId == null) throw AppError.of(AppErrorKind.unauthorized);

    final path = StoragePaths.annotations(userId: userId, worksheetId: widget.worksheetId);
    final payload = InkCodec.encode(json);

    await ref.read(storageRepositoryProvider).putAnnotations(path, payload.bytes);

    final next = await ref.read(worksheetRepositoryProvider).saveAnnotations(
          worksheetId: widget.worksheetId,
          strokesPath: path,
          // 화면 카운터가 아니라 방금 올린 문서에서 센다 — 저장된 것과 기록이 어긋나지 않는다.
          strokeCount: InkCodec.strokeCount(json),
          // `bytes` 는 실제 저장 용량이므로 압축 **후** 크기다.
          bytes: payload.gzipBytes,
          rev: rev,
        );
    _rev = next;
    // 올라갔으니 기기에 둔 것은 지운다. 남겨 두면 다음에 열 때 옛 필기를 다시 올린다.
    await ref.read(offlineStoreProvider).clearInkSpool(widget.worksheetId);
    if (mounted && _spooled) setState(() => _spooled = false);
    AppLogger.debug(
      '필기 저장 rev=$next, ${payload.rawBytes}B → ${payload.gzipBytes}B '
      '(${(payload.ratio * 100).round()}%)',
    );
  }

  /// 저장된 필기를 화면에 되돌린다. **웹뷰 로드가 끝난 뒤에만** 부른다 —
  /// 그 전에는 window.ONPAR_INK 가 아직 없다.
  Future<void> _restoreInk(WorksheetViewData data) async {
    final path = data.strokesPath;
    // 서버에 저장된 필기가 없어도(첫 방문, 또는 오프라인이라 메타를 못 읽음)
    // 기기에 못 올린 필기는 있을 수 있다. 그건 반드시 살려야 한다.
    if (path == null || path.isEmpty) {
      final spool = await ref.read(offlineStoreProvider).readInkSpool(widget.worksheetId);
      if (spool == null) return;
      await _applyStrokes(spool.json);
      if (mounted) setState(() => _spooled = true);
      unawaited(_flushSpool());
      return;
    }

    try {
      // 기기에 못 올린 필기가 있으면 그게 가장 최신이다. 서버 것보다 먼저 화면에 올린다 —
      // 반대로 하면 사용자가 어제 지하철에서 쓴 것이 눈앞에서 사라진다.
      final spool = await ref.read(offlineStoreProvider).readInkSpool(widget.worksheetId);
      if (spool != null) {
        await _applyStrokes(spool.json);
        _rev = data.rev;
        if (mounted) setState(() => _spooled = true);
        unawaited(_flushSpool());
        return;
      }

      final gzipped = await ref.read(storageRepositoryProvider).getAnnotations(path);
      if (gzipped == null) {
        // 메타는 있는데 파일이 없다. 새로 쓰면 되는 상태이므로 오류로 덮지 않는다.
        AppLogger.debug('저장된 필기 파일이 없어 복원을 건너뛴다');
        return;
      }
      // formatVersion 이 1 이면 옛 문서 좌표(anchor 없음)다. 앱은 아무것도 고치지 않고 그대로 넘긴다 —
      // 런타임의 ink-core `migrateStrokes` 가 anchor: null 로 읽어 그린다(docs/plan/06-annotation.md §4).
      // 여기서 앱이 좌표를 손대면 옛 필기가 제자리에서 움직인다.
      if (data.formatVersion == 1) AppLogger.debug('v1 필기를 그대로 런타임에 넘긴다');
      await _applyStrokes(InkCodec.decode(gzipped));
      _rev = data.rev;
    } catch (e, st) {
      final err = AppError.from(e, st);
      AppLogger.error('필기 복원 실패', error: err, stack: st);
      // 못 불러온 채로 계속 저장하면 **빈 캔버스가 저장된 필기를 덮는다**. 그래서 저장을 멈춘다.
      if (mounted) {
        setState(() => _inkSaveBlocked =
            '저장해 둔 필기를 불러오지 못했어요. 옛 필기를 덮어쓰지 않으려고 지금은 저장하지 않아요.');
      }
    }
  }

  /// 서버에서 받은 필기를 캔버스에 넣는다.
  Future<void> _applyStrokes(String json) async {
    _applyingRemoteInk = true;
    // loadStrokes 는 파싱된 객체를 받는다. 문자열을 그대로 넘기면 deserialize 가 빈 문서로 읽는다.
    await _eval('window.ONPAR_INK.loadStrokes(JSON.parse(${jsonEncode(json)}))');
    // loadStrokes 가 만든 strokesChanged 는 JS→Flutter 브리지를 타고 조금 늦게 온다.
    // 곧바로 플래그를 내리면 방금 불러온 것을 "사용자가 그린 것" 으로 보고 그대로 되올린다.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    _applyingRemoteInk = false;
    _inkDirty = false;
  }

  /// 충돌. 자동으로 이기려 들지 않는다 — 필기를 지우는 건 되돌릴 수 없는 손상이다.
  ///
  /// 스트로크는 append-only 에 고유 id 를 가지고 지우개는 tombstone 이라, 대개는 **합칠 수 있다**.
  /// 합치면 아무도 잃지 않는다. 합칠 수 없을 때만 사용자에게 묻는다.
  Future<void> _onAnnotationConflict({required String localJson}) async {
    if (mounted) {
      setState(() => _inkSaveBlocked =
          '다른 기기에서 먼저 저장했어요. 지금 쓴 필기는 아직 저장되지 않았어요.');
    }

    final String? remoteJson;
    final int remoteRev;
    try {
      final meta = await ref.read(worksheetRepositoryProvider).annotationMeta(widget.worksheetId);
      remoteRev = meta.rev;
      _rev = meta.rev;
      final path = meta.path;
      final gzipped =
          path == null ? null : await ref.read(storageRepositoryProvider).getAnnotations(path);
      remoteJson = gzipped == null ? null : InkCodec.decode(gzipped);
    } catch (e, st) {
      // 여기서 그냥 돌아가면 사용자가 방금 쓴 획이 메모리에만 남는다. 기기에 적어 둔다.
      await _spool(localJson, AppError.from(e, st), st);
      _notify('지금은 서버를 못 불러서 이 기기에 보관했어요. 연결되면 자동으로 올려요.');
      return;
    }

    String merged;
    try {
      // 파일이 없으면 합칠 상대가 없다. 우리 것을 새 rev 로 올리면 잃는 게 없다.
      merged =
          remoteJson == null ? localJson : InkCodec.merge(local: localJson, remote: remoteJson);
    } catch (e, st) {
      AppLogger.error('필기 병합 실패', error: AppError.from(e, st), stack: st);
      await _askConflictResolution(localJson: localJson, rev: remoteRev);
      return;
    }

    try {
      await _commitInk(json: merged, rev: remoteRev);
    } catch (e, st) {
      // 합치기까지는 됐는데 못 올렸다. 합친 결과를 기기에 적는다 —
      // 여기서 로컬 것만 남기면 다른 기기의 필기를 잃는다.
      await _spool(merged, AppError.from(e, st), st);
      _notify('합친 필기를 아직 못 올렸어요. 이 기기에 보관했다가 다시 올릴게요.');
      _inkDirty = true;
      return;
    }

    await _applyStrokes(merged);
    if (mounted) setState(() => _inkSaveBlocked = null);
    _notify('다른 기기에서 쓴 필기와 지금 필기를 합쳤어요.');
  }

  /// 합칠 수 없을 때. 어느 쪽도 몰래 버리지 않고 사용자가 고르게 한다.
  /// 아무것도 고르지 않으면 저장은 멈춘 채로 남는다 — 배너가 계속 보이고, 지금 필기는 화면에 그대로 있다.
  Future<void> _askConflictResolution({required String localJson, required int rev}) async {
    if (!mounted) return;
    final overwrite = await AppFeedback.confirm(
      context,
      title: '두 필기를 합치지 못했어요',
      message: '다른 기기에서 먼저 저장한 필기와 지금 필기를 자동으로 합칠 수 없었어요.\n'
          '지금 필기로 덮어쓰면 다른 기기에서 쓴 필기는 이 학습지에서 사라져요.',
      confirmLabel: '지금 필기로 덮어쓰기',
      cancelLabel: '나중에',
      destructive: true,
    );
    if (!overwrite) {
      _inkDirty = true; // 아직 저장 안 된 상태 그대로 둔다. 배너도 그대로 남는다.
      return;
    }

    try {
      await _commitInk(json: localJson, rev: rev);
      if (mounted) setState(() => _inkSaveBlocked = null);
      _notify('지금 필기로 저장했어요.');
    } catch (e, st) {
      _inkDirty = true;
      AppLogger.error('덮어쓰기 저장 실패', error: AppError.from(e, st), stack: st);
      _notify('저장하지 못했어요. 잠시 뒤에 다시 시도해 주세요.');
    }
  }

  /// 배너의 “불러오기”. 최신 필기를 받으면 저장 안 된 지금 필기는 사라지므로 먼저 물어본다.
  Future<void> _reloadInkFromServer() async {
    if (_inkDirty && mounted) {
      final ok = await AppFeedback.confirm(
        context,
        title: '최신 필기를 불러올까요?',
        message: '아직 저장되지 않은 지금 필기는 사라져요.',
        confirmLabel: '불러오기',
        cancelLabel: '그대로 두기',
        destructive: true,
      );
      if (!ok) return;
    }
    _reloadEverything();
  }

  Future<String?> _exportStrokes(InAppWebViewController web) async {
    final raw = await web.evaluateJavascript(
      source: 'JSON.stringify((window.ONPAR_INK && window.ONPAR_INK.exportStrokes()) || null)',
    );
    if (raw is! String || raw.isEmpty || raw == 'null') return null;
    return raw;
  }

  void _notify(String message) {
    if (!mounted) return;
    AppFeedback.toast(context, message);
  }

  // ── JS 호출 ────────────────────────────────────────────────────────

  /// JS 가 던져도 화면은 살아 있어야 한다. 필기가 안 되는 학습지는 불편하지만,
  /// 뷰어가 죽은 학습지는 쓸모가 없다.
  Future<void> _eval(String source) async {
    final web = _web;
    if (web == null) return;
    await web.evaluateJavascript(
      source: 'try { $source } catch (e) { console.error("[onpar] bridge", e) }',
    );
  }

  Future<void> _applyTool(InkTool tool, {Color? color}) async {
    if (!mounted) return;
    setState(() {
      _tool = tool;
      if (color != null) _penColor = color;
    });

    final p = DsTheme.of(context);
    final args = switch (tool) {
      InkTool.none => {'tool': 'none'},
      InkTool.pen => {'tool': 'pen', 'color': _hex(_penColor ?? p.inkPen), 'width': 2.4},
      InkTool.highlighter => {'tool': 'highlighter', 'color': _hex(p.inkHighlighter), 'width': 16.0},
      // 주의: 지금 ink-runtime 의 setTool 은 TOOLS(['pen','highlighter']) 밖의 값을 던진다.
      // 그리기 쪽(onDown/onMove)은 'eraser' 를 이미 처리하므로 검증만 빠진 상태다.
      // _eval 이 try/catch 로 감싸 화면은 살아 있지만, 런타임이 고쳐지기 전까지
      // 지우개는 아무 일도 하지 않는다. (필기 런타임 담당에게 보고함)
      InkTool.eraser => {'tool': 'eraser'},
    };
    await _eval('window.ONPAR_INK.setTool(${jsonEncode(args)})');
  }

  Future<void> _clearAll() async {
    final ok = await AppFeedback.confirm(
      context,
      title: '필기를 전부 지울까요?',
      message: '이 학습지에 한 필기가 모두 사라져요. 되돌리기로 되살릴 수는 있어요.',
      confirmLabel: '전부 지우기',
      destructive: true,
    );
    if (!ok) return;
    await _eval('window.ONPAR_INK.clearAll()');
  }

  // ── 제목 · 인쇄 · 삭제 ───────────────────────────────────────────────

  /// 제목 바꾸기. 모델이 붙인 제목이 항상 사용자의 말은 아니다.
  Future<void> _rename(WorksheetViewData? data) async {
    if (data == null) return;
    final next = await AppFeedback.prompt(
      context,
      title: '제목 바꾸기',
      initial: data.sheet.displayTitle,
      hint: '학습지 제목',
      confirmLabel: '저장',
      maxLength: 120,
    );
    if (next == null || next.trim() == data.sheet.displayTitle) return;
    try {
      await ref.read(worksheetRepositoryProvider).rename(widget.worksheetId, next);
      unawaited(ref.read(libraryControllerProvider.notifier).refresh());
      // 제목은 뷰어·서재·홈이 같이 들고 있다. 한 곳만 고치면 서로 다른 제목이 보인다.
      ref.invalidate(worksheetViewProvider(widget.worksheetId));
      if (mounted) AppFeedback.toast(context, '제목을 바꿨어요.');
    } on AppError catch (e) {
      if (mounted) AppFeedback.toast(context, e.message, danger: true);
    }
  }

  /// 인쇄(그리고 "PDF로 저장").
  ///
  /// 학습지 CSS 에는 진작 `@media print` 가 있었다 — 정답을 숨기고, 접어 둔 것을 펴고,
  /// 구역이 페이지 경계에서 잘리지 않게. 그걸 부를 버튼이 앱에 없었을 뿐이다.
  /// **필기는 저장하고 나서 연다.** 인쇄 대화상자가 뜨는 동안의 저장 실패는 조용히 사라진다.
  Future<void> _print() async {
    final web = _web;
    if (web == null) return;
    await _flush(reason: 'print');
    try {
      await web.printCurrentPage();
      ref.read(analyticsProvider).track(AnalyticsEvent.worksheetOpen, props: {'source': 'print'});
    } catch (e, st) {
      AppLogger.error('인쇄를 열지 못했어요', error: e, stack: st);
      if (mounted) {
        AppFeedback.toast(context, '인쇄 화면을 열지 못했어요. 잠시 뒤에 다시 시도해 주세요.',
            danger: true);
      }
    }
  }

  /// 학습지 삭제. **되돌릴 수 없다** — 필기도 같이 사라진다.
  Future<void> _delete(WorksheetViewData? data) async {
    if (data == null) return;
    final ok = await AppFeedback.confirm(
      context,
      title: '이 학습지를 지울까요?',
      message: '학습지와 여기에 쓴 필기·답안이 모두 사라져요. 되돌릴 수 없어요.\n'
          '사용한 장수는 돌아오지 않아요.',
      confirmLabel: '지우기',
      cancelLabel: '그대로 두기',
      destructive: true,
    );
    if (!ok || !mounted) return;

    try {
      await ref.read(worksheetRepositoryProvider).delete(widget.worksheetId);
      // 홈과 찾기가 같은 목록을 본다. 지운 장이 목록에 남아 있으면 눌렀을 때
      // "없는 학습지" 오류가 나고, 사용자는 삭제가 실패한 줄 안다.
      unawaited(ref.read(libraryControllerProvider.notifier).refresh());
      if (!mounted) return;
      // 지운 학습지의 뷰어에 남아 있을 이유가 없다.
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(Routes.library);
      }
      AppFeedback.toast(context, '학습지를 지웠어요.');
    } on AppError catch (e) {
      if (mounted) AppFeedback.toast(context, e.message, danger: true);
    }
  }

  // ── 화면 ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    final view = ref.watch(worksheetViewProvider(widget.worksheetId));
    final offline = ref.watch(netStatusProvider).valueOrNull == NetStatus.offline;

    return PopScope(
      // 저장이 끝나기 전에 화면이 사라지면 마지막 필기와 답이 날아간다.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _flush(reason: 'pop');
        if (context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: p.surfaceBase,
        appBar: AppBar(
          title: Text(view.valueOrNull?.sheet.displayTitle ?? '학습지'),
          actions: [
            _SaveIndicator(saving: _saving, dirty: _inkDirty || _pendingResponses.isNotEmpty),
            // 제목 바꾸기·인쇄·삭제. 서버는 진작 셋 다 허용하고 있었는데
            // 앱에 부르는 곳이 없어서, 사용자가 할 수 있는 일이 "읽기" 뿐이었다.
            _SheetMenu(
              enabled: view.hasValue,
              onRename: () => unawaited(_rename(view.valueOrNull)),
              onPrint: () => unawaited(_print()),
              onDelete: () => unawaited(_delete(view.valueOrNull)),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              // 배너가 뜨고 지는 동안 **자리도 같이 열리고 닫힌다.**
              // 필기 중에 학습지가 한 칸 툭 밀리면 그 순간 그은 획이 어긋난 자리에 남는다.
              AnimatedSize(
                duration: dsDuration(context, DsMotion.base),
                curve: DsCurve.standard,
                alignment: Alignment.topCenter,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (offline) const OfflineBanner(),
                    // "저장됨" 도 "사라짐" 도 아닌 상태가 있다. 그걸 말하지 않으면 사용자는
                    // 앱을 지워도 되는지 알 수 없고, 지우면 그 필기는 정말 사라진다.
                    if (_spooled) const _SpooledBanner(),
                    if (_inkSaveBlocked != null)
                      _InkBlockedBanner(
                        message: _inkSaveBlocked!,
                        onReload: () => unawaited(_reloadInkFromServer()),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: dsAsync(view,
                  loading: () => const LoadingView(label: '학습지를 여는 중'),
                  error: (e, st) => _errorView(context, AppError.from(e, st)),
                  data: (data) => _viewer(context, data),
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: view.hasValue
            ? _InkToolbar(
                tool: _tool,
                penColor: _penColor ?? p.inkPen,
                canUndo: _canUndo,
                canRedo: _canRedo,
                fingerDrawing: _fingerDrawing,
                onTool: (t) => unawaited(_applyTool(t)),
                onPenColor: (c) => unawaited(_applyTool(InkTool.pen, color: c)),
                onUndo: () => unawaited(_eval('window.ONPAR_INK.undo()')),
                onRedo: () => unawaited(_eval('window.ONPAR_INK.redo()')),
                onClearAll: () => unawaited(_clearAll()),
                onToggleFinger: () {
                  setState(() => _fingerDrawing = !_fingerDrawing);
                  unawaited(_eval('window.ONPAR_INK.setFingerDrawing($_fingerDrawing)'));
                },
              )
            : null,
      ),
    );
  }

  void _reloadEverything() {
    setState(() {
      _inkSaveBlocked = null;
      _pageLoaded = false;
      _pageError = null;
    });
    ref.invalidate(worksheetViewProvider(widget.worksheetId));
  }

  /// 삭제됐거나 남의 학습지는 "다시 시도" 가 의미 없다. 갈 곳을 준다.
  Widget _errorView(BuildContext context, AppError error) {
    final gone = error.kind == AppErrorKind.notFound || error.kind == AppErrorKind.forbidden;
    if (!gone) {
      return ErrorView(
        error: error,
        onRetry: _reloadEverything,
        secondaryLabel: '서재로 가기',
        onSecondary: () => context.go(Routes.library),
      );
    }

    final p = DsTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DsSpace.s8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DsIcon(DsIcons.info, size: 36, color: p.textTertiary),
            const SizedBox(height: DsSpace.s4),
            Text(
              error.kind == AppErrorKind.forbidden ? '이 학습지는 열 수 없어요' : '학습지를 찾지 못했어요',
              textAlign: TextAlign.center,
              style: dsTextStyle(DsType.h3, p.textPrimary),
            ),
            const SizedBox(height: DsSpace.s2),
            Text(error.message,
                textAlign: TextAlign.center, style: dsTextStyle(DsType.body, p.textSecondary)),
            const SizedBox(height: DsSpace.s6),
            FilledButton(
              onPressed: () => context.go(Routes.library),
              child: const Text('서재로 가기'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _viewer(BuildContext context, WorksheetViewData data) {
    _rev = _rev == 0 ? data.rev : _rev;

    return Stack(
      children: [
        InAppWebView(
          // 문서를 통째로 넘긴다. 외부 요청이 0회라 baseUrl 이 필요 없고,
          // 그래서 오프라인에서도 온라인과 똑같이 열린다.
          initialData: InAppWebViewInitialData(data: data.html, mimeType: 'text/html', encoding: 'utf-8'),
          // 본문 글꼴은 앱 번들에 있다. 문서에 굽지 않고 열면서 얹는다 —
          // 이유는 worksheet_assets.dart 에 적어 두었다.
          initialUserScripts: UnmodifiableListView([
            UserScript(
              source: kWorksheetFontUserScript,
              injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
            ),
          ]),
          initialSettings: InAppWebViewSettings(
            // 학습지는 우리가 만든 문서다. 바깥으로 나갈 일이 없다.
            javaScriptEnabled: true,
            supportZoom: true,
            transparentBackground: true,
            // 애플펜슬 필기는 WebView 안에서 한다. 브라우저 제스처가 가로채면 획이 끊긴다.
            disableLongPressContextMenuOnLinks: true,
            allowsInlineMediaPlayback: true,
            // 본문 글꼴을 앱 번들에서 먹인다(아래 onLoadResourceWithCustomScheme).
            // 학습지 HTML 에 글꼴을 굽지 않는 이유는 용량이다 — 한 장에 200KB 가 붙으면
            // 오프라인 보관과 스토리지 비용이 같이 세 배가 된다. 앱이 한 벌만 들고 먹인다.
            resourceCustomSchemes: [kAssetScheme],
          ),
          onLoadResourceWithCustomScheme: (c, request) async {
            final bytes = await loadWorksheetAsset(request.url);
            if (bytes == null) return null;
            return CustomSchemeResponse(
              data: bytes,
              contentType: 'font/ttf',
              contentEncoding: 'utf-8',
            );
          },
          onWebViewCreated: (c) {
            _web = c;
            _registerBridges(c);
          },
          onLoadStop: (c, url) async {
            if (!mounted) return;
            setState(() {
              _pageLoaded = true;
              _pageError = null;
            });
            // 읽기 모드로 시작한다. 펜을 들기 전에는 본문이 자유롭게 스크롤돼야 한다.
            await _applyTool(InkTool.none);
            await _eval('window.ONPAR_INK.setFingerDrawing($_fingerDrawing)');

            // 저장된 필기를 여기서 되돌린다. 웹뷰 로드가 끝난 뒤여야 window.ONPAR_INK 가 있다.
            await _restoreInk(data);

            final quizId = widget.quizId;
            if (quizId != null && quizId.isNotEmpty) {
              await _eval('window.ONPAR_INK.scrollToQuiz(${jsonEncode(quizId)})');
            }
          },
          onReceivedError: (c, request, error) {
            // 본문이 아닌 리소스 하나가 실패한 것으로 학습지 전체를 오류로 덮지 않는다.
            if (!mounted || request.isForMainFrame == false) return;
            setState(() => _pageError = AppError.of(
                  AppErrorKind.offline,
                  message: '학습지를 불러오지 못했어요. 연결을 확인하고 다시 시도해 주세요.',
                ));
          },
          onReceivedHttpError: (c, request, response) {
            if (!mounted || request.isForMainFrame == false) return;
            // 서명 URL 은 1시간이면 만료된다. 다시 받아 오면 대개 풀린다.
            setState(() => _pageError =
                AppError.of(AppError.kindOfStatus(response.statusCode ?? 500)));
          },
        ),
        if (_pageError != null)
          Container(
            color: DsTheme.of(context).surfaceBase,
            child: ErrorView(error: _pageError!, onRetry: _reloadEverything),
          )
        else if (!_pageLoaded)
          Container(
            color: DsTheme.of(context).surfaceBase,
            child: const LoadingView(label: '학습지를 그리는 중'),
          ),
      ],
    );
  }
}

String _hex(Color c) {
  int ch(double v) => (v * 255).round().clamp(0, 255);
  return '#${ch(c.r).toRadixString(16).padLeft(2, '0')}'
      '${ch(c.g).toRadixString(16).padLeft(2, '0')}'
      '${ch(c.b).toRadixString(16).padLeft(2, '0')}';
}

// ── 도구 막대 ────────────────────────────────────────────────────────────

class _InkToolbar extends StatelessWidget {
  const _InkToolbar({
    required this.tool,
    required this.penColor,
    required this.canUndo,
    required this.canRedo,
    required this.fingerDrawing,
    required this.onTool,
    required this.onPenColor,
    required this.onUndo,
    required this.onRedo,
    required this.onClearAll,
    required this.onToggleFinger,
  });

  final InkTool tool;
  final Color penColor;
  final bool canUndo;
  final bool canRedo;
  final bool fingerDrawing;
  final ValueChanged<InkTool> onTool;
  final ValueChanged<Color> onPenColor;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onClearAll;
  final VoidCallback onToggleFinger;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: p.surfaceRaised,
        border: Border(top: BorderSide(color: p.borderSubtle)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 펜을 들었을 때만 색이 나온다. 늘 보이면 막대가 두 줄로 무거워진다.
            if (tool == InkTool.pen)
              Padding(
                padding: const EdgeInsets.only(top: DsSpace.s2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final c in [p.inkPen, p.inkPenBlue, p.inkPenRed])
                      _ColorDot(
                        color: c,
                        selected: c.toARGB32() == penColor.toARGB32(),
                        onTap: () => onPenColor(c),
                      ),
                  ],
                ),
              ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _ToolButton(
                    icon: DsIcons.guide,
                    label: '읽기',
                    selected: tool == InkTool.none,
                    onTap: () => onTool(InkTool.none),
                  ),
                  _ToolButton(
                    icon: DsIcons.pen,
                    label: '펜',
                    selected: tool == InkTool.pen,
                    onTap: () => onTool(InkTool.pen),
                  ),
                  _ToolButton(
                    icon: DsIcons.highlighter,
                    label: '형광펜',
                    selected: tool == InkTool.highlighter,
                    onTap: () => onTool(InkTool.highlighter),
                  ),
                  _ToolButton(
                    icon: DsIcons.eraser,
                    label: '지우개',
                    selected: tool == InkTool.eraser,
                    onTap: () => onTool(InkTool.eraser),
                  ),
                  _Divider(color: p.borderSubtle),
                  _ToolButton(
                    icon: DsIcons.undo,
                    label: '되돌리기',
                    enabled: canUndo,
                    onTap: onUndo,
                  ),
                  _ToolButton(
                    icon: DsIcons.redo,
                    label: '다시하기',
                    enabled: canRedo,
                    onTap: onRedo,
                  ),
                  _ToolButton(
                    icon: DsIcons.clearAll,
                    label: '전체 지우기',
                    onTap: onClearAll,
                  ),
                  _Divider(color: p.borderSubtle),
                  _ToolButton(
                    icon: DsIcons.activity,
                    label: '손가락',
                    selected: fingerDrawing,
                    onTap: onToggleFinger,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 28, margin: const EdgeInsets.symmetric(horizontal: DsSpace.s1), color: color);
}

/// 도구 한 칸. 48dp 이상이고, 선택은 색이 아니라 배경 알약 + 글자 굵기로도 보인다.
class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.enabled = true,
  });

  final List<String> icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    final fg = !enabled
        ? p.textDisabled
        : selected
            ? p.brandTextOnSubtle
            : p.textSecondary;

    // 라벨은 Semantics 가, 탭 동작은 InkWell 이 만든다. 둘을 MergeSemantics 로 합치고
    // 안쪽의 아이콘·글자는 장식으로 뺀다(안 그러면 "펜 펜" 처럼 두 번 읽힌다).
    return MergeSemantics(
      child: Semantics(
        button: true,
        enabled: enabled,
        selected: selected,
        label: label,
        child: Padding(
          padding: const EdgeInsets.all(DsSpace.s1),
          // 도구는 필기 중에 가장 자주 누르는 것이다. 고른 도구의 배경이 흐르며 들어와야
          // "바뀌었다"가 손보다 늦지 않는다.
          child: AnimatedContainer(
            duration: dsDuration(context, DsMotion.fast),
            curve: DsCurve.standard,
            decoration: BoxDecoration(
              color: selected ? p.brandPrimarySubtle : Colors.transparent,
              borderRadius: BorderRadius.circular(DsRadius.md),
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(DsRadius.md),
              child: InkWell(
                onTap: enabled ? onTap : null,
                borderRadius: BorderRadius.circular(DsRadius.md),
                child: Container(
                  constraints: const BoxConstraints(minWidth: 56, minHeight: 52),
                  padding: const EdgeInsets.symmetric(horizontal: DsSpace.s2, vertical: DsSpace.s1),
                  child: ExcludeSemantics(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        DsIcon(icon, size: 20, color: fg),
                        const SizedBox(height: 2),
                        Text(
                          label,
                          style: dsTextStyle(DsType.caption, fg).copyWith(
                            fontSize: 11,
                            fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({required this.color, required this.selected, required this.onTap});

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    return MergeSemantics(
      child: Semantics(
        button: true,
        selected: selected,
        label: '펜 색 ${_colorName(context, color)}',
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          // 터치 영역은 48dp. 점만 작게 그린다.
          child: SizedBox(
            width: 48,
            height: 40,
            child: Center(
              child: Container(
                width: selected ? 26 : 22,
                height: selected ? 26 : 22,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? p.brandText : p.borderSubtle,
                    width: selected ? 3 : 1,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _colorName(BuildContext context, Color c) {
    final p = DsTheme.of(context);
    if (c.toARGB32() == p.inkPenBlue.toARGB32()) return '파랑';
    if (c.toARGB32() == p.inkPenRed.toARGB32()) return '빨강';
    return '검정';
  }
}

// ── 상태 표시 ────────────────────────────────────────────────────────────

/// 저장 상태. 사용자가 앱을 닫아도 되는지 판단할 수 있는 유일한 단서다.
class _SaveIndicator extends StatelessWidget {
  const _SaveIndicator({required this.saving, required this.dirty});

  final bool saving;
  final bool dirty;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    final (String label, Widget mark) = saving
        ? (
            '저장하는 중',
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: p.textTertiary),
            )
          )
        : dirty
            ? ('저장 대기 중', DsIcon(DsIcons.info, size: 14, color: p.textTertiary))
            : ('저장됨', DsIcon(DsIcons.success, size: 14, color: p.statusSuccess));

    return Semantics(
      liveRegion: true,
      label: label,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: DsSpace.s4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 저장 표시는 필기하는 내내 눈 끝에 걸려 있다. 깜빡이면 손이 멈춘다.
              // 그래서 여기서는 아주 짧게, 이동 없이 밝기만 넘긴다.
              DsSwitcher(
                duration: DsMotion.fast,
                alignment: Alignment.center,
                travel: 0,
                child: KeyedSubtree(key: ValueKey(label), child: mark),
              ),
              const SizedBox(width: DsSpace.s1),
              DsSwitcher(
                duration: DsMotion.fast,
                alignment: Alignment.centerLeft,
                travel: 0,
                child: Text(label,
                    key: ValueKey(label), style: dsTextStyle(DsType.caption, p.textTertiary)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 다른 기기가 먼저 저장했을 때. 덮어쓰기를 멈추고 사용자에게 말한다.
/// 필기 저장이 멈췄다는 알림. 조용히 멈추면 사용자는 저장되고 있다고 믿는다.
/// 기기에 보관 중인 필기가 있다는 표시.
///
/// 경고가 아니라 안심시키는 문구다. 사용자가 알아야 할 것은 딱 하나 —
/// **필기는 남아 있고, 연결되면 알아서 올라간다.** 그걸 모르면 다시 그리거나 앱을 지운다.
class _SpooledBanner extends StatelessWidget {
  const _SpooledBanner();

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        color: p.brandPrimarySubtle,
        padding: const EdgeInsets.symmetric(horizontal: DsSpace.s4, vertical: DsSpace.s2),
        child: Row(
          children: [
            DsIcon(DsIcons.info, size: 16, color: p.brandTextOnSubtle),
            const SizedBox(width: DsSpace.s2),
            Expanded(
              child: Text(
                '필기를 이 기기에 보관해 뒀어요. 연결되면 자동으로 올려요.',
                style: dsTextStyle(DsType.caption, p.brandTextOnSubtle),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InkBlockedBanner extends StatelessWidget {
  const _InkBlockedBanner({required this.message, required this.onReload});

  final String message;
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        color: p.statusBgWarning,
        padding: const EdgeInsets.symmetric(horizontal: DsSpace.s4, vertical: DsSpace.s2),
        child: Row(
          children: [
            DsIcon(DsIcons.warning, size: 16, color: p.statusWarning),
            const SizedBox(width: DsSpace.s2),
            Expanded(
              child: Text(message, style: dsTextStyle(DsType.caption, p.textPrimary)),
            ),
            TextButton(onPressed: onReload, child: const Text('불러오기')),
          ],
        ),
      ),
    );
  }
}

/// 학습지 하나에 할 수 있는 일. 필기 중에는 잘 안 쓰므로 메뉴 뒤에 둔다 —
/// 툴바에 늘어놓으면 펜을 든 손이 잘못 누른다.
class _SheetMenu extends StatelessWidget {
  const _SheetMenu({
    required this.enabled,
    required this.onRename,
    required this.onPrint,
    required this.onDelete,
  });

  final bool enabled;
  final VoidCallback onRename;
  final VoidCallback onPrint;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    return PopupMenuButton<String>(
      enabled: enabled,
      tooltip: '학습지 메뉴',
      icon: DsIcon(DsIcons.more, size: 22, color: p.textSecondary, semanticLabel: '더 보기'),
      onSelected: (v) => switch (v) {
        'rename' => onRename(),
        'print' => onPrint(),
        _ => onDelete(),
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'rename', child: Text('제목 바꾸기')),
        const PopupMenuItem(value: 'print', child: Text('인쇄 · PDF로 저장')),
        PopupMenuItem(
          value: 'delete',
          // 위험한 것은 색만으로 알리지 않는다. 스크린리더에도 같은 말이 가야 한다.
          child: Text('학습지 지우기', style: TextStyle(color: p.statusDanger)),
        ),
      ],
    );
  }
}

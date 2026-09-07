import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:onpar_design_system/onpar_design_system.dart';

import '../../core/app_error.dart';
import '../../core/connectivity.dart';
import '../../core/logger.dart';
import '../../core/request_guard.dart';
import '../../core/routes.dart';
import '../../data/supabase.dart';
import '../../data/worksheet_repository.dart';
import '../../domain/models.dart';
import '../../ui/states/app_state_views.dart';
import '../../ui/widgets/feedback.dart';
import 'worksheet_response_mapping.dart';

/// 뷰어를 열기 위해 필요한 것 전부. 한 번에 모아서 받는다 —
/// 셋을 따로 받으면 "본문은 떴는데 필기가 안 붙는" 중간 상태가 생긴다.
class WorksheetViewData {
  const WorksheetViewData({
    required this.sheet,
    required this.url,
    required this.rev,
    required this.strokesPath,
  });

  final WorksheetSummary sheet;
  final String url;

  /// 필기 낙관적 잠금의 기준. 0 이면 아직 저장된 필기가 없다.
  final int rev;
  final String? strokesPath;
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

  final url = await repo.signedHtmlUrl(path);
  final meta = await repo.annotationMeta(id);
  return WorksheetViewData(sheet: sheet, url: url, rev: meta.rev, strokesPath: meta.path);
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
  bool _conflicted = false;

  /// 저장이 겹치지 않게. 두 저장이 같은 rev 로 나가면 하나는 반드시 충돌한다.
  Future<void>? _inFlightSave;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // TODO(analytics): worksheetOpen
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

    _pendingResponses[row['response_id']! as String] = row;
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

    _inkDirty = true;
    if (mounted &&
        (count != _strokeCount || canUndo != _canUndo || canRedo != _canRedo)) {
      setState(() {
        _strokeCount = count;
        _canUndo = canUndo;
        _canRedo = canRedo;
      });
    }
    _inkDebounce.run(() => unawaited(_flush(reason: 'ink')));
  }

  // ── 저장 ────────────────────────────────────────────────────────────

  /// 밀린 것을 지금 전부 올린다. 디바운스 타이머는 취소한다 — 두 번 올릴 이유가 없다.
  Future<void> _flush({required String reason}) {
    _responseDebounce.dispose();
    _inkDebounce.dispose();

    // 이미 저장 중이면 그게 끝난 뒤에 이어서 한 번 더 돈다.
    final running = _inFlightSave;
    final next = running == null ? _runSave(reason) : running.then((_) => _runSave(reason));
    _inFlightSave = next.whenComplete(() {
      if (identical(_inFlightSave, next)) _inFlightSave = null;
    });
    return _inFlightSave!;
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
    if (web == null || !_inkDirty || _conflicted) return;

    final json = await _exportStrokes(web);
    if (json == null) return;

    final userId = ref.read(currentUserProvider)?.id;
    if (userId == null) {
      _notify(AppError.of(AppErrorKind.unauthorized).message);
      return;
    }

    // TODO(storage): 이 JSON 을 gzip 해서 `annotations` 버킷의 strokesPath 로 올린다.
    //   지금은 메타(경로·획 수·크기·rev)만 기록한다. 업로드가 붙기 전까지 저장된 필기를
    //   다시 내려받을 수는 없다 — 그래서 loadStrokes 도 아직 부르지 않는다.
    final strokesPath = '$userId/${widget.worksheetId}.json';
    final bytes = utf8.encode(json).length;

    try {
      final next = await ref.read(worksheetRepositoryProvider).saveAnnotations(
            worksheetId: widget.worksheetId,
            strokesPath: strokesPath,
            strokeCount: _strokeCount,
            bytes: bytes,
            rev: _rev,
          );
      _rev = next;
      _inkDirty = false;
    } on AppError catch (e, st) {
      if (e.code == 'annotation_conflict') {
        // 다른 기기가 먼저 저장했다. 덮어쓰면 그쪽 필기가 말없이 사라진다 — 멈춘다.
        await _onAnnotationConflict(e);
        return;
      }
      AppLogger.error('필기 저장 실패', error: e, stack: st);
      _notify(e.message);
    } catch (e, st) {
      final err = AppError.from(e, st);
      AppLogger.error('필기 저장 실패', error: err, stack: st);
      _notify(err.message);
    }
  }

  /// 충돌. 자동으로 이기려 들지 않는다 — 필기를 지우는 건 되돌릴 수 없는 손상이다.
  Future<void> _onAnnotationConflict(AppError error) async {
    if (mounted) setState(() => _conflicted = true);
    try {
      final meta = await ref.read(worksheetRepositoryProvider).annotationMeta(widget.worksheetId);
      _rev = meta.rev;
      // TODO(storage): meta.path 에서 최신 스트로크를 내려받아
      //   `ONPAR_INK.loadStrokes(json)` 로 화면을 최신 상태로 맞춘다.
    } catch (e, st) {
      AppLogger.error('최신 필기 메타 조회 실패', error: AppError.from(e, st), stack: st);
    }
    _notify(error.message);
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
    setState(() {
      _tool = tool;
      if (color != null) _penColor = color;
    });

    final p = DsTheme.of(context);
    final args = switch (tool) {
      InkTool.none => {'tool': 'none'},
      InkTool.pen => {'tool': 'pen', 'color': _hex(_penColor ?? p.inkPen), 'width': 2.4},
      InkTool.highlighter => {'tool': 'highlighter', 'color': _hex(p.inkHighlighter), 'width': 16.0},
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
        if (mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: p.surfaceBase,
        appBar: AppBar(
          title: Text(view.valueOrNull?.sheet.displayTitle ?? '학습지'),
          actions: [_SaveIndicator(saving: _saving, dirty: _inkDirty || _pendingResponses.isNotEmpty)],
        ),
        body: SafeArea(
          child: Column(
            children: [
              if (offline) const OfflineBanner(),
              if (_conflicted) _ConflictBanner(onReload: _reloadEverything),
              Expanded(
                child: view.when(
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
      _conflicted = false;
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
          initialUrlRequest: URLRequest(url: WebUri(data.url)),
          initialSettings: InAppWebViewSettings(
            // 학습지는 우리가 만든 문서다. 바깥으로 나갈 일이 없다.
            javaScriptEnabled: true,
            supportZoom: true,
            transparentBackground: true,
            // 애플펜슬 필기는 WebView 안에서 한다. 브라우저 제스처가 가로채면 획이 끊긴다.
            disableLongPressContextMenuOnLinks: true,
            allowsInlineMediaPlayback: true,
          ),
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

            // TODO(storage): data.strokesPath 에서 저장된 필기를 내려받아
            //   `ONPAR_INK.loadStrokes(json)` 로 복원한다(다음 단계).

            final quizId = widget.quizId;
            if (quizId != null && quizId.isNotEmpty) {
              await _eval('window.ONPAR_INK.scrollToQuiz(${jsonEncode(quizId)})');
            }
          },
          onReceivedError: (c, request, error) {
            if (!mounted || !request.isForMainFrame!) return;
            setState(() => _pageError = AppError.of(
                  AppErrorKind.offline,
                  message: '학습지를 불러오지 못했어요. 연결을 확인하고 다시 시도해 주세요.',
                ));
          },
          onReceivedHttpError: (c, request, response) {
            if (!mounted || !(request.isForMainFrame ?? false)) return;
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
                    icon: DsIcons.zoomIn,
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
                    icon: DsIcons.profile,
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

    return Semantics(
      button: true,
      enabled: enabled,
      selected: selected,
      label: label,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.all(DsSpace.s1),
          child: Material(
            color: selected ? p.brandPrimarySubtle : Colors.transparent,
            borderRadius: BorderRadius.circular(DsRadius.md),
            child: InkWell(
              onTap: enabled ? onTap : null,
              borderRadius: BorderRadius.circular(DsRadius.md),
              child: Container(
                constraints: const BoxConstraints(minWidth: 56, minHeight: 52),
                padding: const EdgeInsets.symmetric(horizontal: DsSpace.s2, vertical: DsSpace.s1),
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
    return Semantics(
      button: true,
      selected: selected,
      label: '펜 색 ${_colorName(context, color)}',
      child: ExcludeSemantics(
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
                    color: selected ? p.brandPrimary : p.borderSubtle,
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
    final (label, widget) = saving
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
              widget,
              const SizedBox(width: DsSpace.s1),
              Text(label, style: dsTextStyle(DsType.caption, p.textTertiary)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 다른 기기가 먼저 저장했을 때. 덮어쓰기를 멈추고 사용자에게 말한다.
class _ConflictBanner extends StatelessWidget {
  const _ConflictBanner({required this.onReload});
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
              child: Text(
                '다른 기기에서 먼저 저장했어요. 최신 필기를 불러온 뒤 이어서 쓸 수 있어요.',
                style: dsTextStyle(DsType.caption, p.textPrimary),
              ),
            ),
            TextButton(onPressed: onReload, child: const Text('불러오기')),
          ],
        ),
      ),
    );
  }
}

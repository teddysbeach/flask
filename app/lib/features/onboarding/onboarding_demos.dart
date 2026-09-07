import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:onpar_design_system/onpar_design_system.dart';

/// 온보딩에서 쓰는 **동작하는 데모들.**
///
/// 온보딩이 스크린샷을 보여 주면 사용자는 그걸 광고로 읽는다. 그래서 여기 있는 넷은
/// 전부 실제로 움직이고, 셋째 장은 **실제로 그려진다** — 앱을 켠 지 30초 만에
/// 애플펜슬이 이 앱에서 어떻게 반응하는지 손끝으로 알게 하는 것이 목적이다.
/// 필압까지 그대로 받는다(`PointerEvent.pressure`). 그게 이 앱이 파는 것이기 때문이다.
///
/// 규칙 셋:
///
///   1. **보일 때만 돈다.** [PageView] 는 옆 장을 미리 만들어 두므로 `active` 가 없으면
///      보이지도 않는 데모가 배터리를 쓰고, 정작 도착했을 때는 이미 끝나 있다.
///   2. **동작 줄이기를 존중한다.** 켜져 있으면 완성된 마지막 상태를 그냥 보여 준다 —
///      데모를 못 보는 것과 아무것도 못 보는 것은 다르다.
///   3. **글자는 위젯으로 그린다.** 캔버스에 글자를 박으면 시스템 글꼴 크기를 안 따른다.

// ─────────────────────────────────────────────────────────────────────────────
// 공통
// ─────────────────────────────────────────────────────────────────────────────

/// 데모를 담는 종이. 넷이 같은 테두리·같은 그림자를 써야 "같은 앱 안" 으로 보인다.
class DemoFrame extends StatelessWidget {
  const DemoFrame({super.key, required this.child, this.padding, this.label});

  final Widget child;
  final EdgeInsets? padding;

  /// 스크린리더용 한 줄. 데모는 눈으로 보는 것이라 안쪽을 읽어 줘 봐야 소음이다.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    final card = Container(
      padding: padding ?? const EdgeInsets.all(DsSpace.s4),
      decoration: BoxDecoration(
        color: p.surfaceRaised,
        borderRadius: BorderRadius.circular(DsRadius.r2xl),
        border: Border.all(color: p.borderSubtle),
        boxShadow: DsShadow.md,
      ),
      child: child,
    );
    if (label == null) return card;
    return Semantics(label: label, child: ExcludeSemantics(child: card));
  }
}

/// 데모의 재생 상태를 [active] 와 동작 줄이기에 맞춘다.
///
/// 네 데모가 전부 같은 실수를 할 수 있는 자리라 한 곳에 모았다 — 안 보일 때 멈추기,
/// 다시 들어오면 처음부터, 동작 줄이기면 끝난 모습으로.
mixin _DemoPlayback<W extends StatefulWidget> on State<W> {
  bool get demoActive;

  /// 재생/정지의 실제 동작. 애니메이션 컨트롤러든 타이머든 여기서 갈린다.
  void onDemoPlay({required bool reduceMotion});
  void onDemoStop();

  bool _playing = false;

  void _syncPlayback() {
    final shouldPlay = demoActive;
    if (shouldPlay == _playing) return;
    _playing = shouldPlay;
    if (shouldPlay) {
      onDemoPlay(reduceMotion: dsReduceMotion(context));
    } else {
      onDemoStop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncPlayback();
  }

  @override
  void didUpdateWidget(covariant W oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPlayback();
  }
}

/// `[from, to]` 구간을 0‥1 로 편다. 하나의 타임라인에 여러 장면을 얹을 때 쓴다.
double _seg(double t, double from, double to, {Curve curve = DsCurve.standard}) {
  if (to <= from) return t >= to ? 1 : 0;
  return curve.transform(((t - from) / (to - from)).clamp(0.0, 1.0));
}

// ─────────────────────────────────────────────────────────────────────────────
// ① 주제를 적으면 학습지가 나온다
// ─────────────────────────────────────────────────────────────────────────────

const _kDemoTopic = '이차함수의 판별식';

/// 학습지 6단계. 실제 렌더러(`server/.../render.ts`)와 같은 순서·같은 아이콘이다.
const _kStages = <({List<String> icon, String name, String what})>[
  (icon: DsIcons.secProblem, name: '문제 제시', what: '개념 이름 대신, 아직 못 푸는 상황 하나로 시작해요.'),
  (icon: DsIcons.secPredict, name: '예측', what: '설명을 읽기 전에 먼저 답을 골라 봐요. 틀려도 괜찮아요.'),
  (icon: DsIcons.secObserve, name: '관찰', what: '예측이 맞았는지 증거로 확인해요. 여기서 “어?” 가 나와요.'),
  (icon: DsIcons.secConcept, name: '개념', what: '그제서야 개념을 설명해요. 궁금해진 뒤라 잘 붙어요.'),
  (icon: DsIcons.secPractice, name: '연습', what: '손으로 직접 풀어 봐요. 읽기만 한 것은 남지 않아요.'),
  (icon: DsIcons.secExitTicket, name: '나가기 전에', what: '한 문장으로 정리하고 끝내요.'),
];

/// 주제 한 줄 → 6단계 학습지. 타이핑부터 완성까지 한 바퀴를 반복한다.
class TopicToSheetDemo extends StatefulWidget {
  const TopicToSheetDemo({super.key, required this.active});

  final bool active;

  @override
  State<TopicToSheetDemo> createState() => _TopicToSheetDemoState();
}

class _TopicToSheetDemoState extends State<TopicToSheetDemo>
    with SingleTickerProviderStateMixin, _DemoPlayback<TopicToSheetDemo> {
  static const _loop = Duration(milliseconds: 7200);

  late final AnimationController _c =
      AnimationController(vsync: this, duration: _loop);

  @override
  bool get demoActive => widget.active;

  @override
  void onDemoPlay({required bool reduceMotion}) {
    if (reduceMotion) {
      _c.value = 1;
    } else {
      _c.repeat();
    }
  }

  @override
  void onDemoStop() {
    _c.stop();
    _c.value = 0;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    return DemoFrame(
      label: '주제를 입력하면 6단계 학습지가 만들어지는 과정을 보여 주는 그림',
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          final typed = (_seg(t, 0.06, 0.34, curve: Curves.linear) * _kDemoTopic.characters.length)
              .floor()
              .clamp(0, _kDemoTopic.characters.length);
          final text = _kDemoTopic.characters.take(typed).join();
          final typing = t > 0.06 && t < 0.42;
          // 커서는 0.5초에 한 번 깜빡인다. 타임라인 전체를 밀리초로 되돌려 센다.
          final caretOn = typing && ((t * _loop.inMilliseconds) ~/ 500).isEven;
          final press = _seg(t, 0.42, 0.46) - _seg(t, 0.46, 0.52);
          final started = t >= 0.46;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('무엇을 배우고 싶나요?', style: dsTextStyle(DsType.caption, p.textSecondary)),
              const SizedBox(height: DsSpace.s2),
              _MockField(text: text, caretOn: caretOn),
              const SizedBox(height: DsSpace.s3),
              Transform.scale(
                scale: 1 - (1 - DsMotion.pressScale) * press,
                child: _MockButton(enabled: typed == _kDemoTopic.characters.length),
              ),
              const SizedBox(height: DsSpace.s4),
              Divider(height: 1, color: p.borderSubtle),
              const SizedBox(height: DsSpace.s3),
              _ProgressLine(started: started, t: t),
              const SizedBox(height: DsSpace.s3),
              // 칩은 늘 자리에 있다. 뒤늦게 나타나면 카드 높이가 튀고,
              // 튀는 카드는 "만들어지는 중" 이 아니라 "덜 만든 화면" 으로 보인다.
              Wrap(
                spacing: DsSpace.s2,
                runSpacing: DsSpace.s2,
                children: [
                  for (var i = 0; i < _kStages.length; i++)
                    _StageChip(
                      stage: _kStages[i],
                      fill: _seg(t, 0.50 + i * 0.055, 0.50 + i * 0.055 + 0.09),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MockField extends StatelessWidget {
  const _MockField({required this.text, required this.caretOn});

  final String text;
  final bool caretOn;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: DsSpace.s3),
      decoration: BoxDecoration(
        color: p.surfaceSunken,
        borderRadius: BorderRadius.circular(DsRadius.xl),
        border: Border.all(color: text.isEmpty ? p.borderSubtle : p.borderFocus),
      ),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          Flexible(
            child: Text(
              text.isEmpty ? '예: 이차함수의 판별식' : text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: dsTextStyle(
                  DsType.bodyLg, text.isEmpty ? p.textPlaceholder : p.textPrimary),
            ),
          ),
          if (caretOn)
            Container(
              width: 2,
              height: 20,
              margin: const EdgeInsets.only(left: 1),
              color: p.brandText,
            ),
        ],
      ),
    );
  }
}

class _MockButton extends StatelessWidget {
  const _MockButton({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    return AnimatedContainer(
      duration: dsDuration(context, DsMotion.fast),
      curve: DsCurve.standard,
      height: 46,
      width: double.infinity,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: enabled ? p.brandPrimary : p.surfaceSunken,
        borderRadius: BorderRadius.circular(DsRadius.md),
      ),
      child: Text(
        '학습지 만들기',
        style: dsTextStyle(DsType.bodyLg, enabled ? p.brandOnPrimary : p.textDisabled)
            .copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// 생성 진행 문구. 실제 생성 화면과 같은 말을 쓴다 — 온보딩에서 본 문장을
/// 진짜로 만들 때 다시 만나면, 그 화면이 낯설지 않다.
class _ProgressLine extends StatelessWidget {
  const _ProgressLine({required this.started, required this.t});

  final bool started;
  final double t;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    final (String text, Color color) = !started
        ? ('주제를 기다리고 있어요', p.textTertiary)
        : t < 0.72
            ? ('학습지를 쓰고 있어요', p.textSecondary)
            : t < 0.86
                ? ('품질을 검사하고 있어요', p.textSecondary)
                : ('학습지가 준비됐어요', p.statusSuccess);
    return Row(
      children: [
        SizedBox(
          width: 16,
          height: 16,
          child: !started
              ? null
              : t < 0.86
                  ? CircularProgressIndicator(strokeWidth: 2, color: p.brandText)
                  : DsIcon(DsIcons.success, size: 16, color: p.statusSuccess),
        ),
        const SizedBox(width: DsSpace.s2),
        Expanded(child: Text(text, style: dsTextStyle(DsType.body, color))),
      ],
    );
  }
}

class _StageChip extends StatelessWidget {
  const _StageChip({required this.stage, required this.fill});

  final ({List<String> icon, String name, String what}) stage;
  final double fill;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    final on = fill > 0.5;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: DsSpace.s3, vertical: DsSpace.s2),
      decoration: BoxDecoration(
        color: Color.lerp(p.surfaceSunken, p.brandPrimarySubtle, fill),
        borderRadius: BorderRadius.circular(DsRadius.full),
        border: Border.all(color: Color.lerp(p.borderSubtle, p.brandPrimary, fill)!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DsIcon(stage.icon, size: 15, color: Color.lerp(p.textDisabled, p.brandText, fill)!),
          const SizedBox(width: DsSpace.s1),
          Text(stage.name,
              style: dsTextStyle(
                  DsType.caption, Color.lerp(p.textTertiary, p.textPrimary, fill)!)),
          if (on) ...[
            const SizedBox(width: DsSpace.s1),
            DsIcon(DsIcons.success, size: 13, color: p.statusSuccess),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ② 학습지는 이렇게 생겼다
// ─────────────────────────────────────────────────────────────────────────────

/// 6단계를 한 칸씩 짚어 가며 "왜 이 순서인지" 를 말한다.
///
/// 이 앱이 문제집과 다른 지점이 여기 하나라, 온보딩에서 유일하게 **가르치는** 장이다.
class WorksheetAnatomyDemo extends StatefulWidget {
  const WorksheetAnatomyDemo({super.key, required this.active});

  final bool active;

  @override
  State<WorksheetAnatomyDemo> createState() => _WorksheetAnatomyDemoState();
}

class _WorksheetAnatomyDemoState extends State<WorksheetAnatomyDemo>
    with _DemoPlayback<WorksheetAnatomyDemo> {
  static const _dwell = Duration(milliseconds: 1900);

  Timer? _timer;
  int _focus = 0;

  @override
  bool get demoActive => widget.active;

  @override
  void onDemoPlay({required bool reduceMotion}) {
    setState(() => _focus = 0);
    if (reduceMotion) return; // 첫 칸을 짚은 채로 멈춘다. 설명은 그대로 읽힌다.
    _timer = Timer.periodic(_dwell, (_) {
      if (mounted) setState(() => _focus = (_focus + 1) % _kStages.length);
    });
  }

  @override
  void onDemoStop() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DemoFrame(
          label: '학습지 6단계 구조를 차례로 짚어 주는 그림',
          padding: const EdgeInsets.symmetric(vertical: DsSpace.s3, horizontal: DsSpace.s3),
          child: Column(
            children: [
              for (var i = 0; i < _kStages.length; i++)
                _AnatomyRow(stage: _kStages[i], focused: i == _focus, index: i),
            ],
          ),
        ),
        const SizedBox(height: DsSpace.s4),
        // 설명은 카드 밖에 둔다. 안에 넣으면 카드 높이가 문장 길이를 따라 흔들린다.
        SizedBox(
          height: 56,
          child: DsSwitcher(
            child: Column(
              key: ValueKey(_focus),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_kStages[_focus].name,
                    style: dsTextStyle(DsType.body, p.brandText)
                        .copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: DsSpace.s1),
                Text(_kStages[_focus].what,
                    style: dsTextStyle(DsType.body, p.textSecondary)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AnatomyRow extends StatelessWidget {
  const _AnatomyRow({required this.stage, required this.focused, required this.index});

  final ({List<String> icon, String name, String what}) stage;
  final bool focused;
  final int index;

  /// 칸마다 글줄 수를 달리 둔다. 전부 같으면 학습지가 아니라 목록으로 보인다.
  static const _lines = [1, 2, 2, 3, 2, 1];

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    final d = dsDuration(context, DsMotion.base);
    return AnimatedContainer(
      duration: d,
      curve: DsCurve.standard,
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: DsSpace.s2, vertical: DsSpace.s2),
      decoration: BoxDecoration(
        color: focused ? p.brandPrimarySubtle : Colors.transparent,
        borderRadius: BorderRadius.circular(DsRadius.lg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedContainer(
            duration: d,
            curve: DsCurve.standard,
            width: 3,
            height: 14.0 + _lines[index] * 7,
            margin: const EdgeInsets.only(right: DsSpace.s2, top: 2),
            decoration: BoxDecoration(
              color: focused ? p.brandPrimary : Colors.transparent,
              borderRadius: BorderRadius.circular(DsRadius.full),
            ),
          ),
          DsIcon(stage.icon, size: 15, color: focused ? p.brandText : p.textTertiary),
          const SizedBox(width: DsSpace.s2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stage.name,
                  style: dsTextStyle(
                    DsType.caption,
                    focused ? p.textPrimary : p.textTertiary,
                  ).copyWith(fontWeight: focused ? FontWeight.w700 : FontWeight.w400),
                ),
                const SizedBox(height: 5),
                for (var l = 0; l < _lines[index]; l++)
                  AnimatedContainer(
                    duration: d,
                    curve: DsCurve.standard,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 4),
                    // 마지막 줄은 짧게. 글이 문단처럼 보이는 최소한의 장치다.
                    width: l == _lines[index] - 1 ? 88 : double.infinity,
                    decoration: BoxDecoration(
                      color: focused ? p.borderStrong : p.borderSubtle,
                      borderRadius: BorderRadius.circular(DsRadius.full),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ③ 손으로 푼다 — 실제로 그려지는 데모
// ─────────────────────────────────────────────────────────────────────────────

/// 데모 필기의 한 획. 실제 필기 런타임의 스트로크를 앱 쪽 위젯으로 줄인 것이다.
///
/// 굵기를 점마다 따로 갖는 이유: 애플펜슬은 **누르는 세기**를 보내고, 그걸 굵기로
/// 바꾸는 것이 이 앱이 종이와 겨루는 유일한 지점이다. 온보딩에서 그게 안 보이면
/// 사용자는 "웹뷰에 그림 그리는 앱" 으로 기억한다.
class InkDemoStroke {
  InkDemoStroke({required this.color, required this.highlighter});

  final List<Offset> pts = [];
  final List<double> widths = [];
  final Color color;
  final bool highlighter;

  void add(Offset p, double w) {
    pts.add(p);
    widths.add(w);
  }

  bool near(Offset p, double r) {
    for (final q in pts) {
      if ((q - p).distanceSquared <= r * r) return true;
    }
    return false;
  }
}

enum _DemoTool { pen, highlighter, eraser }

/// 그릴 수 있는 면. 테스트가 "여기를 문질러라" 라고 가리킬 곳이 필요하다 —
/// `CustomPaint` 로 찾으면 Material 이 내부에 쓰는 것들까지 걸린다.
const inkDemoCanvasKey = Key('onboarding-ink-canvas');

/// 데모 필기칸에 담긴 것.
///
/// 위젯에서 떼어 둔 이유는 하나다 — **손짓이 정말로 획이 되었는지는 화면 없이도 잴 수 있어야
/// 한다.** 예전에는 "안내 문구가 사라졌는가" 로 갈음했는데, 그건 손가락이 닿았다는 뜻일 뿐
/// 선이 그려졌다는 뜻이 아니다. 점 이동을 통째로 무시해도 그 검사는 통과했다.
class InkDemoStrokes extends ChangeNotifier {
  final List<InkDemoStroke> _seed = [];
  final List<InkDemoStroke> _user = [];
  InkDemoStroke? _drawing;

  /// 제자리에서 바뀌는 목록이라 `old != new` 로는 아무것도 못 잰다.
  /// 바뀔 때마다 올라가는 번호 하나가 화가에게 줄 수 있는 유일한 신호다.
  int _revision = 0;
  int get revision => _revision;

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  List<InkDemoStroke> get seed => _seed;
  List<InkDemoStroke> get user => _user;

  /// 사용자가 담은 점의 수. 이 값이 안 오르면 필기칸은 죽은 것이다.
  int get userPoints => _user.fold(0, (n, s) => n + s.pts.length);
  int get strokeCount => _seed.length + _user.length;
  bool get isEmpty => _seed.isEmpty && _user.isEmpty;
  bool get userDrew => _user.isNotEmpty;

  /// 사용자가 이 종이에 **손을 댔는가** (그었든, 지웠든, 전부 지웠든).
  ///
  /// 이걸 안 세면 미리 쓰인 손글씨가 되살아난다. 크기가 정해질 때마다 씨앗을 다시 앉히는데,
  /// "씨앗 목록이 비었다" 를 기준으로 삼으면 **전체 지우기 바로 다음 프레임에 다시 나타난다** —
  /// 지운 것이 돌아오는 것만큼 앱을 못 믿게 만드는 일도 없다.
  bool _userTouched = false;
  bool get userTouched => _userTouched;

  void _bump() {
    _revision++;
    notifyListeners();
  }

  void seedWith(List<InkDemoStroke> strokes) {
    _seed
      ..clear()
      ..addAll(strokes);
    _revision++;
    // 씨앗은 **레이아웃 도중에** 만들어진다 — 필기칸의 실제 크기를 알아야 글자를 앉힐 수
    // 있기 때문이다. 그 자리에서 알리면 "빌드 중 setState" 로 프레임이 깨진다.
    // 그림 자체는 같은 프레임에 이미 나가므로 **알림만** 다음 프레임으로 미룬다.
    // 이 알림을 듣는 것은 '전체 지우기' 버튼 하나뿐이다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed) notifyListeners();
    });
  }

  void begin(Offset at, double width, {required Color color, required bool highlighter}) {
    _userTouched = true;
    _drawing = InkDemoStroke(color: color, highlighter: highlighter)..add(at, width);
    _user.add(_drawing!);
    _bump();
  }

  void extend(Offset at, double width) {
    final s = _drawing;
    if (s == null) return;
    // 1px 이하로 촘촘한 점은 굵기 계산만 흔들고 그림은 그대로다.
    if (s.pts.isNotEmpty && (s.pts.last - at).distance < 1.2) return;
    s.add(at, width);
    _bump();
  }

  void end() => _drawing = null;

  void eraseAt(Offset at, double radius) {
    _userTouched = true;
    final before = strokeCount;
    _user.removeWhere((s) => s.near(at, radius));
    _seed.removeWhere((s) => s.near(at, radius));
    if (strokeCount != before) _bump();
  }

  void clear() {
    _userTouched = true;
    _user.clear();
    _seed.clear();
    _drawing = null;
    _bump();
  }
}

/// 진짜로 그려지는 필기칸.
///
/// 처음 들어오면 손글씨 답이 저절로 쓰인다(빈 종이는 무엇을 하라는 건지 알려 주지 않는다).
/// 그 뒤부터는 사용자 차례다 — 지우고, 형광펜을 긋고, 전부 지울 수 있다.
class InkDemo extends StatefulWidget {
  const InkDemo({super.key, required this.active, this.onFirstStroke, this.strokes});

  final bool active;

  /// 밖에서 넘기면 그것을 쓴다. 안 넘기면 스스로 만든다 —
  /// `TextField` 가 `TextEditingController` 를 다루는 방식과 같다.
  final InkDemoStrokes? strokes;

  /// 사용자가 **직접** 한 획이라도 그었을 때 한 번. 온보딩에서 이걸 한 사람과
  /// 안 한 사람의 다음 행동이 다르므로, 그 사실만 센다(획 자체는 어디로도 안 나간다).
  final VoidCallback? onFirstStroke;

  @override
  State<InkDemo> createState() => _InkDemoState();
}

class _InkDemoState extends State<InkDemo>
    with SingleTickerProviderStateMixin, _DemoPlayback<InkDemo> {
  late final AnimationController _seedAnim =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));

  late final InkDemoStrokes _strokes = widget.strokes ?? InkDemoStrokes();
  bool get _ownsStrokes => widget.strokes == null;

  _DemoTool _tool = _DemoTool.pen;

  /// 씨앗을 앉힌 크기. 회전 등으로 크기가 바뀌면 다시 앉힌다 — 단, 사용자가
  /// 손을 대기 전까지만이다.
  Size _seededFor = Size.zero;
  bool _reportedFirstStroke = false;

  @override
  bool get demoActive => widget.active;

  @override
  void onDemoPlay({required bool reduceMotion}) {
    if (reduceMotion) {
      _seedAnim.value = 1;
    } else if (_seedAnim.value < 1) {
      _seedAnim.forward();
    }
  }

  @override
  void onDemoStop() {
    // 되감지 않는다. 사용자가 쓴 것을 남겨 둔 채 돌아오면 "내가 쓴 게 그대로 있다" 가 되고,
    // 그 작은 신뢰가 이 앱이 필기를 다루는 방식 전체에 대한 첫 증거다.
    _seedAnim.stop();
  }

  @override
  void dispose() {
    _seedAnim.dispose();
    if (_ownsStrokes) _strokes.dispose();
    super.dispose();
  }

  double _widthFor(PointerEvent e) {
    if (_tool == _DemoTool.highlighter) return 16;
    // 필압. 못 주는 기기(손가락·구형 기기)는 min == max 로 오므로 중간값을 쓴다.
    final span = e.pressureMax - e.pressureMin;
    final norm = span > 0.01 ? ((e.pressure - e.pressureMin) / span).clamp(0.0, 1.0) : 0.5;
    return 2.4 * (0.55 + 0.95 * norm);
  }

  void _down(PointerDownEvent e) {
    if (_tool == _DemoTool.eraser) {
      _strokes.eraseAt(e.localPosition, 14);
      return;
    }
    final p = DsTheme.of(context);
    _strokes.begin(
      e.localPosition,
      _widthFor(e),
      color: _tool == _DemoTool.highlighter ? p.inkHighlighter : p.inkPen,
      highlighter: _tool == _DemoTool.highlighter,
    );
    if (!_reportedFirstStroke) {
      _reportedFirstStroke = true;
      widget.onFirstStroke?.call();
    }
  }

  void _move(PointerMoveEvent e) {
    if (_tool == _DemoTool.eraser) {
      _strokes.eraseAt(e.localPosition, 14);
      return;
    }
    _strokes.extend(e.localPosition, _widthFor(e));
  }

  /// 미리 쓰인 답. 크기가 정해진 뒤에야 만들 수 있어서 레이아웃 단계에서 부른다.
  void _buildSeed(Size size) {
    if (_seededFor == size || _strokes.userTouched) return;
    _seededFor = size;
    _strokes.seedWith(_seedStrokes(size, DsTheme.of(context)));
  }

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    return ListenableBuilder(
      listenable: _strokes,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _InkToolbar(
            tool: _tool,
            onTool: (t) => setState(() => _tool = t),
            onClear: _strokes.clear,
            canClear: !_strokes.isEmpty,
          ),
          const SizedBox(height: DsSpace.s2),
          DemoFrame(
            padding: EdgeInsets.zero,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(DsRadius.r2xl),
              child: SizedBox(
                height: 188,
                child: LayoutBuilder(
                  builder: (context, c) {
                    final size = Size(c.maxWidth, c.maxHeight);
                    _buildSeed(size);
                    Widget ink({required bool highlighter}) => AnimatedBuilder(
                          animation: _seedAnim,
                          builder: (context, _) => CustomPaint(
                            painter: _InkPainter(
                              seed: _strokes.seed,
                              user: _strokes.user,
                              seedProgress: _seedAnim.value,
                              revision: _strokes.revision,
                              highlighter: highlighter,
                            ),
                            size: Size.infinite,
                          ),
                        );

                    return Stack(
                      children: [
                        // 형광펜 → 인쇄 → 펜. 종이에서 보이는 순서 그대로다.
                        Positioned.fill(child: ink(highlighter: true)),
                        const Positioned.fill(child: _PrintedQuestion()),
                        Positioned.fill(
                          child: Listener(
                            key: inkDemoCanvasKey,
                            onPointerDown: _down,
                            onPointerMove: _move,
                            onPointerUp: (_) => _strokes.end(),
                            onPointerCancel: (_) => _strokes.end(),
                            behavior: HitTestBehavior.opaque,
                            child: ink(highlighter: false),
                          ),
                        ),
                        if (!_strokes.userDrew)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: DsSpace.s3,
                            child: IgnorePointer(
                              child: Text(
                                '여기에 직접 써 보세요',
                                textAlign: TextAlign.center,
                                style: dsTextStyle(DsType.caption, p.textPlaceholder),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 인쇄된 문제와 밑줄. 실제 학습지의 `.ink-space` 와 같은 모양이다.
class _PrintedQuestion extends StatelessWidget {
  const _PrintedQuestion();

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(DsSpace.s4, DsSpace.s4, DsSpace.s4, DsSpace.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              DsIcon(DsIcons.activity, size: 14, color: p.brandText),
              const SizedBox(width: DsSpace.s1),
              Text('직접 계산해 보세요',
                  style: dsTextStyle(DsType.caption, p.brandText)
                      .copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: DsSpace.s2),
          Text('y = x² − 4x + 1 의 꼭짓점은?',
              style: dsTextStyle(DsType.bodyLg, p.textPrimary)),
          const SizedBox(height: DsSpace.s4),
          // 필기용 밑줄 두 줄.
          for (var i = 0; i < 2; i++) ...[
            Container(height: 1, color: p.borderSubtle),
            if (i == 0) const SizedBox(height: 38),
          ],
        ],
      ),
    );
  }
}

class _InkToolbar extends StatelessWidget {
  const _InkToolbar({
    required this.tool,
    required this.onTool,
    required this.onClear,
    required this.canClear,
  });

  final _DemoTool tool;
  final ValueChanged<_DemoTool> onTool;
  final VoidCallback onClear;

  /// 지울 것이 하나도 없을 때 '전체 지우기' 는 꺼진다.
  /// 눌러도 아무 일이 없는 버튼을 두지 않는 것이 이 저장소의 규칙이다.
  final bool canClear;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(DsSpace.s1),
      decoration: BoxDecoration(
        color: p.surfaceSunken,
        borderRadius: BorderRadius.circular(DsRadius.full),
        border: Border.all(color: p.borderSubtle),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _ToolPill(
              icon: DsIcons.pen,
              label: '펜',
              selected: tool == _DemoTool.pen,
              onTap: () => onTool(_DemoTool.pen)),
          _ToolPill(
              icon: DsIcons.highlighter,
              label: '형광펜',
              selected: tool == _DemoTool.highlighter,
              onTap: () => onTool(_DemoTool.highlighter)),
          _ToolPill(
              icon: DsIcons.eraser,
              label: '지우개',
              selected: tool == _DemoTool.eraser,
              onTap: () => onTool(_DemoTool.eraser)),
          _ToolPill(
            icon: DsIcons.clearAll,
            label: '전체 지우기',
            selected: false,
            enabled: canClear,
            onTap: onClear,
          ),
        ],
      ),
    );
  }
}

class _ToolPill extends StatelessWidget {
  const _ToolPill({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  final List<String> icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    final fg = !enabled
        ? p.textDisabled
        : selected
            ? p.brandOnPrimary
            : p.textSecondary;
    return Semantics(
      button: true,
      enabled: enabled,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(DsRadius.full),
        child: AnimatedContainer(
          duration: dsDuration(context, DsMotion.fast),
          curve: DsCurve.standard,
          // 손끝이 닿는 최소 크기를 여기서 줄이지 않는다.
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: DsSpace.s3, vertical: DsSpace.s2),
          decoration: BoxDecoration(
            color: selected ? p.brandPrimary : Colors.transparent,
            borderRadius: BorderRadius.circular(DsRadius.full),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DsIcon(icon, size: 16, color: fg),
              const SizedBox(width: DsSpace.s1),
              ExcludeSemantics(
                child: Text(label,
                    style: dsTextStyle(DsType.caption, fg)
                        .copyWith(fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InkPainter extends CustomPainter {
  _InkPainter({
    required this.seed,
    required this.user,
    required this.seedProgress,
    required this.revision,
    required this.highlighter,
  });

  /// 형광펜 층인가, 펜 층인가.
  ///
  /// 둘을 한 캔버스에 그리면 형광펜이 **인쇄된 글자를 덮어** 문제가 안 읽힌다.
  /// 반투명을 아무리 낮춰도 글자 획이 뿌옇게 된다 — 종이에서는 형광펜이 잉크를
  /// 가리지 않으니, 화면에서도 글자 아래에 깔아야 같은 그림이 된다.
  final bool highlighter;

  final List<InkDemoStroke> seed;
  final List<InkDemoStroke> user;
  final double seedProgress;

  /// 획 목록은 **제자리에서** 바뀐다(점 하나마다 리스트를 새로 만들면 손이 느려진다).
  /// 그래서 `old.user != user` 로는 아무것도 못 잰다 — 같은 객체이기 때문이다.
  /// 바뀔 때마다 올라가는 번호 하나가 유일하게 믿을 수 있는 신호다.
  final int revision;

  @override
  void paint(Canvas canvas, Size size) {
    final total = seed.fold<int>(0, (n, s) => n + s.pts.length);
    final budget = (total * seedProgress).round();

    // 씨앗 획이 어디까지 드러났는지 미리 센다.
    final takes = <int>[];
    var used = 0;
    for (final s in seed) {
      takes.add((budget - used).clamp(0, s.pts.length));
      used += s.pts.length;
    }

    for (var i = 0; i < seed.length; i++) {
      if (seed[i].highlighter == highlighter) _drawStroke(canvas, seed[i], takes[i]);
    }
    for (final s in user) {
      if (s.highlighter == highlighter) _drawStroke(canvas, s, s.pts.length);
    }
  }

  void _drawStroke(Canvas canvas, InkDemoStroke s, int take) {
    if (take < 2) return;
    final paint = Paint()
      ..color = s.highlighter ? s.color.withValues(alpha: 0.55) : s.color
      ..strokeCap = s.highlighter ? StrokeCap.square : StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < take - 1; i++) {
      paint.strokeWidth = (s.widths[i] + s.widths[i + 1]) / 2;
      canvas.drawLine(s.pts[i], s.pts[i + 1], paint);
    }
  }

  @override
  bool shouldRepaint(covariant _InkPainter old) =>
      old.revision != revision ||
      old.seedProgress != seedProgress ||
      old.highlighter != highlighter;
}

/// 미리 쓰인 손글씨. 형광펜으로 식을 긋고, 밑줄 위에 `(2, −3)` 이라고 쓴다.
///
/// 베지에로 그린 뒤 점으로 잘게 나눈다. 그래야 지우개·필압·부분 노출이
/// 사용자가 그은 획과 **똑같은 방식으로** 다뤄진다 — 데모용 특례를 만들지 않는다.
List<InkDemoStroke> _seedStrokes(Size s, DsPalette p) {
  final out = <InkDemoStroke>[];

  // 형광펜: 문제의 식 위를 지난다.
  final hl = InkDemoStroke(color: p.inkHighlighter, highlighter: true);
  final hlY = s.height * 0.285;
  for (var i = 0; i <= 40; i++) {
    final f = i / 40;
    hl.add(
      Offset(s.width * (0.055 + 0.575 * f), hlY + math.sin(f * math.pi) * -1.6),
      18,
    );
  }
  out.add(hl);

  // 펜: 밑줄 위의 답.
  final h = s.height * 0.20;
  final top = s.height * 0.60;
  var x = s.width * 0.10;
  double u(double v) => v * h;

  InkDemoStroke pen() => InkDemoStroke(color: p.inkPen, highlighter: false);

  void emit(Path path, double advance) {
    final stroke = pen();
    for (final m in path.computeMetrics()) {
      final steps = math.max(2, (m.length / 2).round());
      for (var i = 0; i <= steps; i++) {
        final t = m.getTangentForOffset(m.length * i / steps);
        if (t == null) continue;
        // 손으로 쓴 굵기. 획 중간이 굵고 끝이 가늘어야 종이처럼 보인다.
        final f = i / steps;
        stroke.add(t.position, 1.7 + 1.5 * math.sin(f * math.pi));
      }
    }
    if (stroke.pts.length >= 2) out.add(stroke);
    x += advance + u(0.16);
  }

  Path at(void Function(Path path, double Function(double) uu, double x0, double y0) build) {
    final path = Path();
    build(path, u, x, top);
    return path;
  }

  // (
  emit(at((q, uu, x0, y0) {
    q.moveTo(x0 + uu(.55), y0 + uu(.02));
    q.cubicTo(x0 + uu(.10), y0 + uu(.22), x0 + uu(.10), y0 + uu(.78), x0 + uu(.55), y0 + uu(.98));
  }), u(.55));

  // 2
  emit(at((q, uu, x0, y0) {
    q.moveTo(x0 + uu(.05), y0 + uu(.28));
    q.cubicTo(x0 + uu(.10), y0 + uu(.02), x0 + uu(.62), y0 + uu(.02), x0 + uu(.60), y0 + uu(.34));
    q.cubicTo(x0 + uu(.58), y0 + uu(.60), x0 + uu(.22), y0 + uu(.72), x0 + uu(.04), y0 + uu(.98));
    q.lineTo(x0 + uu(.64), y0 + uu(.96));
  }), u(.68));

  // ,
  emit(at((q, uu, x0, y0) {
    q.moveTo(x0 + uu(.16), y0 + uu(.86));
    q.cubicTo(x0 + uu(.20), y0 + uu(.95), x0 + uu(.14), y0 + uu(1.10), x0 + uu(.02), y0 + uu(1.18));
  }), u(.26));

  // −
  emit(at((q, uu, x0, y0) {
    q.moveTo(x0 + uu(.02), y0 + uu(.62));
    q.lineTo(x0 + uu(.46), y0 + uu(.575));
  }), u(.50));

  // 3
  emit(at((q, uu, x0, y0) {
    q.moveTo(x0 + uu(.06), y0 + uu(.16));
    q.cubicTo(x0 + uu(.30), y0 - uu(.04), x0 + uu(.68), y0 + uu(.14), x0 + uu(.36), y0 + uu(.46));
    q.cubicTo(x0 + uu(.76), y0 + uu(.46), x0 + uu(.70), y0 + uu(1.02), x0 + uu(.10), y0 + uu(.90));
  }), u(.70));

  // )
  emit(at((q, uu, x0, y0) {
    q.moveTo(x0 + uu(.05), y0 + uu(.02));
    q.cubicTo(x0 + uu(.50), y0 + uu(.22), x0 + uu(.50), y0 + uu(.78), x0 + uu(.05), y0 + uu(.98));
  }), u(.55));

  return out;
}

// ─────────────────────────────────────────────────────────────────────────────
// ④ 잊을 때쯤 다시 물어본다
// ─────────────────────────────────────────────────────────────────────────────

/// 복습 회차. `docs/plan/07-review-notifications.md` 의 기본 간격 그대로다.
const _kReviewDays = <int>[1, 3, 7, 16, 35];
const _kSpan = 35.0;

/// 망각곡선 두 줄.
///
/// 이 앱이 "학습지를 만들어 주는 앱" 이 아니라 "안 잊게 해 주는 앱" 이라는 것을
/// 문장으로 백 번 말하는 것보다 이 그림 하나가 빠르다. 두 줄의 차이가 곧 제품이다.
///
/// 색만으로 구분하지 않는다 — 실선/점선과 직접 라벨을 함께 둔다.
class ReviewCurveDemo extends StatefulWidget {
  const ReviewCurveDemo({super.key, required this.active});

  final bool active;

  @override
  State<ReviewCurveDemo> createState() => _ReviewCurveDemoState();
}

class _ReviewCurveDemoState extends State<ReviewCurveDemo>
    with SingleTickerProviderStateMixin, _DemoPlayback<ReviewCurveDemo> {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 5600));

  @override
  bool get demoActive => widget.active;

  @override
  void onDemoPlay({required bool reduceMotion}) {
    if (reduceMotion) {
      _c.value = 1;
    } else {
      _c.repeat();
    }
  }

  @override
  void onDemoStop() {
    _c.stop();
    _c.value = 0;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _CurveLegend(),
        const SizedBox(height: DsSpace.s2),
        DemoFrame(
          label: '복습을 하면 기억이 유지되고, 하지 않으면 빠르게 흐려지는 것을 보여 주는 그래프',
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              // 0.72 까지 그림이 그려지고, 나머지는 완성된 그림을 보는 시간이다.
              final draw = _seg(_c.value, 0.02, 0.72, curve: Curves.easeInOut);
              return SizedBox(
                height: 168,
                child: LayoutBuilder(
                  builder: (context, c) {
                    const labelH = 20.0;
                    final plot = Size(c.maxWidth, c.maxHeight - labelH);
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          left: 0,
                          top: 0,
                          width: plot.width,
                          height: plot.height,
                          child: CustomPaint(
                            painter: _CurvePainter(palette: p, progress: draw),
                          ),
                        ),
                        // 날짜는 위젯으로 둔다. 캔버스에 박으면 글꼴 크기 설정을 안 따른다.
                        for (final d in _kReviewDays)
                          Positioned(
                            left: _CurvePainter.xOf(d.toDouble(), plot.width) - 20,
                            top: plot.height + 3,
                            width: 40,
                            child: Opacity(
                              opacity: draw >= _CurvePainter.fracOf(d.toDouble()) ? 1 : 0,
                              child: Text('$d일',
                                  textAlign: TextAlign.center,
                                  style: dsTextStyle(DsType.caption, p.textTertiary)),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              );
            },
          ),
        ),
        const SizedBox(height: DsSpace.s3),
        // 알림은 위에서 내려온다. 실제 알림이 그렇게 온다.
        AnimatedBuilder(
          animation: _c,
          builder: (context, child) {
            final show = _c.value > 0.78;
            final d = dsDuration(context, DsMotion.slow);
            return AnimatedSlide(
              offset: show ? Offset.zero : const Offset(0, -0.3),
              duration: d,
              curve: DsCurve.enter,
              child: AnimatedOpacity(
                opacity: show ? 1 : 0,
                duration: d,
                curve: DsCurve.enter,
                child: child,
              ),
            );
          },
          child: const _MockNotification(),
        ),
      ],
    );
  }
}

class _CurveLegend extends StatelessWidget {
  const _CurveLegend();

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _LegendItem(color: p.brandText, dashed: false, label: '복습하면'),
        const SizedBox(width: DsSpace.s4),
        _LegendItem(color: p.textTertiary, dashed: true, label: '복습 안 하면'),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.dashed, required this.label});

  final Color color;
  final bool dashed;
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 20,
          height: 2,
          child: CustomPaint(painter: _SwatchPainter(color: color, dashed: dashed)),
        ),
        const SizedBox(width: DsSpace.s2),
        // 글자는 글자 색을 쓴다. 선 색을 글자에 입히면 대비가 무너진다.
        Text(label, style: dsTextStyle(DsType.caption, p.textSecondary)),
      ],
    );
  }
}

class _SwatchPainter extends CustomPainter {
  const _SwatchPainter({required this.color, required this.dashed});

  final Color color;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    if (!dashed) {
      canvas.drawLine(Offset(0, size.height / 2), Offset(size.width, size.height / 2), paint);
      return;
    }
    for (var x = 0.0; x < size.width; x += 6) {
      canvas.drawLine(
          Offset(x, size.height / 2), Offset(math.min(x + 3, size.width), size.height / 2), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SwatchPainter old) =>
      old.color != color || old.dashed != dashed;
}

class _CurvePainter extends CustomPainter {
  const _CurvePainter({required this.palette, required this.progress});

  final DsPalette palette;
  final double progress;

  /// 마지막 표시와 날짜 글자가 오른쪽 끝에서 잘리지 않도록 남기는 여백.
  static const pad = 14.0;

  /// 날짜를 가로 위치로. 1·3·7일이 왼쪽 끝에 뭉치지 않도록 로그로 편다.
  static double xOf(double day, double width) =>
      pad + (width - pad * 2) * math.log(1 + day) / math.log(1 + _kSpan);

  /// 0‥1 로 본 가로 위치. 날짜 글자를 언제 보일지 정할 때 쓴다.
  static double fracOf(double day) => math.log(1 + day) / math.log(1 + _kSpan);

  /// 복습하지 않았을 때의 기억률. 에빙하우스의 모양(처음에 급히 떨어지고 길게 눕는다)을
  /// 멱함수로 근사한다. 지수함수로 두면 사흘 만에 바닥에 붙어 그래프가 아무 말도 안 한다.
  static double _decayOnly(double day) => math.pow(1 + day, -0.62).toDouble();

  /// 복습했을 때의 기억률.
  ///
  /// **첫 복습 전에는 복습을 안 한 것과 똑같다.** 두 줄이 거기서 겹쳐 있다가 갈라지는 것이
  /// 이 그림의 전부다 — 처음부터 벌어져 있으면 "원래 다른 사람" 이야기가 된다.
  /// 복습할 때마다 기억이 버티는 시간(stability)이 곱으로 늘어난다. 간격을 1·3·7·16·35일로
  /// 벌리는 근거가 그것이다.
  static double _retention(double day) {
    var last = 0.0;
    var reviews = 0;
    for (final r in _kReviewDays) {
      if (day < r) break;
      last = r.toDouble();
      reviews++;
    }
    if (reviews == 0) return _decayOnly(day);
    final stability = 1.6 * math.pow(2.4, reviews).toDouble();
    return math.exp(-(day - last) / stability);
  }

  double _yOf(double retention, double height) => height * (1 - retention) * 0.92 + 2;

  @override
  void paint(Canvas canvas, Size size) {
    // 가로축이 로그라, 날짜로 진행시키면 앞부분이 순식간에 지나간다.
    final maxDay = math.exp(progress * math.log(1 + _kSpan)) - 1;
    if (maxDay <= 0) return;

    // 바닥선. 눈에 띄면 안 되지만 없으면 곡선이 허공에 뜬다.
    canvas.drawLine(
      Offset(pad, size.height),
      Offset(size.width - pad, size.height),
      Paint()
        ..color = palette.borderSubtle
        ..strokeWidth = 1,
    );

    Path build(double Function(double) f) {
      final path = Path();
      for (var i = 0; i <= 220; i++) {
        final day = maxDay * i / 220;
        final o = Offset(xOf(day, size.width), _yOf(f(day), size.height));
        i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
      }
      return path;
    }

    // ── 복습 안 하면 (점선)
    _dashed(canvas, build(_decayOnly), palette.textTertiary);

    // ── 복습하면 (실선)
    canvas.drawPath(
      build(_retention),
      Paint()
        ..color = palette.brandText
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );

    // ── 복습 지점. 겹치는 표시에는 배경색 링을 둘러 서로 붙어 보이지 않게 한다.
    for (final d in _kReviewDays) {
      if (d > maxDay) continue;
      final c = Offset(xOf(d.toDouble(), size.width), _yOf(_retention(d.toDouble()), size.height));
      canvas.drawCircle(c, 6, Paint()..color = palette.surfaceRaised);
      canvas.drawCircle(c, 4.5, Paint()..color = palette.brandPrimary);
      canvas.drawCircle(
        c,
        4.5,
        Paint()
          ..color = palette.brandText
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke,
      );
    }
  }

  void _dashed(Canvas canvas, Path path, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, math.min(d + 4, m.length)), paint);
        d += 8;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CurvePainter old) =>
      old.progress != progress || old.palette != palette;
}

/// 실제로 오는 알림의 모습. 문구는 복습 알림과 같은 말을 쓴다.
class _MockNotification extends StatelessWidget {
  const _MockNotification();

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: DsSpace.s3),
      decoration: BoxDecoration(
        color: p.surfaceOverlay,
        borderRadius: BorderRadius.circular(DsRadius.r2xl),
        border: Border.all(color: p.borderSubtle),
        boxShadow: DsShadow.lg,
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: p.brandPrimary,
              borderRadius: BorderRadius.circular(DsRadius.lg),
            ),
            alignment: Alignment.center,
            child: DsIcon(DsIcons.review, size: 18, color: p.brandOnPrimary),
          ),
          const SizedBox(width: DsSpace.s3),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('온파',
                        style: dsTextStyle(DsType.caption, p.textPrimary)
                            .copyWith(fontWeight: FontWeight.w700)),
                    const Spacer(),
                    Text('지금', style: dsTextStyle(DsType.caption, p.textTertiary)),
                  ],
                ),
                const SizedBox(height: 2),
                Text('오늘 복습할 문제 3개가 있어요 · 2분이면 끝나요',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: dsTextStyle(DsType.caption, p.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

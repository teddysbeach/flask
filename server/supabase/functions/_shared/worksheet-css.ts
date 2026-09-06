// 학습지 문서 스타일. 색·간격·서체 값은 전부 tokens.css.ts 의 var(--ds-*) 를 쓴다.
//
// 설계 원칙: 학습지는 앱 화면이 아니라 종이다.
// 섹션마다 테두리와 그림자를 두른 카드를 쌓으면 앱의 목록 화면처럼 보인다.
// 종이 위에서 구역을 나누는 것은 상자가 아니라 여백과 타이포그래피다.

export const WORKSHEET_CSS = `
*, *::before, *::after { box-sizing: border-box; }
html { -webkit-text-size-adjust: 100%; }
body {
  margin: 0;
  background: var(--ds-color-surface-base);
  font-family: var(--ds-font-sans);
  color: var(--ds-color-text-primary);
  -webkit-tap-highlight-color: transparent;
  -webkit-font-smoothing: antialiased;
}

/* 문서 폭은 고정이다. 리플로우가 일어나면 기존 필기 좌표가 전부 어긋난다.
   화면 맞춤은 .sheet-scaler 의 transform: scale() 로만 처리한다. */
.sheet-scaler { transform-origin: top left; will-change: transform; }
.sheet {
  width: var(--ds-sheet-width);
  margin: 0 auto;
  padding: var(--ds-sheet-padding);
  background: var(--ds-paper);
  position: relative;
}

/* ── 아이콘 ──
   currentColor 를 쓰므로 색은 주변 텍스트를 따라간다. */
.ico { display: inline-block; vertical-align: -0.16em; flex: none; }

/* ── 표지 ── */
.sheet__header { margin-bottom: 64px; }
.sheet__eyebrow {
  display: flex; align-items: center; gap: 7px;
  font-size: 13px; font-weight: 700; letter-spacing: .1em;
  color: var(--ds-color-brand-primary);
  margin: 0 0 18px;
}
.sheet__title {
  font-size: 40px; line-height: 1.22; font-weight: 700; letter-spacing: -1px;
  margin: 0 0 18px;
  text-wrap: balance;
}
.sheet__one-liner {
  font-size: 19px; line-height: 1.68; font-weight: 400;
  color: var(--ds-color-text-secondary);
  margin: 0 0 24px;
  max-width: 34em;
}
/* 칩을 나열하면 앱 UI 처럼 보인다. 가운뎃점으로 잇는 한 줄이 문서에 맞는다. */
.sheet__meta {
  display: flex; align-items: center; gap: 10px;
  font-size: 14px; color: var(--ds-color-text-tertiary);
  padding-top: 22px;
  border-top: 1px solid var(--ds-color-border-subtle);
}
.sheet__meta span + span::before { content: "·"; margin-right: 10px; opacity: .6; }

/* ── 섹션 ──
   카드가 아니다. 넉넉한 여백과 머리글의 가는 선으로만 나눈다. */
.sec { margin-bottom: var(--ds-sheet-section-gap); }
.sec:last-of-type { margin-bottom: 0; }

.sec__head {
  margin-bottom: 32px;
  padding-bottom: 18px;
  border-bottom: 1px solid var(--ds-color-border-subtle);
}
/* 번호와 아이콘은 제목과 나란히 두지 않는다. 마커가 셋이 겹치면 제목이 묻힌다. */
.sec__label {
  display: flex; align-items: center; gap: 8px;
  color: var(--ds-color-brand-primary);
  margin: 0 0 10px;
}
.sec__num {
  font-size: var(--ds-ws-section-num-size);
  font-weight: var(--ds-ws-section-num-weight);
  letter-spacing: .14em;
  font-variant-numeric: tabular-nums;
}
.sec__title {
  font-size: var(--ds-ws-section-title-size);
  line-height: var(--ds-ws-section-title-lh);
  font-weight: var(--ds-ws-section-title-weight);
  letter-spacing: -.5px;
  margin: 0;
}
.sec__body > *:first-child { margin-top: 0; }
.sec__body > *:last-child  { margin-bottom: 0; }

/* ── 본문 ── */
.p {
  font-size: var(--ds-ws-body-size);
  line-height: var(--ds-ws-body-lh);   /* 1.78 — 펜으로 줄 사이에 끼워 쓸 여지 */
  margin: 0 0 var(--ds-sheet-block-gap);
  max-width: 38em;                      /* 한 줄이 너무 길면 눈이 되돌아올 자리를 잃는다 */
}
.p strong { font-weight: 700; }
.p em {
  font-style: normal;
  background: linear-gradient(transparent 64%, var(--ds-color-ink-highlighter-alt) 64%);
  padding-bottom: 1px;
}
code, .code {
  font-family: var(--ds-font-mono);
  font-size: .9em;
  background: var(--ds-color-surface-sunken);
  padding: 2px 6px; border-radius: var(--ds-radius-sm);
  color: var(--ds-color-text-primary);
}
.h3 {
  display: flex; align-items: center; gap: 8px;
  font-size: 19px; font-weight: 700; line-height: 1.5;
  margin: 40px 0 16px; letter-spacing: -.3px;
}
.h3 .ico { color: var(--ds-color-text-tertiary); }
.list { margin: 0 0 var(--ds-sheet-block-gap); padding-left: 24px; max-width: 38em; }
.list li {
  font-size: var(--ds-ws-body-size); line-height: var(--ds-ws-body-lh);
  margin-bottom: 10px; padding-left: 4px;
}
.list li::marker { color: var(--ds-color-text-tertiary); }

/* ── 일상 비유 ──
   학습지에서 가장 먼저 읽는 문장. 상자에 가두지 않고 리드 문단으로 세운다. */
.analogy {
  display: block;
  font-size: var(--ds-ws-lead-size);
  line-height: var(--ds-ws-lead-lh);
  font-weight: var(--ds-ws-lead-weight);
  letter-spacing: -.2px;
  margin: 0 0 36px;
  padding-left: 24px;
  border-left: 3px solid var(--ds-color-brand-primary);
  max-width: 36em;
}
.analogy .ico { display: none; }   /* 리드 문단에는 아이콘을 넣지 않는다 */

/* ── 용어 풀이 ──
   사전처럼 읽히게. 가는 선으로 항목을 나눈다. */
.glossary {
  margin: 0 0 var(--ds-sheet-block-gap);
  border-top: 1px solid var(--ds-color-border-subtle);
}
.glossary dt {
  font-size: 16px; font-weight: 700;
  padding: 16px 0 0;
  color: var(--ds-color-text-primary);
}
.glossary dd {
  font-size: 16px; line-height: 1.7; margin: 5px 0 0;
  padding-bottom: 16px;
  border-bottom: 1px solid var(--ds-color-border-subtle);
  color: var(--ds-color-text-secondary);
  max-width: 40em;
}

/* ── 파르 ──
   먼저 헤맨 사람이 옆에서 건네는 말. 회색 상자가 아니라 사람이 말하는 모양이어야 한다. */
.par {
  display: grid; grid-template-columns: 40px 1fr; gap: 16px;
  margin: 36px 0 0;
  padding: 22px 24px 22px 20px;
  background: var(--ds-color-surface-sunken);
  border-radius: var(--ds-radius-2xl);
  max-width: 40em;
}
.par__badge {
  display: inline-flex; align-items: center; justify-content: center;
  width: 40px; height: 40px; border-radius: var(--ds-radius-full);
  background: var(--ds-color-brand-primary); color: #fff;
}
.par__badge span { display: none; }        /* 이름은 아래 본문 쪽에서 낸다 */
.par__name {
  display: block; font-size: 13px; font-weight: 700;
  color: var(--ds-color-brand-primary);
  margin: 2px 0 6px; letter-spacing: -.01em;
}
.par__note {
  font-size: 16px; line-height: 1.75; margin: 0;
  color: var(--ds-color-text-primary);
}

/* ── 콜아웃 ──
   좌측 굵은 바 + 대문자 라벨은 오래된 관용구다. 옅은 면과 아이콘 라벨로 충분하다. */
.callout {
  margin: 0 0 var(--ds-sheet-block-gap);
  padding: 22px 26px;
  border-radius: var(--ds-radius-2xl);
  max-width: 40em;
}
.callout--story   { background: var(--ds-callout-story-bg); }
.callout--tip     { background: var(--ds-callout-tip-bg); }
.callout--caution { background: var(--ds-callout-caution-bg); }
.callout__label {
  display: flex; align-items: center; gap: 7px;
  font-size: 13px; font-weight: 700; letter-spacing: -.01em;
  margin: 0 0 10px;
}
.callout--story   .callout__label { color: var(--ds-callout-story-accent); }
.callout--tip     .callout__label { color: var(--ds-callout-tip-accent); }
.callout--caution .callout__label { color: var(--ds-callout-caution-accent); }
.callout .p, .callout .list { margin-bottom: 0; font-size: 16px; }
.callout .list li:last-child { margin-bottom: 0; }

/* ── 카드 (사전학습 / 다음 단계 / 숙제) ── */
.cards { display: grid; gap: 14px; margin: 0 0 var(--ds-sheet-block-gap); max-width: 40em; }
.card {
  padding: 20px 22px;
  border: 1px solid var(--ds-color-border-subtle);
  border-radius: var(--ds-radius-xl);
  background: var(--ds-color-surface-raised);
}
.card__title { font-size: 17px; font-weight: 700; margin: 0 0 7px; letter-spacing: -.2px; }
.card__why { font-size: 16px; line-height: 1.7; color: var(--ds-color-text-secondary); margin: 0; }
.card__hint {
  font-size: 14px; color: var(--ds-color-text-tertiary); margin: 10px 0 0;
}

/* ── 타임라인 ── */
.timeline { list-style: none; margin: 0 0 var(--ds-sheet-block-gap); padding: 0; max-width: 40em; }
.timeline li {
  display: grid; grid-template-columns: 108px 1fr; gap: 20px;
  padding: 16px 0;
  border-bottom: 1px solid var(--ds-color-border-subtle);
}
.timeline li:first-child { padding-top: 0; }
.timeline li:last-child { border-bottom: 0; }
.timeline__when {
  font-size: 14px; font-weight: 700; line-height: 1.7;
  color: var(--ds-color-brand-primary);
}
.timeline__what { font-size: 16px; line-height: 1.72; margin: 0; }
/* 불확실한 사실은 눈에 보이게 표시한다. 정직성 규칙의 시각적 표현. */
.conf {
  display: inline-block;
  font-size: 12px; font-weight: 700; padding: 2px 8px;
  border-radius: var(--ds-radius-full); margin-left: 8px; vertical-align: 1px;
}
.conf--medium { background: var(--ds-callout-tip-bg); color: var(--ds-callout-tip-accent); }
.conf--low    { background: var(--ds-callout-caution-bg); color: var(--ds-callout-caution-accent); }

/* ── 상황극 ── */
.scene {
  font-size: 16px; line-height: 1.72; color: var(--ds-color-text-secondary);
  margin: 0 0 24px; max-width: 38em;
}
.dialogue { margin: 0 0 var(--ds-sheet-block-gap); max-width: 38em; }
.dialogue__line {
  display: grid; grid-template-columns: 72px 1fr; gap: 16px;
  padding: 10px 0;
}
.dialogue__speaker {
  font-size: 14px; font-weight: 700; line-height: 1.85;
  color: var(--ds-color-text-tertiary); text-align: right;
}
.dialogue__text { font-size: 17px; line-height: 1.75; margin: 0; }

/* ── 예시 ── */
.example { margin: 0 0 var(--ds-sheet-block-gap); max-width: 40em; }
.example__caption {
  font-size: 14px; color: var(--ds-color-text-tertiary); margin: 0 0 10px;
}
.ex-code, .ex-calc, .ex-steps, .ex-compare {
  background: var(--ds-color-surface-sunken);
  border-radius: var(--ds-radius-xl);
}
.ex-code {
  margin: 0; padding: 20px 22px; overflow-x: auto;
  font-family: var(--ds-font-mono); font-size: 14px; line-height: 1.7;
}
.ex-code code { background: none; padding: 0; }

/* 계산 — 줄마다 한 단계. 손으로 따라 쓰기 좋게 넉넉히 띄운다 */
.ex-calc { list-style: none; counter-reset: step; margin: 0; padding: 20px 24px; }
.ex-calc li {
  font-family: var(--ds-font-mono); font-size: 16px; line-height: 1.9;
  padding: 7px 0 7px 32px; position: relative;
}
.ex-calc li + li { border-top: 1px solid var(--ds-color-border-subtle); }
.ex-calc li::before {
  counter-increment: step; content: counter(step);
  position: absolute; left: 0; top: 12px;
  font-family: var(--ds-font-sans); font-size: 12px; font-weight: 700;
  color: var(--ds-color-text-tertiary);
}

/* 동작 순서 */
.ex-steps { margin: 0; padding: 20px 24px 20px 44px; }
.ex-steps li { font-size: 16px; line-height: 1.8; margin-bottom: 10px; }
.ex-steps li:last-child { margin-bottom: 0; }

/* 전 / 후 비교 */
.ex-compare { padding: 8px 24px; }
.ex-compare__row {
  display: grid; grid-template-columns: 1fr 24px 1fr; gap: 14px; align-items: center;
  padding: 14px 0;
  border-bottom: 1px solid var(--ds-color-border-subtle);
  font-size: 16px; line-height: 1.65;
}
.ex-compare__row:last-child { border-bottom: 0; }
.ex-compare__before { color: var(--ds-color-text-secondary); }
.ex-compare__after { font-weight: 700; }
.ex-compare__arrow { color: var(--ds-color-brand-primary); font-weight: 700; text-align: center; }
.ex-compare__full { grid-column: 1 / -1; }

/* 장면 묘사 */
.ex-scene {
  margin: 0; padding: 22px 26px;
  background: var(--ds-callout-story-bg);
  border-radius: var(--ds-radius-2xl);
}
.ex-scene p { font-size: 16px; line-height: 1.75; margin: 0 0 8px; }
.ex-scene p:last-child { margin-bottom: 0; }

/* ── 문제 ── */
.quiz { list-style: none; margin: 0; padding: 0; counter-reset: q; }
.quiz__item { padding: 32px 0; border-top: 1px solid var(--ds-color-border-subtle); }
.quiz__item:first-child { border-top: 0; padding-top: 0; }
.quiz__q {
  font-size: var(--ds-ws-quiz-question-size);
  line-height: var(--ds-ws-quiz-question-lh);
  font-weight: var(--ds-ws-quiz-question-weight);
  letter-spacing: -.2px;
  margin: 0; max-width: 36em;
}
.quiz__q::before {
  counter-increment: q; content: "Q" counter(q);
  display: block;
  font-size: 13px; font-weight: 700; letter-spacing: .1em;
  color: var(--ds-color-brand-primary);
  margin-bottom: 8px;
}
.quiz__choices { list-style: none; margin: 16px 0 0; padding: 0; max-width: 36em; }
.quiz__choices li {
  font-size: 16px; line-height: 1.6; padding: 13px 18px; margin-bottom: 8px;
  border: 1px solid var(--ds-color-border-subtle);
  border-radius: var(--ds-radius-lg);
}
.quiz__a { margin-top: 16px; }
.quiz__a summary {
  display: inline-flex; align-items: center; gap: 6px;
  cursor: pointer; font-size: 14px; font-weight: 700;
  color: var(--ds-color-text-tertiary); list-style: none;
  padding: 7px 14px; border-radius: var(--ds-radius-full);
  border: 1px solid var(--ds-color-border-subtle);
}
.quiz__a summary::-webkit-details-marker { display: none; }
.quiz__a-body {
  margin-top: 14px; padding: 20px 24px;
  background: var(--ds-color-surface-sunken);
  border-radius: var(--ds-radius-xl);
  font-size: 16px; line-height: 1.75; max-width: 38em;
}
.quiz__a-body p { margin: 0 0 10px; }
.quiz__a-body p:last-child { margin-bottom: 0; }
.quiz__a-label {
  font-size: 12px; font-weight: 700; letter-spacing: .06em;
  color: var(--ds-color-text-tertiary); display: block; margin-bottom: 3px;
}

/* ── 체크리스트 ── */
.checklist { list-style: none; margin: 0; padding: 0; max-width: 38em; }
.checklist li {
  display: grid; grid-template-columns: 24px 1fr; gap: 12px; align-items: start;
  font-size: 16px; line-height: 1.75; margin-bottom: 14px;
}
.checklist li::before {
  content: ""; width: 20px; height: 20px; margin-top: 3px;
  border: 1.5px solid var(--ds-color-border-strong);
  border-radius: var(--ds-radius-md);
}

/* ── 필기 여백 ──
   같은 안내 문구를 열다섯 번 반복하면 그건 안내가 아니라 소음이다.
   대신 아주 옅은 괘선을 깔아서 '여기 쓰라'는 걸 모양으로 알린다. */
.ink-space {
  margin-top: 24px;
  background-image: repeating-linear-gradient(
    to bottom,
    transparent 0, transparent 39px,
    var(--ds-color-border-subtle) 39px, var(--ds-color-border-subtle) 40px
  );
  border-radius: var(--ds-radius-md);
}
.ink-space[data-ink-space="sm"] { height: var(--ds-ink-space-sm); }
.ink-space[data-ink-space="md"] { height: var(--ds-ink-space-md); }
.ink-space[data-ink-space="lg"] { height: var(--ds-ink-space-lg); }

/* ── 필기 레이어 ──
   문서 흐름 안에 절대 배치한다. 본문과 같은 스크롤 컨테이너를 쓰므로
   스크롤 동기화 문제가 애초에 생기지 않는다. docs/plan/06-annotation.md §1 */
.ink-layer {
  position: absolute; top: 0; left: 0;
  width: var(--ds-sheet-width); height: 100%;
  pointer-events: none;
  touch-action: none;
  z-index: 10;
}

.sheet__footer {
  margin-top: 72px; padding-top: 24px;
  border-top: 1px solid var(--ds-color-border-subtle);
  font-size: 13px; color: var(--ds-color-text-tertiary);
  display: flex; justify-content: space-between; align-items: center;
}

@media print {
  body { background: #fff; }
  .sec { break-inside: avoid; }
  .quiz__a { display: none; }
}
`

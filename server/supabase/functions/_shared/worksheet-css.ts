// 학습지 문서 레이아웃. 색·간격·서체 값은 전부 tokens.css.ts 의 var(--ds-*) 를 쓴다.
// 이 파일에 리터럴 색이 들어가면 디자인 교체가 깨진다.

export const WORKSHEET_CSS = `
*, *::before, *::after { box-sizing: border-box; }
html { -webkit-text-size-adjust: 100%; }
body {
  margin: 0;
  background: var(--ds-color-surface-sunken);
  font-family: var(--ds-font-sans);
  color: var(--ds-color-text-primary);
  /* 필기 중 브라우저 제스처가 가로채지 않게 한다 */
  -webkit-tap-highlight-color: transparent;
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

/* ── 헤더 ── */
.sheet__header { margin-bottom: calc(var(--ds-sheet-section-gap) * 1.25); }
.sheet__eyebrow {
  font-size: 13px; font-weight: 700; letter-spacing: .06em;
  color: var(--ds-color-brand-primary); text-transform: uppercase;
  margin: 0 0 10px;
}
.sheet__title {
  font-size: 34px; line-height: 1.25; font-weight: 700; letter-spacing: -.6px;
  margin: 0 0 12px; color: var(--ds-color-text-primary);
}
.sheet__one-liner {
  font-size: var(--ds-ws-body-size); line-height: 1.6;
  color: var(--ds-color-text-secondary); margin: 0 0 16px;
}
.sheet__meta { display: flex; flex-wrap: wrap; gap: 8px; }
.meta-chip {
  font-size: 13px; font-weight: 500; padding: 5px 11px;
  border-radius: var(--ds-radius-full);
  background: var(--ds-color-surface-sunken); color: var(--ds-color-text-secondary);
}

/* ── 섹션 ── */
.sec {
  margin-bottom: var(--ds-sheet-section-gap);
  padding: 28px;
  background: var(--ds-color-surface-raised);
  border: 1px solid var(--ds-color-border-default);
  border-radius: var(--ds-radius-xl);
  box-shadow: var(--ds-shadow-sm);
}
.sec__title {
  display: flex; align-items: center; gap: 12px;
  font-size: var(--ds-ws-section-title-size);
  line-height: var(--ds-ws-section-title-lh);
  font-weight: var(--ds-ws-section-title-weight);
  letter-spacing: -.3px;
  margin: 0 0 20px;
}
.sec__num {
  flex: none;
  display: inline-flex; align-items: center; justify-content: center;
  min-width: 30px; height: 30px; padding: 0 8px;
  font-size: var(--ds-ws-section-num-size);
  font-weight: var(--ds-ws-section-num-weight);
  letter-spacing: var(--ds-ws-section-num-lh);
  border-radius: var(--ds-radius-full);
  background: var(--ds-color-brand-primary);
  color: var(--ds-color-text-on-brand);
}
.sec__body > *:first-child { margin-top: 0; }
.sec__body > *:last-child  { margin-bottom: 0; }

/* ── 본문 타이포 ── */
.p {
  font-size: var(--ds-ws-body-size);
  line-height: var(--ds-ws-body-lh);   /* 1.78 — 펜으로 줄 사이에 끼워 쓸 여지 */
  margin: 0 0 16px;
}
.p strong { font-weight: 700; }
.p em { font-style: normal; background: linear-gradient(transparent 62%, var(--ds-color-ink-highlighter-alt) 62%); }
code, .code {
  font-family: var(--ds-font-mono);
  font-size: .92em;
  background: var(--ds-color-surface-sunken);
  padding: 2px 6px; border-radius: var(--ds-radius-sm);
}
.h3 {
  font-size: 18px; font-weight: 650; line-height: 1.45;
  margin: 28px 0 12px; letter-spacing: -.2px;
}
.list { margin: 0 0 16px; padding-left: 22px; }
.list li { font-size: var(--ds-ws-body-size); line-height: var(--ds-ws-body-lh); margin-bottom: 8px; }
.list li::marker { color: var(--ds-color-text-tertiary); }

/* ── 일상 비유 ──
   학습지에서 독자가 가장 먼저 읽는 문장. 정의보다 먼저 온다. */
.analogy {
  font-size: 19px; line-height: 1.7; font-weight: 500;
  margin: 0 0 20px; padding: 18px 20px;
  background: var(--ds-callout-story-bg);
  border-radius: var(--ds-radius-lg);
  color: var(--ds-color-text-primary);
}

/* ── 용어 풀이 ── */
.glossary { margin: 0 0 16px; }
.glossary dt {
  font-size: 15px; font-weight: 700; margin-top: 14px;
  color: var(--ds-color-brand-primary);
}
.glossary dt:first-child { margin-top: 0; }
.glossary dd {
  font-size: 15px; line-height: 1.7; margin: 4px 0 0;
  color: var(--ds-color-text-secondary);
}

/* ── 파르 ──
   선생이 아니라 옆자리에 앉은, 먼저 헤맨 사람. */
.par {
  display: grid; grid-template-columns: auto 1fr; gap: 12px; align-items: start;
  margin: 20px 0 0; padding: 14px 16px;
  background: var(--ds-color-surface-sunken);
  border-radius: var(--ds-radius-lg);
}
.par__badge {
  flex: none; display: inline-flex; align-items: center; justify-content: center;
  width: 34px; height: 34px; border-radius: var(--ds-radius-full);
  background: var(--ds-color-brand-primary); color: var(--ds-color-text-on-brand);
  font-size: 12px; font-weight: 700; letter-spacing: -.02em;
}
.par__note {
  font-size: 15px; line-height: 1.72; margin: 0;
  color: var(--ds-color-text-primary);
}

/* ── 콜아웃 ── */
.callout {
  border-left: var(--ds-callout-bar-width) solid;
  border-radius: 0 var(--ds-radius-md) var(--ds-radius-md) 0;
  padding: 16px 18px; margin: 0 0 16px;
}
.callout--story   { border-color: var(--ds-callout-story-bar);   background: var(--ds-callout-story-bg); }
.callout--tip     { border-color: var(--ds-callout-tip-bar);     background: var(--ds-callout-tip-bg); }
.callout--caution { border-color: var(--ds-callout-caution-bar); background: var(--ds-callout-caution-bg); }
.callout__label {
  font-size: 12px; font-weight: 700; letter-spacing: .04em;
  text-transform: uppercase; margin: 0 0 6px; opacity: .75;
}
.callout p:last-child { margin-bottom: 0; }

/* ── 카드 그리드 (사전학습 / 다음 단계) ── */
.cards { display: grid; gap: 12px; }
.card {
  padding: 16px 18px;
  border: 1px solid var(--ds-color-border-default);
  border-radius: var(--ds-radius-lg);
  background: var(--ds-color-surface-base);
}
.card__title { font-size: 16px; font-weight: 650; margin: 0 0 6px; }
.card__why { font-size: 14px; line-height: 1.6; color: var(--ds-color-text-secondary); margin: 0; }
.card__hint { font-size: 13px; color: var(--ds-color-text-tertiary); margin: 8px 0 0; }

/* ── 타임라인 (탄생 배경) ── */
.timeline { list-style: none; margin: 0 0 16px; padding: 0; }
.timeline li {
  display: grid; grid-template-columns: 96px 1fr; gap: 16px;
  padding: 12px 0; border-bottom: 1px solid var(--ds-color-border-subtle);
}
.timeline li:last-child { border-bottom: 0; }
.timeline__when { font-size: 14px; font-weight: 650; color: var(--ds-color-brand-primary); }
.timeline__what { font-size: 15px; line-height: 1.65; margin: 0; }
/* 불확실한 사실은 시각적으로 구분한다. 정직성 규칙의 UI 표현. */
.conf { font-size: 11px; font-weight: 700; padding: 2px 6px; border-radius: var(--ds-radius-sm); margin-left: 6px; vertical-align: 2px; }
.conf--medium { background: var(--ds-callout-tip-bg); color: var(--ds-color-status-warning); }
.conf--low    { background: var(--ds-callout-caution-bg); color: var(--ds-color-status-danger); }

/* ── 상황극 ── */
.scene { font-size: 15px; line-height: 1.7; color: var(--ds-color-text-secondary); margin: 0 0 16px; }
.dialogue { margin: 0 0 16px; }
.dialogue__line { display: grid; grid-template-columns: auto 1fr; gap: 12px; margin-bottom: 12px; }
.dialogue__speaker { font-size: 14px; font-weight: 700; white-space: nowrap; color: var(--ds-color-brand-primary); }
.dialogue__text { font-size: 15px; line-height: 1.7; margin: 0; }

/* ── 코드 예시 ── */
.example { margin: 0 0 16px; }
.example__caption { font-size: 13px; color: var(--ds-color-text-secondary); margin: 0 0 8px; }
pre {
  margin: 0; padding: 16px;
  background: var(--ds-color-surface-sunken);
  border-radius: var(--ds-radius-md);
  overflow-x: auto;
  font-family: var(--ds-font-mono); font-size: 13px; line-height: 1.6;
}
pre code { background: none; padding: 0; }

/* ── 문제 ── */
.quiz { list-style: none; margin: 0; padding: 0; counter-reset: q; }
.quiz__item { padding: 20px 0; border-top: 1px solid var(--ds-color-border-subtle); }
.quiz__item:first-child { border-top: 0; padding-top: 0; }
.quiz__q {
  font-size: var(--ds-ws-quiz-question-size);
  line-height: var(--ds-ws-quiz-question-lh);
  font-weight: var(--ds-ws-quiz-question-weight);
  margin: 0 0 4px;
}
.quiz__q::before {
  counter-increment: q; content: "Q" counter(q) ". ";
  color: var(--ds-color-brand-primary);
}
.quiz__choices { list-style: none; margin: 12px 0 0; padding: 0; }
.quiz__choices li {
  font-size: 15px; line-height: 1.6; padding: 9px 14px; margin-bottom: 8px;
  border: 1px solid var(--ds-color-border-default);
  border-radius: var(--ds-radius-md);
}
.quiz__a { margin-top: 12px; }
.quiz__a summary {
  cursor: pointer; font-size: 14px; font-weight: 650;
  color: var(--ds-color-brand-primary); list-style: none;
}
.quiz__a summary::-webkit-details-marker { display: none; }
.quiz__a summary::before { content: "▸ "; }
.quiz__a[open] summary::before { content: "▾ "; }
.quiz__a-body {
  margin-top: 10px; padding: 14px 16px;
  background: var(--ds-color-surface-sunken);
  border-radius: var(--ds-radius-md);
  font-size: 15px; line-height: 1.7;
}
.quiz__a-body p { margin: 0 0 8px; }
.quiz__a-body p:last-child { margin-bottom: 0; }
.quiz__a-label { font-weight: 700; }

/* ── 체크리스트 ── */
.checklist { list-style: none; margin: 0; padding: 0; }
.checklist li {
  display: grid; grid-template-columns: 22px 1fr; gap: 10px; align-items: start;
  font-size: 15px; line-height: 1.7; margin-bottom: 10px;
}
.checklist li::before {
  content: ""; width: 18px; height: 18px; margin-top: 3px;
  border: 1.5px solid var(--ds-color-border-strong);
  border-radius: var(--ds-radius-sm);
}

/* ── 필기 여백 ──
   펜으로 쓰라고 비워 둔 자리. 인쇄하면 사라지는 안내선만 옅게 깐다. */
.ink-space {
  margin-top: 18px;
  border-top: 1px dashed var(--ds-color-border-subtle);
  position: relative;
}
.ink-space[data-ink-space="sm"] { height: var(--ds-ink-space-sm); }
.ink-space[data-ink-space="md"] { height: var(--ds-ink-space-md); }
.ink-space[data-ink-space="lg"] { height: var(--ds-ink-space-lg); }
.ink-space::after {
  content: "여기에 필기하세요";
  position: absolute; top: 10px; left: 0;
  font-size: 12px; color: var(--ds-color-text-tertiary); opacity: .55;
}

/* ── 필기 레이어 ──
   문서 흐름 안에 절대 배치한다. 본문과 같은 스크롤 컨테이너를 쓰므로
   스크롤 동기화 문제가 애초에 생기지 않는다. docs/plan/06-annotation.md §1 */
.ink-layer {
  position: absolute; top: 0; left: 0;
  width: var(--ds-sheet-width); height: 100%;
  pointer-events: none;   /* 필기 모드가 켜질 때만 auto 로 바뀐다 */
  touch-action: none;
  z-index: 10;
}

.sheet__footer {
  margin-top: 40px; padding-top: 20px;
  border-top: 1px solid var(--ds-color-border-subtle);
  font-size: 12px; color: var(--ds-color-text-tertiary); text-align: center;
}

@media print {
  body { background: #fff; }
  .sec { break-inside: avoid; box-shadow: none; }
  .ink-space::after { display: none; }
  .quiz__a { display: none; }   /* 인쇄본에는 정답을 감춘다 */
}
`

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
  overflow-wrap: break-word;
}

/* 문서 폭은 유동이다(V6).
   예전에는 820px 고정을 .sheet-scaler 의 scale() 로 줄여 화면에 맞췄는데,
   390px 폰에서 배율이 0.47 이 되어 18px 본문이 8px 로 보였다. 읽을 수 없는 학습지였다.
   필기 좌표는 이제 [data-ink-anchor] 요소 기준 정규화라 리플로우가 나도 획이 따라간다.
   --ds-sheet-width 는 최대 폭 토큰으로 그대로 남는다(런타임·테스트가 읽는다). */
.sheet-scaler { transform-origin: top left; will-change: transform; }
.sheet {
  width: 100%;
  max-width: var(--ds-sheet-width, 820px);
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
  color: var(--ds-color-brand-text);
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
  color: var(--ds-color-brand-text);
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
/* 단계가 무엇을 하는 자리인지 한 줄. 제목 아래에 조용히 놓인다. */
.sec__lead {
  font-size: 15px; line-height: 1.6;
  color: var(--ds-color-text-tertiary);
  margin: 6px 0 0;
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

/* ── 문제 제시 ──
   학습지 전체가 수렴하는 질문 하나. 제목 다음으로 가장 눈에 띄는 글줄이어야 한다.
   상자가 아니라 굵은 브랜드 색 세로선과 큰 활자로 세운다. */
.problem {
  margin: 0 0 40px;
  padding: 4px 0 4px 28px;
  border-left: 4px solid var(--ds-color-brand-text);
  max-width: 34em;
}
.problem__q {
  font-size: 25px; line-height: 1.5; font-weight: 700; letter-spacing: -.5px;
  margin: 0;
  color: var(--ds-color-text-primary);
  text-wrap: balance;
}
.problem__why {
  font-size: 16px; line-height: 1.7; margin: 14px 0 0;
  color: var(--ds-color-text-secondary);
}

/* ── 관찰 지시 ──
   "여기를 보세요" 목록. 번호가 곧 순서라 크게 세우고 항목 사이를 넉넉히 띄운다. */
.notice {
  list-style: none; counter-reset: notice;
  margin: 0 0 var(--ds-sheet-block-gap); padding: 0; max-width: 38em;
}
.notice li {
  display: grid; grid-template-columns: 32px 1fr; gap: 14px; align-items: start;
  font-size: var(--ds-ws-body-size); line-height: var(--ds-ws-body-lh);
  padding: 12px 0;
  border-top: 1px solid var(--ds-color-border-subtle);
}
.notice li:first-child { border-top: 0; padding-top: 0; }
.notice li::before {
  counter-increment: notice; content: counter(notice);
  display: inline-flex; align-items: center; justify-content: center;
  width: 28px; height: 28px; margin-top: 2px;
  border-radius: var(--ds-radius-full);
  background: var(--ds-color-brand-primary-subtle);
  color: var(--ds-color-brand-text-on-subtle);
  font-size: 13px; font-weight: 700; font-variant-numeric: tabular-nums;
}

/* ── 일상 비유 ──
   관찰한 것에 이름을 붙이는 첫 문장. 상자에 가두지 않고 리드 문단으로 세운다.
   문제 제시의 질문보다는 한 단계 낮게 — 세로선을 가늘게 둔다. */
.analogy {
  display: block;
  font-size: var(--ds-ws-lead-size);
  line-height: var(--ds-ws-lead-lh);
  font-weight: var(--ds-ws-lead-weight);
  letter-spacing: -.2px;
  margin: 0 0 36px;
  padding-left: 24px;
  border-left: 2px solid var(--ds-color-brand-text);
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
  background: var(--ds-color-brand-primary); color: var(--ds-color-brand-on-primary);
}
.par__badge span { display: none; }        /* 이름은 아래 본문 쪽에서 낸다 */
.par__name {
  display: block; font-size: 13px; font-weight: 700;
  color: var(--ds-color-brand-text);
  margin: 2px 0 6px; letter-spacing: -.01em;
}
.par__note {
  font-size: 16px; line-height: 1.75; margin: 0;
  color: var(--ds-color-text-primary);
}

/* ── 활동 ──
   설명 뒤에 학생이 무언가를 하는 자리. 학습지에서 가장 중요한 요소라 가장 눈에 띄어야 한다. */
.act {
  margin: 0 0 var(--ds-sheet-block-gap);
  padding: 24px 26px;
  border: 2px solid var(--ds-color-brand-text);
  border-radius: var(--ds-radius-2xl);
  max-width: 40em;
}
.act__label {
  display: flex; align-items: center; gap: 7px;
  font-size: 13px; font-weight: 700; letter-spacing: .02em;
  color: var(--ds-color-brand-text); margin: 0 0 10px;
}
.act__prompt { font-size: 17px; line-height: 1.7; font-weight: 500; margin: 0; }
.act__options { list-style: none; margin: 14px 0 0; padding: 0; }
.act__options { margin: 14px 0 0; }
.act__key { font-weight: 700; color: var(--ds-color-text-tertiary); }
.act .ink-space { margin-top: 16px; }
.act__reveal { margin-top: 16px; }
.act__reveal summary {
  display: inline-flex; align-items: center; gap: 6px;
  cursor: pointer; font-size: 13px; font-weight: 700; list-style: none;
  color: var(--ds-color-text-tertiary);
  /* 최소 44px. 손가락으로 누르는 것이라 글자 크기가 아니라 누를 면적이 기준이다. */
  min-height: 44px; box-sizing: border-box;
  padding: 6px 14px; border-radius: var(--ds-radius-full);
  border: 1px solid var(--ds-color-border-subtle);
}
.act__reveal summary::-webkit-details-marker { display: none; }
.act__reveal-body {
  margin-top: 12px; font-size: 16px; line-height: 1.72;
  padding: 14px 18px; background: var(--ds-color-surface-sunken);
  border-radius: var(--ds-radius-lg);
}

/* ── 서술형 응답: 타이핑 + 필기 ──
   둘 중 하나만 두면 한쪽 학습자가 답을 남길 방법을 잃는다.
   textarea 는 JS 없이도 쓰이는 진짜 입력칸이라 어떤 경우에도 숨기지 않는다. */
.answer { margin-top: 16px; }
.answer__text {
  display: block; width: 100%;
  font-family: inherit; font-size: 16px; line-height: 1.75;
  color: var(--ds-color-text-primary);
  padding: 12px 14px; min-height: 88px; resize: vertical;
  background: var(--ds-color-surface-raised);
  border: 1px solid var(--ds-color-border-subtle);
  border-radius: var(--ds-radius-lg);
}
.answer__text::placeholder { color: var(--ds-color-text-placeholder); }
.answer__text:focus-visible {
  outline: 2px solid var(--ds-color-border-focus); outline-offset: 1px;
  border-color: var(--ds-color-border-focus);
}
.answer .ink-space { margin-top: 10px; }

/* ── 규칙의 경계 ──
   V6 의 핵심 장치. 단순화가 절대법칙으로 굳는 것을 막는다.
   콜아웃만큼 존재감이 있어야 하지만 '주의' 색(빨강)은 쓰지 않는다 —
   예외는 경고가 아니라 개념의 일부다. 두 줄 구조가 눈에 보이게 가로선으로 나눈다. */
.boundary {
  margin: 0 0 var(--ds-sheet-block-gap);
  padding: 4px 22px;
  background: var(--ds-color-surface-sunken);
  border-left: 3px solid var(--ds-color-border-strong);
  border-radius: var(--ds-radius-lg);
  max-width: 40em;
}
.boundary__holds, .boundary__breaks {
  display: grid; grid-template-columns: 18px 1fr; gap: 10px; align-items: start;
  font-size: 16px; line-height: 1.7;
  margin: 0; padding: 16px 0;
  color: var(--ds-color-text-primary);
}
.boundary__breaks { border-top: 1px solid var(--ds-color-border-subtle); }
.boundary__holds::before, .boundary__breaks::before {
  font-size: 15px; font-weight: 700; line-height: 1.8;
  color: var(--ds-color-text-tertiary);
}
.boundary__holds::before { content: "○"; }
.boundary__breaks::before { content: "×"; }

/* ── 선택지 (라디오) ── */
.act__opt {
  display: grid; grid-template-columns: auto 26px 1fr; gap: 10px; align-items: start;
  font-size: 16px; line-height: 1.65; padding: 10px 12px; margin: 0 -12px;
  border-top: 1px solid var(--ds-color-border-subtle); cursor: pointer;
  border-radius: var(--ds-radius-md);
}
.act__opt input { margin-top: 5px; accent-color: var(--ds-color-brand-text); }
.act__opt.is-picked { background: var(--ds-color-surface-sunken); }
.act__opt.is-correct { background: var(--ds-callout-tip-bg); }
.act__opt.is-wrong { background: var(--ds-callout-caution-bg); }
.act__fb {
  margin: 12px 0 0; padding: 12px 16px; font-size: 15px; line-height: 1.7;
  background: var(--ds-callout-caution-bg); color: var(--ds-color-text-primary);
  border-radius: var(--ds-radius-lg);
}
.act__fb::before { content: "이렇게 고르셨다면 — "; font-weight: 700; color: var(--ds-callout-caution-accent); }
.act__attempt {
  display: inline-flex; align-items: center; gap: 8px;
  margin-top: 8px; font-size: 14px; color: var(--ds-color-text-secondary); cursor: pointer;
  /* 체크박스 한 줄도 누르는 것이다. 19px 짜리 줄은 펜으로만 눌린다. */
  min-height: 44px;
}
.act__attempt input { accent-color: var(--ds-color-brand-text); }
.quiz__submit {
  margin-top: 12px; padding: 9px 20px; font-size: 14px; font-weight: 700; cursor: pointer;
  min-height: 44px; box-sizing: border-box;
  border: 0; border-radius: var(--ds-radius-full);
  background: var(--ds-color-neutral-primary-base); color: var(--ds-color-neutral-primary-on-base);
}
.is-answered .quiz__submit { display: none; }
/* 고르기 전에 답을 열려고 하면 살짝 흔들어 알린다 */
@keyframes nudge { 0%,100% { transform: translateX(0) } 25% { transform: translateX(-4px) } 75% { transform: translateX(4px) } }
.is-nudge { animation: nudge .3s ease 2; }
.is-nudge .act__reveal summary, .is-nudge .quiz__a summary { color: var(--ds-callout-caution-accent); border-color: var(--ds-callout-caution-accent); }

/* ── 맥락 노트 (접힘) ──
   개념 안의 짧은 역사. 핵심 경로가 아니라 접어 두고, 원하면 편다. 섹션 자체는 접지 않는다. */
.context {
  margin: 36px 0 0; max-width: 40em;
  border: 1px dashed var(--ds-color-border-default);
  border-radius: var(--ds-radius-xl);
  padding: 0 22px;
}
.context[open] { padding-bottom: 22px; }
.context__summary {
  display: flex; align-items: center; gap: 8px; cursor: pointer; list-style: none;
  padding: 16px 0; font-size: 15px; font-weight: 700;
  color: var(--ds-color-text-secondary);
}
.context__summary::-webkit-details-marker { display: none; }
.context__summary .ico { color: var(--ds-color-text-tertiary); }
.context[open] .context__summary { border-bottom: 1px solid var(--ds-color-border-subtle); margin-bottom: 18px; }
.context__body .p { font-size: 16px; }
.context__body > *:last-child { margin-bottom: 0; }

/* ── 나가기 전에: 성찰 ── */
.reflect + .reflect { margin-top: 32px; }
.reflect { margin-top: 28px; max-width: 40em; }
.reflect__prompt { display: flex; gap: 8px; align-items: start; font-size: 16px; font-weight: 700; line-height: 1.6; margin: 0; }
.reflect__prompt .ico { color: var(--ds-color-brand-text); margin-top: 3px; }

/* ── 표지: 전제 ── */
.sheet__assumes {
  display: flex; flex-wrap: wrap; gap: 8px; align-items: center;
  font-size: 14px; color: var(--ds-color-text-secondary);
  margin: 14px 0 0;
}
.sheet__assumes-label { color: var(--ds-color-text-tertiary); margin-right: 4px; }
.sheet__assumes > span:not(.sheet__assumes-label) {
  padding: 4px 10px; border-radius: var(--ds-radius-full);
  background: var(--ds-color-surface-sunken);
}

/* ── 오답 진단 ── */
.quiz__mis { margin-top: 14px; padding-top: 14px; border-top: 1px solid var(--ds-color-border-subtle); }
.quiz__mis ul { margin: 6px 0 0; padding-left: 18px; }
.quiz__mis li { font-size: 15px; line-height: 1.7; margin-bottom: 6px; }

/* ── 콜아웃 ──
   좌측 굵은 바 + 대문자 라벨은 오래된 관용구다. 옅은 면과 아이콘 라벨로 충분하다. */
.callout {
  margin: 0 0 var(--ds-sheet-block-gap);
  padding: 22px 26px;
  border-radius: var(--ds-radius-2xl);
  max-width: 40em;
}
.callout--caution { background: var(--ds-callout-caution-bg); }
.callout__label {
  display: flex; align-items: center; gap: 7px;
  font-size: 13px; font-weight: 700; letter-spacing: -.01em;
  margin: 0 0 10px;
}
.callout--caution .callout__label { color: var(--ds-callout-caution-accent); }
.callout .p, .callout .list { margin-bottom: 0; font-size: 16px; }
.callout .list li:last-child { margin-bottom: 0; }

/* ── 카드 (다음 단계 / 확장 과제) ── */
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

/* ── 타임라인 (맥락 노트의 사실들) ── */
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
  color: var(--ds-color-brand-text);
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
.ex-compare__arrow { color: var(--ds-color-brand-text); font-weight: 700; text-align: center; }
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
/* 번호 줄. 번호 옆에 이 문제가 무엇을 증거로 삼는지 작은 라벨로 붙는다.
   문제는 개수가 아니라 증거 종류로 센다 — 그 사실이 학습자에게도 보여야 한다. */
.quiz__head {
  display: flex; align-items: center; gap: 10px;
  margin: 0 0 8px;
}
.quiz__head::before {
  counter-increment: q; content: "Q" counter(q);
  font-size: 13px; font-weight: 700; letter-spacing: .1em;
  color: var(--ds-color-brand-text);
}
.quiz__evidence {
  font-size: 12px; font-weight: 700; line-height: 1.4;
  padding: 3px 9px; border-radius: var(--ds-radius-full);
  background: var(--ds-color-surface-sunken);
  color: var(--ds-color-text-tertiary);
}
.quiz__q {
  font-size: var(--ds-ws-quiz-question-size);
  line-height: var(--ds-ws-quiz-question-lh);
  font-weight: var(--ds-ws-quiz-question-weight);
  letter-spacing: -.2px;
  margin: 0; max-width: 36em;
}
.quiz__choices { list-style: none; margin: 16px 0 0; padding: 0; max-width: 36em; }
.quiz__choices { margin: 16px 0 0; }
.quiz__a { margin-top: 16px; }
.quiz__a summary {
  display: inline-flex; align-items: center; gap: 6px;
  cursor: pointer; font-size: 14px; font-weight: 700;
  color: var(--ds-color-text-tertiary); list-style: none;
  min-height: 44px; box-sizing: border-box;
  padding: 7px 16px; border-radius: var(--ds-radius-full);
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
  width: 100%; height: 100%;
  pointer-events: none;
  touch-action: none;
  z-index: 10;
}

/* ── 로버스트니스 예산 (접힘) ──
   이 학습지가 막으려 한 오해와 어디서 어떻게 막았는지.
   학습자보다 검토자를 위한 것이라 맨 끝에서 조용히 있어야 한다 — 회색, 작은 글씨, 접힘. */
.guards {
  margin: 56px 0 0; max-width: 40em;
  border-top: 1px solid var(--ds-color-border-subtle);
}
.guards__summary {
  display: flex; align-items: center; gap: 6px;
  cursor: pointer; list-style: none;
  min-height: 44px; box-sizing: border-box;
  padding: 16px 0 4px;
  font-size: 13px; font-weight: 700;
  color: var(--ds-color-text-tertiary);
}
.guards__summary::-webkit-details-marker { display: none; }
.guards__summary::before { content: "＋"; font-weight: 400; }
.guards[open] .guards__summary::before { content: "－"; }
.guards__list { list-style: none; margin: 8px 0 0; padding: 0; }
.guards__item { padding: 14px 0; border-top: 1px solid var(--ds-color-border-subtle); }
.guards__item:first-child { border-top: 0; }
.guards__mis {
  margin: 0; font-size: 14px; line-height: 1.65;
  color: var(--ds-color-text-secondary);
}
.guards__mis::before { content: "오해 "; color: var(--ds-color-text-tertiary); font-weight: 700; }
.guards__how {
  margin: 5px 0 0; font-size: 13px; line-height: 1.65;
  color: var(--ds-color-text-tertiary);
}
.guards__where {
  display: inline-block; margin-right: 7px;
  font-weight: 700; color: var(--ds-color-text-secondary);
}

.sheet__footer {
  margin-top: 72px; padding-top: 24px;
  border-top: 1px solid var(--ds-color-border-subtle);
  font-size: 13px; color: var(--ds-color-text-tertiary);
  display: flex; justify-content: space-between; align-items: center;
}

/* ── 좁은 화면 ──
   축소해서 보여 주는 것은 대응이 아니다. 폰에서도 본문이 본문 크기로 읽혀야 한다. */
@media (max-width: 900px) {
  .sheet { padding: 56px 44px; }
  .sheet__header { margin-bottom: 48px; }
  .sec { margin-bottom: 56px; }
}
@media (max-width: 640px) {
  :root {
    --ds-ws-body-size: 17px;
    --ds-ws-lead-size: 19px;
    --ds-ws-section-title-size: 22px;
    --ds-ws-quiz-question-size: 17px;
    --ds-ink-space-md: 128px;
    --ds-ink-space-lg: 180px;
  }
  .sheet { padding: 36px 20px; }
  .sheet__header { margin-bottom: 36px; }
  .sheet__title { font-size: 29px; letter-spacing: -.6px; margin-bottom: 14px; }
  .sheet__one-liner { font-size: 17px; margin-bottom: 18px; }
  .sheet__meta { flex-wrap: wrap; gap: 6px; padding-top: 16px; }
  .sec { margin-bottom: 48px; }
  .sec__head { margin-bottom: 24px; padding-bottom: 14px; }
  .h3 { font-size: 18px; margin: 30px 0 14px; }
  .problem { padding-left: 18px; margin-bottom: 30px; }
  .problem__q { font-size: 21px; }
  .analogy { padding-left: 16px; margin-bottom: 28px; }
  .act { padding: 18px 16px; border-radius: var(--ds-radius-xl); }
  .act__opt { margin: 0 -8px; padding: 10px 8px; }
  .callout, .par, .ex-scene { padding: 18px 16px; }
  .par { grid-template-columns: 32px 1fr; gap: 12px; }
  .par__badge { width: 32px; height: 32px; }
  .boundary { padding: 2px 16px; }
  .quiz__item { padding: 24px 0; }
  .quiz__a-body, .ex-code, .ex-calc, .ex-steps { padding: 16px; }
  .ex-compare { padding: 4px 16px; }
  /* 좁은 폭에서 '전 → 후' 를 세 칸으로 두면 양쪽이 두 글자씩 남는다 */
  .ex-compare__row { grid-template-columns: 1fr; gap: 4px; }
  .ex-compare__arrow { text-align: left; }
  .timeline li { grid-template-columns: 1fr; gap: 2px; }
  .notice li { grid-template-columns: 26px 1fr; gap: 10px; }
  .notice li::before { width: 24px; height: 24px; }
  .answer__text { font-size: 15px; min-height: 76px; }
  .sheet__footer { margin-top: 48px; }
}

/* 움직임에 민감한 사람이 있다. OS 에 "동작 줄이기" 를 켜 둔 것은 취향이 아니라 요청이다.
   답을 먼저 열려고 할 때의 흔들림도 여기서 멈춘다 — 알리는 방법은 색과 글자로 충분하다. */
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after {
    animation-duration: 0.01ms !important;
    animation-iteration-count: 1 !important;
    transition-duration: 0.01ms !important;
    scroll-behavior: auto !important;
  }
}

@media print {
  body { background: #fff; }
  .sec { break-inside: avoid; }
  /* 접어 둔 보조 정보는 종이에서 열려 있어야 한다 — 종이에는 삼각형을 누를 방법이 없다. */
  details { display: block; }
  details > * { display: revert; }
  details::details-content { content-visibility: visible; display: block; }
  .context, .guards { break-inside: avoid; }
  /* 답은 예외다. 문제와 정답이 같은 종이에 인쇄되면 문제가 아니다. */
  .quiz__a, .act__reveal { display: none; }
  /* 타이핑칸은 종이 위에서 그냥 줄 없는 빈 칸이다. 배경·그림자 없이 테두리만. */
  .answer__text {
    background: none; box-shadow: none; resize: none;
    border: 1px solid var(--ds-color-border-strong);
  }
  .answer__text::placeholder { color: transparent; }
}
`

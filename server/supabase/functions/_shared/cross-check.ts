// 집필 단계(Sonnet)가 설계 단계(Opus)의 판단을 뒤집지 않았는지 검사한다.
//
// 이 검사가 2단계 하이브리드의 안전장치다. 사실성 판단은 ①에서 끝나야 하고,
// ②는 그걸 문장으로 옮기기만 해야 한다. 프롬프트로 부탁하는 것과 별개로 코드로 확인한다.
//
// V5: 설계가 정하는 것은 네 가지다 — 맥락 노트의 사실(확실성 포함), 문제 계획(난이도·전이),
// 다음 단계 제목, 그리고 첫 예측의 "흔한 오답". 마지막 것이 새로 들어왔다.
// 흔한 오답이 선택지에 없으면 예측은 진단이 아니라 퀴즈다. 집필이 그걸 빼면 설계를 뒤집은 것이다.
//
// V6: 두 가지가 더 설계의 몫이 됐다 — 막아야 할 오해(guards)와 문제의 증거 종류(evidence).
// 둘 다 "이 학습지가 무엇에 버티는가" 를 정하는 판단이라 집필이 손대면 로버스트니스가 무너진다.

import type { WorksheetContent, WorksheetOutline } from './worksheet-types.ts'

export interface CrossCheckResult {
  ok: boolean
  violations: string[]
}

export function crossCheck(outline: WorksheetOutline, content: WorksheetContent): CrossCheckResult {
  const v: string[] = []

  // ── 메타: 난이도와 분야는 설계가 정한다 ────────────────────────────────
  if (content.level !== outline.level) {
    v.push(`level 이 설계(${outline.level})와 다릅니다: ${content.level}`)
  }
  if (content.category !== outline.category) {
    v.push(`category 가 설계(${outline.category})와 다릅니다: ${content.category}`)
  }

  // ── 맥락 노트의 사실과 확실성 등급은 설계가 확정한다 ─────────────────────
  const planned = outline.facts ?? []
  const note = content.concept.context_note
  const written = note?.facts ?? []
  if (planned.length === 0) {
    // 설계가 사실을 하나도 안 냈으면 맥락 노트는 없거나(null) 사실이 0개여야 한다
    if (written.length !== 0) {
      v.push(`concept.context_note.facts 개수가 설계(0)와 다릅니다: ${written.length} — 집필 단계가 사실을 지어낼 수 없습니다`)
    }
  } else if (!note) {
    v.push(`설계가 맥락 노트 사실 ${planned.length}개를 냈는데 concept.context_note 가 없습니다`)
  } else if (written.length !== planned.length) {
    v.push(`concept.context_note.facts 개수가 설계(${planned.length})와 다릅니다: ${written.length}`)
  } else {
    planned.forEach((f, i) => {
      if (written[i].confidence !== f.confidence) {
        v.push(`concept.context_note.facts[${i}].confidence 가 설계(${f.confidence})와 다릅니다: ${written[i].confidence}` +
          ` — 집필 단계가 사실성 판단을 바꿀 수 없습니다`)
      }
    })
  }

  // ── 문제는 설계한 것만 쓴다 (개수·난이도·전이 거리) ────────────────────────
  const quiz = content.practice.quiz
  if (quiz.length !== outline.quiz_plan.length) {
    v.push(`practice.quiz 개수가 설계(${outline.quiz_plan.length})와 다릅니다: ${quiz.length}`)
  } else {
    outline.quiz_plan.forEach((q, i) => {
      if (quiz[i].difficulty !== q.difficulty) {
        v.push(`practice.quiz[${i}].difficulty 가 설계(${q.difficulty})와 다릅니다: ${quiz[i].difficulty}`)
      }
      if (quiz[i].transfer !== q.transfer) {
        v.push(`practice.quiz[${i}].transfer 가 설계(${q.transfer})와 다릅니다: ${quiz[i].transfer}`)
      }
      // 증거 종류는 설계가 고른다. 문제는 개수가 아니라 무엇을 증명하느냐로 뽑히기 때문에,
      // 집필이 graph 를 recall 로 바꾸면 목표를 증명하던 문제가 용어 되살리기로 내려앉는다.
      if (q.evidence && quiz[i].evidence !== q.evidence) {
        v.push(`practice.quiz[${i}].evidence 가 설계(${q.evidence})와 다릅니다: ${quiz[i].evidence}` +
          ` — 문제가 무엇을 증거로 삼는지는 설계 단계의 판단입니다`)
      }
    })
  }

  // ── 다음 단계 제안은 설계가 고른 것이다 (새로 지어내면 안 된다) ────────────
  compareTitles(v, 'exit_ticket.next_steps', outline.next_steps, content.exit_ticket.next_steps)

  // ── 첫 예측의 흔한 오답은 반드시 선택지에 있어야 한다 ─────────────────────
  // 이게 예측의 진단 가치다. 정답만 있는 선택지는 학생이 무엇을 잘못 알고 있는지 보여주지 못한다.
  const wrong = normalize(outline.prediction?.common_wrong ?? '')
  const options = content.predict.hook.options ?? []
  const hasWrong = wrong.length > 0 && options.some((o) => {
    const n = normalize(o)
    return n.includes(wrong) || wrong.includes(n)
  })
  if (!hasWrong) {
    v.push(`predict.hook.options 에 설계의 흔한 오답("${outline.prediction?.common_wrong ?? ''}")이 없습니다` +
      ` — 흔한 오답이 선택지에 있어야 예측이 진단이 됩니다`)
  }

  // ── 막아야 할 오해도 설계가 정한다 ─────────────────────────────────────
  // 집필이 guards 를 자기 마음대로 바꾸면 "무엇에 버티는 학습지인가" 를 설계가 아니라
  // 문장 쓰는 단계가 정하게 된다. 개수와 각 오해가 설계도의 것과 같아야 한다.
  const plannedGuards = outline.guards ?? []
  const writtenGuards = content.robustness?.guards ?? []
  if (plannedGuards.length !== writtenGuards.length) {
    v.push(`robustness.guards 개수가 설계(${plannedGuards.length})와 다릅니다: ${writtenGuards.length}`)
  }
  for (const p of plannedGuards) {
    const want = normalize(p.misconception)
    const found = want.length > 0 && writtenGuards.some((g) => {
      const n = normalize(g.misconception ?? '')
      return n.length > 0 && (n.includes(want) || want.includes(n))
    })
    if (!found) {
      v.push(`robustness.guards 에 설계가 정한 오해("${p.misconception}")가 없습니다` +
        ` — 막을 오해를 집필 단계가 바꿀 수 없습니다`)
    }
  }

  return { ok: v.length === 0, violations: v }
}

function compareTitles(
  v: string[], field: string,
  planned: { title: string }[], written: { title: string }[],
) {
  if (planned.length !== written.length) {
    v.push(`${field} 개수가 설계(${planned.length})와 다릅니다: ${written.length}`)
    return
  }
  planned.forEach((p, i) => {
    if (normalize(p.title) !== normalize(written[i].title)) {
      v.push(`${field}[${i}].title 이 설계("${p.title}")와 다릅니다: "${written[i].title}"`)
    }
  })
}

/** 공백·괄호 차이 정도는 같은 것으로 본다. 표기 흔들림까지 실패로 만들 필요는 없다. */
const normalize = (s: string) => s.replace(/[\s()（）]/g, '').toLowerCase()

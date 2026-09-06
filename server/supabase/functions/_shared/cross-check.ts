// 집필 단계(Sonnet)가 설계 단계(Opus)의 판단을 뒤집지 않았는지 검사한다.
//
// 이 검사가 2단계 하이브리드의 안전장치다. 사실성 판단은 ①에서 끝나야 하고,
// ②는 그걸 문장으로 옮기기만 해야 한다. 프롬프트로 부탁하는 것과 별개로 코드로 확인한다.

import type { WorksheetContent, WorksheetOutline } from './worksheet-types.ts'

export interface CrossCheckResult {
  ok: boolean
  violations: string[]
}

export function crossCheck(outline: WorksheetOutline, content: WorksheetContent): CrossCheckResult {
  const v: string[] = []

  // ── 상황극의 사실/가상 구분은 설계가 정한 것을 따라야 한다 ────────────────
  if (content.roleplay.mode !== outline.roleplay_mode) {
    v.push(`roleplay.mode 가 설계(${outline.roleplay_mode})와 다릅니다: ${content.roleplay.mode}`)
  }

  // ── 탄생 배경의 확실성 등급은 설계가 확정한다 ────────────────────────────
  if (content.origin_story.timeline.length !== outline.facts.length) {
    v.push(`origin_story.timeline 개수가 설계(${outline.facts.length})와 다릅니다: ${content.origin_story.timeline.length}`)
  } else {
    outline.facts.forEach((f, i) => {
      const t = content.origin_story.timeline[i]
      if (t.confidence !== f.confidence) {
        v.push(`origin_story.timeline[${i}].confidence 가 설계(${f.confidence})와 다릅니다: ${t.confidence}` +
          ` — 집필 단계가 사실성 판단을 바꿀 수 없습니다`)
      }
    })
  }

  // 설계가 low/medium 을 하나라도 냈으면 불확실성 고지가 있어야 한다
  const hasUncertain = outline.facts.some((f) => f.confidence !== 'high')
  if (hasUncertain && !content.origin_story.uncertainty_note) {
    v.push('설계가 불확실한 사실을 표시했는데 uncertainty_note 가 없습니다')
  }

  // ── 문제는 설계한 것만 쓴다 ──────────────────────────────────────────────
  if (content.quiz.length !== outline.quiz_plan.length) {
    v.push(`quiz 개수가 설계(${outline.quiz_plan.length})와 다릅니다: ${content.quiz.length}`)
  } else {
    outline.quiz_plan.forEach((q, i) => {
      if (content.quiz[i].difficulty !== q.difficulty) {
        v.push(`quiz[${i}].difficulty 가 설계(${q.difficulty})와 다릅니다: ${content.quiz[i].difficulty}`)
      }
    })
  }

  // ── 사전학습·다음단계 제안은 설계가 고른 것이다 (새로 지어내면 안 된다) ────
  compareTitles(v, 'prerequisites', outline.prerequisites, content.prerequisites)
  compareTitles(v, 'next_steps', outline.next_steps, content.next_steps)

  // ── 메타 ─────────────────────────────────────────────────────────────────
  if (content.level !== outline.level) {
    v.push(`level 이 설계(${outline.level})와 다릅니다: ${content.level}`)
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

// 복습 응답 한 건이 DB 에 만들어야 하는 변화. 순수 함수다.
//
// SM-2 계산 자체는 review-schedule.ts 에 있고 여기서는 그것을 **쓰기만** 한다.
// 앱에도 SM-2 를 넣으면 두 벌이 되고, 두 벌은 반드시 갈라진다.
// 그래서 앱은 이 함수를 부르는 엣지 함수에 grade 만 보낸다.

import { answerReview, rescheduleRemaining } from './review-schedule.ts'
import type { ReviewRow } from './review-schedule.ts'

export interface AnswerPlan {
  /** 응답한 회차에 쓸 것 */
  update: { id: string; state: 'done' | 'retired'; ease: number; grade: number; answeredAt: string }
  /** 남은 회차의 due_at 재계산 (쉽다고 하면 뒤로, 어렵다고 하면 앞으로) */
  reschedule: { id: string; intervalDays: number; ease: number; dueAt: string }[]
  /** 완전히 잊었을 때 끼워 넣는 단기 재복습. 없으면 null */
  relearn: {
    quizItemId: string; repetition: number; intervalDays: number; ease: number; dueAt: string
  } | null
}

/**
 * @param row       응답한 회차
 * @param remaining 같은 학습지의 아직 안 푼 회차들(자기 자신 제외)
 */
export function planAnswer(
  row: ReviewRow,
  remaining: ReviewRow[],
  grade: number,
  now: Date,
  timeZone: string,
  reviewHour: number,
): AnswerPlan {
  const outcome = answerReview(row, grade, now, timeZone, reviewHour)

  // 응답한 회차는 다시 잡지 않는다 — 넣으면 방금 푼 문제의 due_at 이 되살아난다.
  const others = remaining.filter((r) => r.id !== row.id)

  return {
    update: {
      id: row.id,
      state: outcome.state,
      ease: outcome.ease,
      grade,
      answeredAt: now.toISOString(),
    },
    reschedule: rescheduleRemaining(others, outcome.ease, now, timeZone, reviewHour).map((r) => ({
      id: r.id,
      intervalDays: r.intervalDays,
      ease: r.ease,
      dueAt: r.dueAt.toISOString(),
    })),
    relearn: outcome.relearn && {
      quizItemId: outcome.relearn.quizItemId,
      repetition: outcome.relearn.repetition,
      intervalDays: outcome.relearn.intervalDays,
      ease: outcome.relearn.ease,
      dueAt: outcome.relearn.dueAt.toISOString(),
    },
  }
}

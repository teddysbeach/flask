// 망각곡선 복습 스케줄. docs/plan/07-review-notifications.md
//
// 서버가 스케줄의 소스 오브 트루스다. 로컬 알림은 여기서 파생된 캐시일 뿐이라,
// 알림이 유실돼도 앱을 열면 복습 큐가 정확히 복원된다.

/** 에빙하우스 기반 확장 간격. 회차마다 다른 문제를 낸다(같은 문제 반복보다 학습지 전체를 훑는 효과). */
export const BASE_INTERVALS = [1, 3, 7, 16, 35]
export const MAX_REPETITION = BASE_INTERVALS.length

/** iOS 는 앱당 대기 중인 로컬 알림을 64개까지만 유지한다. 다른 알림용 여유를 남긴다. */
export const NOTIFICATION_SLOTS = 48

/** 알림 피로가 이 기능을 죽이는 1번 원인이다. */
export const MAX_REVIEWS_PER_DAY = 3

export const EASE_MIN = 1.3
export const EASE_MAX = 2.8
export const EASE_DEFAULT = 2.5

export interface ReviewRow {
  id: string
  quizItemId: string
  repetition: number
  intervalDays: number
  ease: number
  dueAt: Date
  state: 'pending' | 'done' | 'skipped' | 'retired'
}

// ── 시간대 ───────────────────────────────────────────────────────────────

/** 주어진 시각에서 그 타임존의 UTC 오프셋(분). DST 를 자동으로 반영한다. */
export function tzOffsetMinutes(date: Date, timeZone: string): number {
  const dtf = new Intl.DateTimeFormat('en-US', {
    timeZone, hourCycle: 'h23',
    year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', second: '2-digit',
  })
  const parts: Record<string, string> = {}
  for (const p of dtf.formatToParts(date)) parts[p.type] = p.value
  const asUtc = Date.UTC(
    +parts.year, +parts.month - 1, +parts.day,
    +parts.hour, +parts.minute, +parts.second,
  )
  return (asUtc - date.getTime()) / 60000
}

/** 그 타임존의 날짜 부분(연·월·일). */
export function localDateParts(date: Date, timeZone: string) {
  const dtf = new Intl.DateTimeFormat('en-CA', { timeZone, year: 'numeric', month: '2-digit', day: '2-digit' })
  const [y, m, d] = dtf.format(date).split('-').map(Number)
  return { year: y, month: m, day: d }
}

/**
 * "그 타임존 기준 N일 뒤 H시" 를 UTC 시각으로.
 *
 * DST 경계에서 오프셋이 바뀌므로 한 번 계산한 뒤 다시 확인한다.
 * 이걸 안 하면 서머타임 전환 주에 알림이 한 시간씩 어긋난다.
 */
export function atLocalHour(base: Date, daysAhead: number, timeZone: string, hour: number): Date {
  const { year, month, day } = localDateParts(base, timeZone)
  const target = new Date(Date.UTC(year, month - 1, day + daysAhead))
  const t = localDateParts(target, timeZone)

  const wall = Date.UTC(t.year, t.month - 1, t.day, hour)
  let utc = wall - tzOffsetMinutes(new Date(wall), timeZone) * 60000
  const recheck = wall - tzOffsetMinutes(new Date(utc), timeZone) * 60000
  if (recheck !== utc) utc = recheck
  return new Date(utc)
}

// ── 초기 스케줄 ──────────────────────────────────────────────────────────

export interface ScheduleSeed {
  quizItemId: string
  repetition: number
  intervalDays: number
  ease: number
  dueAt: Date
}

/**
 * 학습지 완성 시점에 문항을 망각곡선 회차에 흩어 놓는다.
 * 문항 수는 분야가 정하므로(4~7) 회차 수(5)와 같지 않다 — 회차를 돌려 쓰되 문항은 다 넣는다.
 */
export function createInitialSchedules(
  quizItemIds: string[], now: Date, timeZone: string, reviewHour: number,
): ScheduleSeed[] {
  // 문항 하나가 회차 하나를 맡아 망각곡선 위에 흩어진다.
  // 예전에는 slice(0, MAX_REPETITION) 이었다 — 문항이 정확히 5개일 때만 우연히 맞았고,
  // 문항 수가 분야마다 달라지자(4~7) 여섯 번째부터는 복습이 아예 안 잡혔다.
  // 문항 수와 회차 수는 다른 것이므로 회차는 돌려 쓰고, 문항은 하나도 빠뜨리지 않는다.
  // 같은 날 겹치는 것은 알림 단계의 하루 상한이 다음 날로 민다.
  return quizItemIds.map((quizItemId, i) => {
    const repetition = i % MAX_REPETITION
    return {
      quizItemId,
      repetition,
      intervalDays: BASE_INTERVALS[repetition],
      ease: EASE_DEFAULT,
      dueAt: atLocalHour(now, BASE_INTERVALS[repetition], timeZone, reviewHour),
    }
  })
}

// ── 응답 처리 (SM-2 lite) ────────────────────────────────────────────────

export const clampEase = (e: number) => Math.min(Math.max(e, EASE_MIN), EASE_MAX)

/** grade 0=모르겠음 1=어려움 2=보통 3=쉬움 */
export function nextEase(ease: number, grade: number): number {
  const q = 3 - grade
  return clampEase(Math.round((ease + (0.1 - q * (0.08 + q * 0.02))) * 100) / 100)
}

export interface AnswerOutcome {
  /** 응답한 회차의 최종 상태 */
  state: 'done' | 'retired'
  ease: number
  /** 완전히 잊었을 때 끼워 넣는 단기 재복습 (없으면 null) */
  relearn: ScheduleSeed | null
}

export function answerReview(
  row: ReviewRow, grade: number, now: Date, timeZone: string, reviewHour: number,
): AnswerOutcome {
  if (grade < 0 || grade > 3) throw new Error(`grade 는 0~3 이어야 합니다: ${grade}`)
  const ease = nextEase(row.ease, grade)

  // 완전히 잊었으면 다음 회차를 기다리지 않고 내일 같은 문제를 다시 낸다
  const relearn = grade === 0
    ? {
        quizItemId: row.quizItemId,
        repetition: Math.max(row.repetition - 1, 0),
        intervalDays: 1,
        ease,
        dueAt: atLocalHour(now, 1, timeZone, reviewHour),
      }
    : null

  // 5회차를 보통 이상으로 통과하면 졸업
  const state: 'done' | 'retired' =
    row.repetition + 1 >= MAX_REPETITION && grade >= 2 ? 'retired' : 'done'

  return { state, ease, relearn }
}

/**
 * 남은 회차의 due_at 을 새 ease 로 다시 계산한다.
 * 쉽다고 답하면 뒤 회차들이 뒤로 밀리고, 어렵다고 답하면 당겨진다.
 *
 * ease 를 그대로 남은 행에 심는 것이 중요하다. 여기서 EASE_DEFAULT 기준으로 다시 만들어 버리면
 * 다음 응답이 항상 2.5 에서 출발해 SM-2 가 누적되지 않는다 — 몇 번을 어렵다고 답해도
 * 간격이 제자리인 셈이 된다.
 */
export function rescheduleRemaining(
  rows: ReviewRow[], ease: number, from: Date, timeZone: string, reviewHour: number,
): { id: string; intervalDays: number; ease: number; dueAt: Date }[] {
  const factor = clampEase(ease) / EASE_DEFAULT
  return rows
    .filter((r) => r.state === 'pending')
    .map((r) => {
      const days = Math.max(1, Math.round(BASE_INTERVALS[r.repetition] * factor))
      return {
        id: r.id,
        intervalDays: days,
        ease: clampEase(ease),
        dueAt: atLocalHour(from, days, timeZone, reviewHour),
      }
    })
}

// ── 알림 배분 ────────────────────────────────────────────────────────────

/**
 * 하루에 몰린 복습을 상한만큼만 남기고 다음 날로 민다.
 * 알림이 하루에 열 개씩 오면 사용자는 알림을 꺼버리고, 그러면 리텐션 엔진이 멈춘다.
 */
export function applyDailyCap<T extends { dueAt: Date }>(
  items: T[], timeZone: string, maxPerDay = MAX_REVIEWS_PER_DAY,
): T[] {
  const sorted = [...items].sort((a, b) => a.dueAt.getTime() - b.dueAt.getTime())
  const perDay = new Map<string, number>()
  const dayKey = (d: Date) => {
    const p = localDateParts(d, timeZone)
    return `${p.year}-${p.month}-${p.day}`
  }

  return sorted.map((item) => {
    let due = item.dueAt
    let guard = 0
    while ((perDay.get(dayKey(due)) ?? 0) >= maxPerDay) {
      due = new Date(due.getTime() + 86400000)
      if (++guard > 365) break        // 무한 루프 방지
    }
    const k = dayKey(due)
    perDay.set(k, (perDay.get(k) ?? 0) + 1)
    return { ...item, dueAt: due }
  })
}

/**
 * 로컬 알림으로 실제로 걸 것만 고른다.
 * iOS 64개 한도 때문에 "다 걸어두기"가 불가능하므로 가장 임박한 것부터 채운다.
 */
export function selectForNotifications<T extends { dueAt: Date }>(
  pending: T[], now: Date, limit = NOTIFICATION_SLOTS,
): T[] {
  return pending
    .filter((r) => r.dueAt.getTime() > now.getTime())
    .sort((a, b) => a.dueAt.getTime() - b.dueAt.getTime())
    .slice(0, limit)
}

/** 알림 본문은 문제 원문이다. 배너를 읽는 순간 인출이 시작된다. */
export function notificationBody(question: string, maxLength = 100): string {
  if (question.length <= maxLength) return question
  const cut = question.slice(0, maxLength)
  const lastStop = Math.max(cut.lastIndexOf('. '), cut.lastIndexOf('? '), cut.lastIndexOf('요 '))
  return (lastStop > maxLength * 0.5 ? cut.slice(0, lastStop + 1) : cut.trimEnd()) + '…'
}

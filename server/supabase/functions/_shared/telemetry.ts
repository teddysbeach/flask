// 텔레메트리 요청 검증. **순수 함수**로 떼어 둔다.
//
// 여기가 느슨하면 언젠가 주제 원문이나 답안이 통째로 들어온다. 그리고 그건 배포한 뒤에는
// 알아채기 어렵다 — 대시보드에 잘 찍히고 있으니 아무도 안 본다.
// 그래서 "무엇을 받는가" 가 아니라 **"무엇만 받는가"** 를 코드로 적는다.

/** 앱의 AnalyticsEvent enum 과 같은 목록. 여기 없는 이름은 버린다. */
export const EVENT_NAMES = [
  'appOpen', 'onboardingStart', 'onboardingComplete', 'onboardingSkip',
  'consentAccept', 'signupStart', 'signupComplete', 'loginComplete', 'logout',
  'worksheetCreateEntry', 'worksheetCreateStart', 'worksheetCreateComplete',
  'worksheetCreateFailed', 'worksheetOpen', 'worksheetResponse',
  'reviewNotificationOpen', 'reviewAnswer',
  'paywallView', 'purchaseStart', 'purchaseComplete', 'purchaseFailed', 'purchaseRestore',
  'withdrawStart', 'withdrawComplete', 'screenView', 'errorShown',
] as const

/**
 * props 에 허용하는 키. **목록에 없는 키는 통째로 버린다.**
 *
 * 막을 키를 나열하는 방식(블록리스트)은 반드시 뚫린다 — 새 화면이 새 키를 만들고,
 * 그 키가 목록에 없으면 그냥 지나간다. 허용할 키를 나열하면 반대가 된다.
 */
export const ALLOWED_PROP_KEYS = new Set([
  'name',            // 화면 이름 (screenView)
  'topic_length',    // 주제 원문이 아니라 길이
  'level', 'grade', 'index', 'total', 'count', 'kind', 'stage', 'reason',
  'product_id', 'granted', 'already_processed', 'from',
  'ok', 'retryable', 'code', 'error_code', 'duration_ms', 'elapsed_sec', 'source',
  'method',          // 로그인 수단(email · apple · google) — 계정 자체가 아니다
  'has_session', 'version', 'marketing', 'page', 'pages',
])

const MAX_PROPS = 12
const MAX_STR = 120
const MAX_BATCH = 50

export interface CleanEvent {
  name: string
  props: Record<string, unknown>
  occurred_at: string
}

const isIsoDate = (v: unknown): v is string =>
  typeof v === 'string' && !Number.isNaN(Date.parse(v))

/** 값도 거른다. 문자열은 길이를 자르고, 객체·배열은 아예 안 받는다(중첩이 곧 유출 경로다). */
function cleanProps(raw: unknown): Record<string, unknown> {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return {}
  const out: Record<string, unknown> = {}
  for (const [k, v] of Object.entries(raw as Record<string, unknown>)) {
    if (Object.keys(out).length >= MAX_PROPS) break
    if (!ALLOWED_PROP_KEYS.has(k)) continue
    if (typeof v === 'string') out[k] = v.slice(0, MAX_STR)
    else if (typeof v === 'number' && Number.isFinite(v)) out[k] = v
    else if (typeof v === 'boolean') out[k] = v
    // null·객체·배열은 담지 않는다.
  }
  return out
}

/** 배치 하나를 정제한다. 못 쓰는 항목은 **조용히 버린다** — 앱이 재시도하게 만들 이유가 없다. */
export function cleanEvents(raw: unknown): CleanEvent[] {
  if (!Array.isArray(raw)) return []
  const names = new Set<string>(EVENT_NAMES)
  const out: CleanEvent[] = []
  for (const item of raw.slice(0, MAX_BATCH)) {
    if (!item || typeof item !== 'object') continue
    const e = item as Record<string, unknown>
    if (typeof e.name !== 'string' || !names.has(e.name)) continue
    if (!isIsoDate(e.occurred_at)) continue
    out.push({
      name: e.name,
      props: cleanProps(e.props),
      occurred_at: new Date(e.occurred_at).toISOString(),
    })
  }
  return out
}

export interface CleanCrash {
  fingerprint: string
  message: string
  stack: string | null
  context: string | null
  fatal: boolean
  occurred_at: string
}

export function cleanCrashes(raw: unknown): CleanCrash[] {
  if (!Array.isArray(raw)) return []
  const out: CleanCrash[] = []
  for (const item of raw.slice(0, MAX_BATCH)) {
    if (!item || typeof item !== 'object') continue
    const c = item as Record<string, unknown>
    if (typeof c.message !== 'string' || c.message.trim() === '') continue
    if (!isIsoDate(c.occurred_at)) continue
    const fp = typeof c.fingerprint === 'string' && c.fingerprint.length <= 64
      ? c.fingerprint
      : 'unknown'
    out.push({
      fingerprint: fp,
      message: c.message.slice(0, 2000),
      stack: typeof c.stack === 'string' ? c.stack.slice(0, 8000) : null,
      context: typeof c.context === 'string' ? c.context.slice(0, 200) : null,
      fatal: c.fatal === true,
      occurred_at: new Date(c.occurred_at).toISOString(),
    })
  }
  return out
}

/** UUID 형식만 install_id 로 받는다. 아무 문자열이나 받으면 그게 곧 식별자가 된다. */
export function cleanInstallId(v: unknown): string | null {
  return typeof v === 'string' &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v)
    ? v.toLowerCase()
    : null
}

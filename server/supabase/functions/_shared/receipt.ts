// 영수증 확인. 스토어에 직접 물어본다.
//
// 앱이 보낸 영수증 문자열만 보고 "형식이 맞으니 진짜" 라고 판단하면 안 된다 —
// 형식은 누구나 흉내 낼 수 있다. 반드시 발급처(Apple/Google)에 되물어야 한다.

export interface VerifyInput {
  platform: 'ios' | 'android'
  productId: string
  transactionId: string
  receipt: string
  appleSharedSecret: string
  googleServiceAccountJson: string
  androidPackageName: string
}

export interface Verdict {
  ok: boolean
  reason?: string
  transactionId?: string
  originalTransactionId?: string
}

/** Apple 은 프로덕션 URL 이 21007 을 주면 샌드박스로 다시 물어야 한다(심사 계정이 샌드박스다). */
const APPLE_PROD = 'https://buy.itunes.apple.com/verifyReceipt'
const APPLE_SANDBOX = 'https://sandbox.itunes.apple.com/verifyReceipt'

export async function verifyReceipt(i: VerifyInput): Promise<Verdict> {
  try {
    return i.platform === 'ios' ? await verifyApple(i) : await verifyGoogle(i)
  } catch (e) {
    return { ok: false, reason: `verify_threw:${e instanceof Error ? e.message : e}` }
  }
}

async function verifyApple(i: VerifyInput): Promise<Verdict> {
  if (!i.appleSharedSecret) return { ok: false, reason: 'apple_secret_missing' }

  const ask = async (url: string) => {
    const res = await fetch(url, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        'receipt-data': i.receipt,
        password: i.appleSharedSecret,
        'exclude-old-transactions': false,
      }),
    })
    return await res.json() as Record<string, unknown>
  }

  let body = await ask(APPLE_PROD)
  if (body.status === 21007) body = await ask(APPLE_SANDBOX)
  if (body.status !== 0) return { ok: false, reason: `apple_status_${body.status}` }

  const receipt = body.receipt as { in_app?: Record<string, string>[] } | undefined
  const items = receipt?.in_app ?? []
  const match = items.find((t) => t.transaction_id === i.transactionId) ??
    items.find((t) => t.product_id === i.productId)
  if (!match) return { ok: false, reason: 'apple_transaction_not_found' }
  if (match.product_id !== i.productId) return { ok: false, reason: 'apple_product_mismatch' }
  // 환불·취소된 거래는 지급하지 않는다.
  if (match.cancellation_date_ms) return { ok: false, reason: 'apple_cancelled' }

  return {
    ok: true,
    transactionId: match.transaction_id,
    originalTransactionId: match.original_transaction_id,
  }
}

async function verifyGoogle(i: VerifyInput): Promise<Verdict> {
  if (!i.googleServiceAccountJson) return { ok: false, reason: 'google_credentials_missing' }

  const token = await googleAccessToken(i.googleServiceAccountJson)
  if (!token) return { ok: false, reason: 'google_token_failed' }

  const url = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/` +
    `${encodeURIComponent(i.androidPackageName)}/purchases/products/` +
    `${encodeURIComponent(i.productId)}/tokens/${encodeURIComponent(i.receipt)}`

  const res = await fetch(url, { headers: { authorization: `Bearer ${token}` } })
  if (!res.ok) return { ok: false, reason: `google_http_${res.status}` }

  const body = await res.json() as Record<string, unknown>
  // 0 = 구매됨, 1 = 취소됨, 2 = 보류 중. 보류를 지급하면 결제되지 않은 장수를 준다.
  if (body.purchaseState !== 0) return { ok: false, reason: `google_state_${body.purchaseState}` }

  return {
    ok: true,
    transactionId: (body.orderId as string) ?? i.transactionId,
    originalTransactionId: body.orderId as string | undefined,
  }
}

/** 서비스 계정 JWT → 액세스 토큰. Deno 의 WebCrypto 로 RS256 서명한다. */
async function googleAccessToken(serviceAccountJson: string): Promise<string | null> {
  const sa = JSON.parse(serviceAccountJson) as { client_email: string; private_key: string }
  const now = Math.floor(Date.now() / 1000)
  const header = { alg: 'RS256', typ: 'JWT' }
  const claim = {
    iss: sa.client_email,
    scope: 'https://www.googleapis.com/auth/androidpublisher',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  }
  const b64 = (o: unknown) =>
    btoa(JSON.stringify(o)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
  const unsigned = `${b64(header)}.${b64(claim)}`

  const pem = sa.private_key.replace(/-----[A-Z ]+-----/g, '').replace(/\s/g, '')
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0))
  const key = await crypto.subtle.importKey(
    'pkcs8', der, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign'],
  )
  const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(unsigned))
  const sigB64 = btoa(String.fromCharCode(...new Uint8Array(sig)))
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')

  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: `${unsigned}.${sigB64}`,
    }),
  })
  if (!res.ok) return null
  const body = await res.json() as { access_token?: string }
  return body.access_token ?? null
}

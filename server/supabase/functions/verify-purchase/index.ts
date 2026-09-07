// POST /functions/v1/verify-purchase  { platform, product_id, transaction_id, receipt, original_transaction_id? }
//
// 영수증을 **서버가** 확인하고 장수를 지급한다.
//
// 앱이 "샀어요" 라고 말하는 것만 믿고 지급하면 누구나 장수를 무한히 만들 수 있다.
// 그래서 지급은 서비스 롤로만 하고(RLS 로도 purchases 직접 INSERT 는 막혀 있다),
// 지급 장수는 products 테이블에서 읽는다 — 앱이 보낸 숫자는 쓰지 않는다.
//
// 멱등성은 DB 가 보장한다: unique(platform, transaction_id).
// 그래서 앱이 같은 영수증을 여러 번 보내도(복원·재시도) 두 번 지급되지 않는다.

import { createClient } from 'npm:@supabase/supabase-js@2'
import { json, errorResponse, CORS } from '../_shared/http.ts'
import { verifyReceipt } from '../_shared/receipt.ts'

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS })
  if (req.method !== 'POST') return errorResponse('method_not_allowed', 405)

  const auth = req.headers.get('Authorization') ?? ''
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: auth } } },
  )
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return errorResponse('unauthorized', 401)

  const body = await req.json().catch(() => ({}))
  const platform = body.platform
  const productId = body.product_id
  const transactionId = body.transaction_id
  const receipt = body.receipt

  if (platform !== 'ios' && platform !== 'android') return errorResponse('invalid_platform', 400)
  if (typeof productId !== 'string' || !productId) return errorResponse('invalid_product', 400)
  if (typeof transactionId !== 'string' || !transactionId) return errorResponse('invalid_transaction', 400)
  if (typeof receipt !== 'string' || !receipt) return errorResponse('invalid_receipt', 400)

  const admin = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  )

  // 상품이 우리 카탈로그에 있는지 먼저 본다. 앱이 보낸 product_id 를 그대로 믿지 않는다.
  const { data: product } = await admin
    .from('products').select('id, sheets, price_krw, is_active').eq('id', productId).maybeSingle()
  if (!product || product.is_active !== true) return errorResponse('unknown_product', 400)

  const verdict = await verifyReceipt({
    platform,
    productId,
    transactionId,
    receipt,
    appleSharedSecret: Deno.env.get('APPLE_SHARED_SECRET') ?? '',
    googleServiceAccountJson: Deno.env.get('GOOGLE_SERVICE_ACCOUNT_JSON') ?? '',
    androidPackageName: Deno.env.get('ANDROID_PACKAGE_NAME') ?? 'me.popol.onpar',
  })

  if (!verdict.ok) {
    // 어디서 막혔는지는 로그에만. 응답으로 자세히 알려주면 위조를 도와주는 셈이다.
    console.error('[verify-purchase] 거절', verdict.reason, { platform, productId })
    return errorResponse('receipt_invalid', 402, { detail: '영수증을 확인하지 못했어요.' })
  }

  const { data, error } = await admin.rpc('grant_quota_from_purchase', {
    p_user: user.id,
    p_platform: platform,
    p_product_id: productId,
    p_transaction_id: verdict.transactionId ?? transactionId,
    p_original_transaction_id: verdict.originalTransactionId ?? body.original_transaction_id ?? null,
    p_price_krw: product.price_krw,
    p_receipt: { platform, verified_at: new Date().toISOString() },
  })
  if (error) {
    console.error('[verify-purchase] 지급 실패', error.message)
    return errorResponse('grant_failed', 500)
  }

  const row = Array.isArray(data) ? data[0] : data
  const { data: profile } = await admin
    .from('profiles').select('quota_total, quota_used').eq('id', user.id).single()

  return json({
    ok: true,
    granted: row?.granted ?? 0,
    already_processed: row?.already_processed ?? false,
    quota_remaining: (profile?.quota_total ?? 0) - (profile?.quota_used ?? 0),
  }, 200)
})

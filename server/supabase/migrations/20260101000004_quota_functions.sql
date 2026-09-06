-- 쿼터 조작은 전부 SECURITY DEFINER 함수로만. 근거: docs/plan/03-data-model.md §4

-- ── 생성 시 차감 ─────────────────────────────────────────────────────────
-- WHERE 절이 행 잠금과 조건 검사를 한 문장에서 처리하므로 동시 요청 레이스가 불가능하다.
create or replace function public.consume_quota(p_user uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare v_ok boolean;
begin
  update public.profiles
     set quota_used = quota_used + 1
   where id = p_user
     and quota_used < quota_total
  returning true into v_ok;
  return coalesce(v_ok, false);
end;
$$;

-- ── 생성 실패 시 환불 ────────────────────────────────────────────────────
create or replace function public.refund_quota(p_user uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.profiles
     set quota_used = greatest(quota_used - 1, 0)
   where id = p_user;
end;
$$;

-- ── 결제 지급 ────────────────────────────────────────────────────────────
-- 멱등: unique(platform, transaction_id) + on conflict do nothing 이 중복 지급을 막는다.
-- 지급 장수는 products 테이블에서 조회한다. 호출자가 보낸 값은 쓰지 않는다.
create or replace function public.grant_quota_from_purchase(
  p_user                    uuid,
  p_platform                text,
  p_product_id              text,
  p_transaction_id          text,
  p_original_transaction_id text,
  p_price_krw               int,
  p_receipt                 jsonb
)
returns table (purchase_id uuid, granted int, already_processed boolean)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sheets int;
  v_id     uuid;
begin
  select sheets into v_sheets
    from public.products
   where id = p_product_id and is_active;

  if v_sheets is null then
    raise exception 'unknown_product: %', p_product_id using errcode = 'check_violation';
  end if;

  insert into public.purchases (
    user_id, platform, product_id, transaction_id,
    original_transaction_id, quantity_granted, price_krw, raw_receipt, purchased_at
  ) values (
    p_user, p_platform, p_product_id, p_transaction_id,
    p_original_transaction_id, v_sheets, p_price_krw, p_receipt, now()
  )
  on conflict (platform, transaction_id) do nothing
  returning id into v_id;

  if v_id is null then                      -- 이미 처리된 영수증
    select p.id into v_id
      from public.purchases p
     where p.platform = p_platform and p.transaction_id = p_transaction_id;
    return query select v_id, 0, true;
    return;
  end if;

  update public.profiles
     set quota_total = quota_total + v_sheets
   where id = p_user;

  return query select v_id, v_sheets, false;
end;
$$;

-- ── 환불 회수 ────────────────────────────────────────────────────────────
-- 이미 써버린 장수는 회수하지 않는다. quota_used 는 건드리지 않고 quota_total 만 깎는다.
-- 결과적으로 quota_used > quota_total 이 되면 consume_quota 가 자연스럽게 막는다.
create or replace function public.revoke_quota_from_purchase(
  p_platform       text,
  p_transaction_id text,
  p_reason         text default 'refunded'
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user   uuid;
  v_sheets int;
begin
  update public.purchases
     set state = p_reason, refunded_at = now()
   where platform = p_platform
     and transaction_id = p_transaction_id
     and state = 'granted'
  returning user_id, quantity_granted into v_user, v_sheets;

  if v_user is null then
    return false;                            -- 없는 거래이거나 이미 회수됨 (멱등)
  end if;

  update public.profiles
     set quota_total = greatest(quota_total - v_sheets, 0)
   where id = v_user;

  return true;
end;
$$;

-- 실행 권한은 service_role 에만.
revoke execute on function
  public.consume_quota(uuid),
  public.refund_quota(uuid),
  public.grant_quota_from_purchase(uuid, text, text, text, text, int, jsonb),
  public.revoke_quota_from_purchase(text, text, text)
from public, anon, authenticated;

grant execute on function
  public.consume_quota(uuid),
  public.refund_quota(uuid),
  public.grant_quota_from_purchase(uuid, text, text, text, text, int, jsonb),
  public.revoke_quota_from_purchase(text, text, text)
to service_role;

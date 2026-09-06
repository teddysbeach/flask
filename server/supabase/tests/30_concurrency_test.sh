#!/usr/bin/env bash
# consume_quota 동시성 테스트.
#
# 무료 2장 상한이 지켜지는지는 "동시에 여러 요청이 들어와도" 성립해야 의미가 있다.
# 병렬 세션 N개가 각각 M번 차감을 시도하고, 성공 횟수 합계가 quota_total 과
# 정확히 같은지 본다. 조건부 UPDATE 가 아니라 read-then-write 로 짰다면 여기서 초과가 난다.
set -euo pipefail

DB="${DB:-onpar_test}"
PSQL="${PSQL:-psql}"
WORKERS="${WORKERS:-8}"
ATTEMPTS="${ATTEMPTS:-40}"
QUOTA="${QUOTA:-50}"

USER_ID=$($PSQL -X -At -q -d "$DB" -c "
  insert into auth.users (email) values ('race-$(date +%s%N)@onpar.test') returning id;" | tail -1)
$PSQL -X -q -d "$DB" -c "
  update public.profiles set quota_total = $QUOTA, quota_used = 0 where id = '$USER_ID';"

tmp=$(mktemp -d)
for w in $(seq 1 "$WORKERS"); do
  (
    ok=0
    for _ in $(seq 1 "$ATTEMPTS"); do
      r=$($PSQL -X -At -d "$DB" -c "select public.consume_quota('$USER_ID');")
      [ "$r" = "t" ] && ok=$((ok + 1))
    done
    echo "$ok" > "$tmp/$w"
  ) &
done
wait

total=0
for w in $(seq 1 "$WORKERS"); do total=$((total + $(cat "$tmp/$w"))); done
used=$($PSQL -X -At -d "$DB" -c "select quota_used from public.profiles where id = '$USER_ID';")
rm -rf "$tmp"

echo "워커 ${WORKERS}개 × 시도 ${ATTEMPTS}회 = $((WORKERS * ATTEMPTS))회 요청, 쿼터 ${QUOTA}장"
echo "  성공 반환:   $total"
echo "  quota_used:  $used"

fail=0
[ "$total" = "$QUOTA" ] || { echo "FAIL 성공 횟수가 $total (쿼터 $QUOTA 여야 함)"; fail=1; }
[ "$used"  = "$QUOTA" ] || { echo "FAIL quota_used 가 $used (쿼터 $QUOTA 여야 함)"; fail=1; }
[ "$fail" = 0 ] && echo "PASS 동시 요청에서도 쿼터 초과 지급 없음"
exit $fail

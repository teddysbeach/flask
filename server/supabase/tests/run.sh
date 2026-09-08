#!/usr/bin/env bash
# 로컬 Postgres 에 마이그레이션을 적용하고 전체 테스트를 돌린다.
#
#   ./server/supabase/tests/run.sh
#
# Supabase CLI 없이 순수 Postgres 로 돈다. auth/storage 스키마는 00_shim.sql 이 흉내낸다.
# CI 와 로컬에서 같은 명령으로 검증할 수 있게 하는 게 목적이다.
set -euo pipefail

DB="${DB:-onpar_test}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MIGRATIONS="$HERE/../migrations"

echo "▸ 데이터베이스 재생성: $DB"
dropdb --if-exists "$DB" 2>/dev/null || true
createdb "$DB"

echo "▸ shim 적용 (auth / storage / 역할)"
psql -v ON_ERROR_STOP=1 -X -q -d "$DB" -f "$HERE/00_shim.sql"

echo "▸ 마이그레이션 적용"
#
# `psql ... && echo OK` 로 쓰면 psql 이 실패해도 러너가 0 을 돌려준다(set -e 가
# && 목록의 앞 명령을 봐주기 때문이다). 그러면 **덜 적용된 스키마 위에서** 뒤의 테스트가
# 전부 통과하고 CI 는 초록이 된다 — 실제로 그렇게 한 번 통과했다.
# 실패는 그 자리에서 멈춰야 한다.
for f in "$MIGRATIONS"/*.sql; do
  printf '  %-46s' "$(basename "$f")"
  if ! psql -v ON_ERROR_STOP=1 -X -q -d "$DB" -f "$f"; then
    echo "실패"
    echo "마이그레이션이 적용되지 않았습니다: $(basename "$f")" >&2
    exit 1
  fi
  echo "OK"
done

echo "▸ 테스트"
for f in "$HERE"/[0-9][0-9]_*.sql; do
  echo "  ── $(basename "$f")"
  psql -v ON_ERROR_STOP=1 -X -q -d "$DB" -f "$f" 2>&1 | sed 's/^psql:[^ ]* /    /'
done

echo "  ── 30_concurrency_test.sh"
DB="$DB" bash "$HERE/30_concurrency_test.sh" | sed 's/^/    /'

echo
echo "전부 통과."

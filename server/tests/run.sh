#!/usr/bin/env bash
# 서버 전체 테스트. DB 는 로컬 Postgres, 렌더러는 Node.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"

echo "▸ 토큰 생성물 드리프트 검사"
node "$ROOT/design/build_tokens.mjs" --check

echo "▸ 렌더러 · 검증기"
node --experimental-strip-types "$HERE/render.test.ts"

echo "▸ DB (마이그레이션 · RLS · 동시성)"
"$ROOT/server/supabase/tests/run.sh"

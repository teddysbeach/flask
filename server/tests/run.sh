#!/usr/bin/env bash
# 서버 전체 테스트. DB 는 로컬 Postgres, 렌더러는 Node.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"

echo "▸ 생성물 드리프트 검사"
node "$ROOT/design/build_tokens.mjs" --check
node "$ROOT/server/build-runtime.mjs" --check

echo "▸ 필기 코어"
node "$ROOT/app/tests/ink-core.test.mjs" | tail -2

echo "▸ 렌더러 · 검증기"
node --experimental-strip-types "$HERE/render.test.ts" | tail -2

echo "▸ 비용 · 정합성 · 복습 스케줄"
node --experimental-strip-types "$HERE/logic.test.ts" | tail -2

echo "▸ 생성 파이프라인"
node --experimental-strip-types "$HERE/pipeline.test.ts" | tail -2

echo "▸ DB (마이그레이션 · RLS · 동시성)"
"$ROOT/server/supabase/tests/run.sh"

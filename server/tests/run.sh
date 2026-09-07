#!/usr/bin/env bash
# 서버 전체 테스트. DB 는 로컬 Postgres, 렌더러는 Node.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"

echo "▸ 생성물 드리프트 검사"
node "$ROOT/design/build_tokens.mjs" --check
node "$ROOT/design/build_icons.mjs" --check
node "$ROOT/server/build-runtime.mjs" --check
node "$ROOT/server/build-assets.mjs" --check

echo "▸ 필기 코어"
node "$ROOT/app/tests/ink-core.test.mjs" | tail -2

echo "▸ 렌더러 · 검증기"
node --experimental-strip-types "$HERE/render.test.ts" | tail -2

echo "▸ 비용 · 정합성 · 복습 스케줄"
node --experimental-strip-types "$HERE/logic.test.ts" | tail -2

echo "▸ 학습지 자가점검 (분야별)"
node --experimental-strip-types "$HERE/selfcheck.ts" | tail -5

echo "▸ 상호작용 런타임 (Chromium)"
if node -e "require(require('child_process').execSync('npm root -g',{encoding:'utf8'}).trim()+'/playwright')" 2>/dev/null; then
  node --experimental-strip-types "$HERE/interact.browser.test.ts" | tail -2
else
  echo "  (playwright 가 없어 건너뜀 — npm i -g playwright 후 다시 실행)"
fi

echo "▸ 생성 파이프라인"
node --experimental-strip-types "$HERE/pipeline.test.ts" | tail -2

echo "▸ DB (마이그레이션 · RLS · 동시성)"
"$ROOT/server/supabase/tests/run.sh"

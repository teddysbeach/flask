#!/usr/bin/env node
// assets/manifest.json → assets.g.ts (id 목록 + data URI).
//
// 사진은 라이선스와 출처가 확인된 것만 쓴다. 매니페스트에 없는 id 는 검증기가 거부한다.
// 학습지 HTML 은 외부 요청 0회가 규약이라 이미지도 data URI 로 박아 넣는다.
//   node server/build-assets.mjs [--check]

import { readFileSync, writeFileSync, existsSync, statSync } from 'node:fs'
import { createHash } from 'node:crypto'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const HERE = dirname(fileURLToPath(import.meta.url))
const ROOT = resolve(HERE, '..')
const MANIFEST = resolve(HERE, 'assets/manifest.json')
const OUT = resolve(HERE, 'supabase/functions/_shared/assets.g.ts')
const MAX_BYTES = 900 * 1024   // 한 장이 이보다 크면 학습지가 무거워진다

const MIME = { '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.png': 'image/png', '.webp': 'image/webp' }

const manifest = JSON.parse(readFileSync(MANIFEST, 'utf8'))
const assets = manifest.assets ?? []
const entries = []

for (const a of assets) {
  for (const k of ['id', 'file', 'credit', 'license', 'source']) {
    if (!a[k]) throw new Error(`자산 ${a.id ?? '?'} 에 ${k} 가 없습니다 — 출처·라이선스 없는 이미지는 넣을 수 없습니다`)
  }
  const file = resolve(HERE, 'assets/img', a.file)
  if (!existsSync(file)) throw new Error(`파일이 없습니다: ${a.file}`)
  const ext = a.file.slice(a.file.lastIndexOf('.')).toLowerCase()
  const mime = MIME[ext]
  if (!mime) throw new Error(`지원하지 않는 형식입니다: ${a.file}`)
  const bytes = readFileSync(file)
  if (bytes.length > MAX_BYTES) {
    throw new Error(`${a.file} 이 ${Math.round(bytes.length / 1024)}KB 입니다 (상한 ${MAX_BYTES / 1024}KB). 줄여서 넣으세요`)
  }
  entries.push({
    id: a.id, credit: a.credit, license: a.license, source: a.source,
    note: a.note ?? '', sha256: createHash('sha256').update(bytes).digest('hex').slice(0, 16),
    dataUri: `data:${mime};base64,${bytes.toString('base64')}`,
  })
}

const q = (s) => JSON.stringify(String(s))
const body = `// GENERATED — server/build-assets.mjs 가 assets/manifest.json 에서 만든다. 직접 고치지 않는다.
//
// 실물 자극(사진). 도식으로 대신할 수 없는 지각 판단을 가르칠 때만 쓴다.
// 라이선스·출처가 확인된 것만 들어온다 — 빌드가 그걸 강제한다.

export interface Asset {
  id: string
  credit: string
  license: string
  source: string
  note: string
  sha256: string
  dataUri: string
}

export const ASSETS: Record<string, Asset> = {
${entries.map((e) => `  ${q(e.id)}: { id: ${q(e.id)}, credit: ${q(e.credit)}, license: ${q(e.license)}, source: ${q(e.source)}, note: ${q(e.note)}, sha256: ${q(e.sha256)}, dataUri: ${q(e.dataUri)} },`).join('\n')}
}

export const ASSET_IDS: readonly string[] = ${JSON.stringify(entries.map((e) => e.id))}
`

const check = process.argv.includes('--check')
if (check) {
  const cur = existsSync(OUT) ? readFileSync(OUT, 'utf8') : ''
  if (cur !== body) {
    console.error(`[drift] ${OUT.replace(ROOT + '/', '')} 가 매니페스트와 어긋납니다. node server/build-assets.mjs 를 실행하세요.`)
    process.exit(1)
  }
  console.log(`실물 자극 생성물 최신 상태 확인됨 (${entries.length}개).`)
} else {
  writeFileSync(OUT, body)
  const kb = Math.round(body.length / 1024)
  console.log(`생성: ${OUT.replace(ROOT + '/', '')} (${entries.length}개, ${kb}KB)`)
}

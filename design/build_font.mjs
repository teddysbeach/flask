// Pretendard 서브셋 생성기.
//
//   node design/build_font.mjs
//
// 왜 이 파일이 필요한가:
//   design_tokens.json 은 본문 글꼴을 'Pretendard Variable' 이라고 선언한다. 그런데
//   저장소 어디에도 그 글꼴이 없어서 앱도 학습지도 조용히 시스템 글꼴로 떨어지고 있었다.
//   타입 스케일·자간을 맞춰 놓고 정작 다른 글꼴로 그리고 있었던 셈이다.
//
// 왜 원본을 저장소에 안 두는가:
//   원본 가변 글꼴은 6.7MB 다. 저장소에 두면 clone 마다 그만큼이 따라다닌다.
//   npm 의 `pretendard` 패키지에서 **버전을 고정해** 받아 서브셋만 남긴다.
//
// 왜 한 파일만 만드는가:
//   Flutter 는 TTF/OTF 만 읽고, WebView 는 TTF 도 읽는다. 하나로 둘 다 먹인다 —
//   두 벌로 두면 앱과 학습지의 글자 모양이 갈라질 수 있고, 그건 눈에 보인다.
//
// 라이선스: SIL Open Font License 1.1. 서브셋(파생물) 배포가 허용되며 원문을 함께 둔다
//   (design/fonts/Pretendard-OFL.txt, 앱의 오픈소스 라이선스 화면에도 실린다).

import { execFileSync } from 'node:child_process'
import { existsSync, mkdirSync, readFileSync, rmSync, statSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const VERSION = '1.3.9'
const OUT = resolve(ROOT, 'app/assets/fonts/PretendardVariable.subset.ttf')
const TMP = resolve(ROOT, '.font-build')

/**
 * 담을 글자.
 *
 * 한글은 **KS X 1001 완성형 대역**(cp949 두 바이트가 0xB0~0xC8)만 담는다. 현대 한국어
 * 문장의 사실상 전부가 여기 든다. 11,172자 전체를 담으면 5.5MB 가 되고, 앱 용량 3.5MB 를
 * 더 쓰는 대신 얻는 것이 "뷁" 같은 글자뿐이라 셈이 맞지 않는다.
 * 빠진 글자는 폴백 글꼴이 그린다 — 글꼴 스택이 그 일을 하라고 있는 것이다.
 */
const LATIN = [
  [0x0020, 0x007e], // 아스키
  [0x00a0, 0x00ff], // 라틴-1 보충
  [0x2000, 0x206f], // 일반 구두점(— ‘ ’ “ ” …)
  [0x20a9, 0x20a9], // ₩
  [0x20ac, 0x20ac], // €
  [0x2190, 0x21ff], // 화살표
  [0x2200, 0x22ff], // 수학 기호
  [0x25a0, 0x25ff], // 도형(○ × ● 등 — 학습지가 쓴다)
  [0x2713, 0x2717], // ✓ ✗
  [0x3000, 0x303f], // CJK 구두점
  [0x3130, 0x318f], // 한글 자모(ㄱ ㅏ …)
  [0xff01, 0xff60], // 전각
]

function ksHangul() {
  const out = []
  for (let cp = 0xac00; cp <= 0xd7a3; cp++) {
    const b = Buffer.from(String.fromCodePoint(cp), 'binary')
    // Node 에 cp949 인코더가 없다. KS X 1001 본체는 유니코드 순서와 1:1 이 아니라서
    // 대역 계산으로는 못 고른다 — 대신 iconv 가 있으면 쓰고, 없으면 전체를 담는다.
    out.push(cp)
    void b
  }
  return out
}

function unicodesArg() {
  const parts = LATIN.map(([a, b]) => `U+${a.toString(16).toUpperCase()}-${b.toString(16).toUpperCase()}`)
  const hangul = process.env.ONPAR_FONT_FULL_HANGUL === '1'
    ? ['U+AC00-D7A3']
    : ksSyllablesViaPython()
  return [...parts, ...hangul].join(',')
}

/** KS X 1001 음절 목록. 파이썬의 cp949 코덱으로 고른다(표준 목록을 손으로 적지 않는다). */
function ksSyllablesViaPython() {
  const code = [
    'out=[]',
    'for cp in range(0xAC00, 0xD7A4):',
    '    try:',
    '        b=chr(cp).encode("cp949")',
    '    except UnicodeEncodeError:',
    '        continue',
    '    if 0xB0 <= b[0] <= 0xC8: out.append(cp)',
    'print(",".join("U+%04X" % c for c in out))',
  ].join('\n')
  return [execFileSync('python3', ['-c', code], { encoding: 'utf8' }).trim()]
}

function run(cmd, args, opts = {}) {
  return execFileSync(cmd, args, { stdio: ['ignore', 'pipe', 'inherit'], encoding: 'utf8', ...opts })
}

mkdirSync(TMP, { recursive: true })
console.log(`▸ pretendard@${VERSION} 내려받는 중`)
const tgz = run('npm', ['pack', `pretendard@${VERSION}`, '--silent'], { cwd: TMP }).trim().split('\n').pop()
run('tar', ['xzf', tgz], { cwd: TMP })

const source = resolve(TMP, 'package/dist/public/variable/PretendardVariable.ttf')
if (!existsSync(source)) {
  console.error('패키지 구조가 바뀌었습니다. 원본 경로를 확인하세요:', source)
  process.exit(1)
}

mkdirSync(dirname(OUT), { recursive: true })
console.log('▸ 서브셋 만드는 중 (fontTools)')
run('python3', [
  '-m', 'fontTools.subset', source,
  `--unicodes=${unicodesArg()}`,
  '--layout-features=*',
  // 가변 축(wght)을 남긴다. 400·500·600·700 을 파일 하나로 다 쓴다 —
  // 굵기마다 파일을 두면 네 벌이 되고, 합치면 오히려 더 크다.
  '--recalc-bounds',
  '--name-IDs=*',
  `--output-file=${OUT}`,
], { cwd: TMP })

rmSync(TMP, { recursive: true, force: true })
const kb = Math.round(statSync(OUT).size / 1024)
console.log(`생성: ${OUT.replace(ROOT + '/', '')} (${kb} KB)`)
if (kb > 3072) {
  console.error('서브셋이 3MB 를 넘었습니다. 담는 글자 범위를 다시 보세요.')
  process.exit(1)
}
void readFileSync

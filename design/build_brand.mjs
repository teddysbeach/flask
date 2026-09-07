#!/usr/bin/env node
// ONPAR 브랜드 자산 생성기 — 심볼 · 워드마크 · 앱 아이콘 · 스플래시.
//
//   node design/build_brand.mjs           전부 만든다 (PNG 는 Playwright 필요)
//   node design/build_brand.mjs --check   SVG 산출물이 최신인지만 본다 (브라우저 불필요)
//
// 기하가 여기 한 곳에만 있다. 손으로 만든 PNG 를 저장소에 흩어 두면
// 브랜드 색이나 비율을 바꿀 때 어느 게 낡았는지 아무도 모른다.
//
// ── 심볼의 뜻 ────────────────────────────────────────────────────────────
// 원 하나(사람) 아래에 **길이가 똑같은 줄 두 개**.
// par(라틴어·영어: 동등한)가 이름의 절반이고, 두 줄이 같은 길이인 것이 그 뜻이다.
// 같은 두 줄은 학습지의 줄이기도 하다. 그래서 이 마크는 브랜드 문장을 그대로 그린 것이다 —
// "모두가 같은 자리에서 배운다."
// 원 위에 줄이 겹치지 않는다. 겹치면 ≠(같지 않다) 로 읽힌다 — 뜻이 정반대가 된다.
//
// 어떤 회사의 상표도 쓰지 않는다. 원 하나, 사각형 둘, 브랜드 색뿐이다.

import { execSync } from 'node:child_process';
import { createRequire } from 'node:module';
import { mkdirSync, writeFileSync, readFileSync, existsSync, statSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, '..');
const APP = join(ROOT, 'app');
const IOS = join(APP, 'ios', 'Runner');
const ANDROID_RES = join(APP, 'android', 'app', 'src', 'main', 'res');
const DESIGN_BRAND = join(HERE, 'brand');
const DS_LIB = join(ROOT, 'packages', 'design_system', 'lib', 'src', 'tokens');
const CHECK = process.argv.includes('--check');

// ── 브랜드 색 (design/design_tokens.json) ─────────────────────────────────
const tokens = JSON.parse(readFileSync(join(HERE, 'design_tokens.json'), 'utf8'));
const BRAND = tokens.color.brand.primary;
const BRAND_DEEP = tokens.color.brand.primaryPressed;
const ON_BRAND = tokens.color.brand.onPrimary;
for (const [name, v] of Object.entries({ BRAND, BRAND_DEEP, ON_BRAND })) {
  if (!/^#[0-9a-f]{6}$/i.test(v ?? '')) throw new Error(`${name} 을 토큰에서 못 읽었다: ${v}`);
}

// ── 심볼 ──────────────────────────────────────────────────────────────────
// 1024 캔버스. 글리프는 288 × 576 (정확히 1:2) — 스플래시 PNG 가 배율마다 정수로 떨어진다.
const S = {
  cx: 512,
  ringCy: 368, ringOuter: 144, ringStroke: 76,
  barW: 288, barH: 72, y1: 600, y2: 728,
};
const GLYPH = {
  x: S.cx - S.barW / 2,
  y: S.ringCy - S.ringOuter,
  w: S.barW,
  h: S.y2 + S.barH - (S.ringCy - S.ringOuter),
};
if (GLYPH.h !== GLYPH.w * 2) throw new Error(`심볼 비율이 1:2 가 아니다: ${GLYPH.w}×${GLYPH.h}`);

// 두 줄은 반드시 같은 길이다. 이름의 뜻이라 검사로 못 박는다.
if (S.barW <= 0 || S.barH <= 0) throw new Error('줄 치수가 잘못됐다');

// Android 적응형 아이콘 안전 원(지름 66%)을 벗어나면 런처가 마크를 잘라 먹는다.
const REACH = Math.max(
  Math.hypot(GLYPH.x - S.cx, GLYPH.y - 512),
  Math.hypot(GLYPH.x - S.cx, GLYPH.y + GLYPH.h - 512),
);
const SAFE = 1024 * 0.66 / 2;
if (REACH > SAFE) throw new Error(`심볼이 적응형 안전 원을 벗어난다: ${REACH.toFixed(1)} > ${SAFE.toFixed(1)}`);

const symbolBody = (fill) => [
  `<circle cx="${S.cx}" cy="${S.ringCy}" r="${S.ringOuter - S.ringStroke / 2}" fill="none" stroke="${fill}" stroke-width="${S.ringStroke}"/>`,
  `<rect x="${GLYPH.x}" y="${S.y1}" width="${S.barW}" height="${S.barH}" rx="${S.barH / 2}" fill="${fill}"/>`,
  `<rect x="${GLYPH.x}" y="${S.y2}" width="${S.barW}" height="${S.barH}" rx="${S.barH / 2}" fill="${fill}"/>`,
].join('\n  ');

// ── 워드마크 "온파" ───────────────────────────────────────────────────────
// 심볼과 같은 펜으로 그린다: 같은 둥근 끝, 한 가지 획 두께.
// 한글 자모를 원과 사각형만으로 세운 기하 레터링이라 어떤 폰트에도 기대지 않는다 —
// 폰트를 번들하지 않는 이상 iOS 와 Android 가 다른 글자를 그리기 때문이다.
const W = 46;
const wbar = (x, y, w, h = W) => `<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="${Math.min(w, h) / 2}" fill="FILL"/>`;
const wring = (cx, cy, outer) => `<circle cx="${cx}" cy="${cy}" r="${outer - W / 2}" fill="none" stroke="FILL" stroke-width="${W}"/>`;
const WORD = { w: 752, h: 360, gap: 372 };
const wordmarkBody = (fill) => [
  // 온 — ㅇ / ㅗ / ㄴ
  wring(160, 100, 72),
  wbar(137, 190, W, 38), wbar(0, 224, 320),
  wbar(24, 288, W, 72), wbar(24, 314, 266),
  // 파 — ㅍ / ㅏ
  wbar(WORD.gap + 0, 78, 238), wbar(WORD.gap + 0, 250, 238),
  wbar(WORD.gap + 50, 116, W, 142), wbar(WORD.gap + 142, 116, W, 142),
  wbar(WORD.gap + 268, 56, W, 274), wbar(WORD.gap + 314, 172, 66),
].join('\n  ').replaceAll('FILL', fill);

// ── SVG 문서 ──────────────────────────────────────────────────────────────
const doc = (w, h, body, vb = `0 0 ${w} ${h}`) =>
  `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="${vb}">\n  ${body}\n</svg>\n`;

/** 앱 아이콘 원본. 모서리는 안 깎는다 — iOS 도 Android 도 OS 가 깎는다. */
const iconSvg = doc(1024, 1024, [
  `<defs>`,
  `  <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">`,
  `    <stop offset="0" stop-color="${BRAND}"/>`,
  `    <stop offset="1" stop-color="${BRAND_DEEP}"/>`,
  `  </linearGradient>`,
  `  <radialGradient id="glow" cx="0.26" cy="0.2" r="0.75">`,
  `    <stop offset="0" stop-color="#ffffff" stop-opacity="0.16"/>`,
  `    <stop offset="1" stop-color="#ffffff" stop-opacity="0"/>`,
  `  </radialGradient>`,
  `</defs>`,
  `<rect width="1024" height="1024" fill="url(#bg)"/>`,
  `<rect width="1024" height="1024" fill="url(#glow)"/>`,
  symbolBody(ON_BRAND),
].join('\n  '));

/** 잘라 낸 심볼(투명). 색은 쓰는 쪽이 정한다 — 앱은 ColorFilter 로 칠한다. */
const symbolSvg = doc(GLYPH.w, GLYPH.h, symbolBody('currentColor'), `${GLYPH.x} ${GLYPH.y} ${GLYPH.w} ${GLYPH.h}`);
const symbolWhiteSvg = doc(GLYPH.w, GLYPH.h, symbolBody(ON_BRAND), `${GLYPH.x} ${GLYPH.y} ${GLYPH.w} ${GLYPH.h}`);
const symbolBrandSvg = doc(GLYPH.w, GLYPH.h, symbolBody(BRAND), `${GLYPH.x} ${GLYPH.y} ${GLYPH.w} ${GLYPH.h}`);
const wordmarkSvg = doc(WORD.w, WORD.h, wordmarkBody('currentColor'));
const wordmarkBrandSvg = doc(WORD.w, WORD.h, wordmarkBody(BRAND));

/**
 * 앱에서 쓰는 것은 이 Dart 상수다. 에셋 번들이 아니라 문자열로 두는 이유는 DsIcon 과 같다 —
 * 파일을 안 읽으니 테스트가 에셋 없이 돌고, 경로가 어긋날 일이 없다.
 * 색은 currentColor 라서 쓰는 쪽(SvgTheme)이 정한다.
 */
const brandDart = `// design/build_brand.mjs 가 만든 파일. 손으로 고치지 마세요.
//
// 심볼: 원 하나(사람) 아래 길이가 같은 줄 두 개. par = 동등, 그리고 학습지의 줄.
// 워드마크: "온파" — 원과 사각형만으로 세운 기하 레터링(폰트에 기대지 않는다).

/// 브랜드 도형. 색은 \`currentColor\` 라 쓰는 쪽이 정한다.
class DsBrand {
  const DsBrand._();

  /// 심볼 비율 — 가로:세로 = 1:2.
  static const double symbolAspect = ${GLYPH.w} / ${GLYPH.h};

  /// 워드마크 비율 — 가로:세로.
  static const double wordmarkAspect = ${WORD.w} / ${WORD.h};

  static const String symbol = r'''${symbolSvg.trim()}''';

  static const String wordmark = r'''${wordmarkSvg.trim()}''';
}
`;

// ── 쓰기 · 검사 ───────────────────────────────────────────────────────────
const SVGS = [
  [join(DESIGN_BRAND, 'onpar_symbol.svg'), symbolBrandSvg],
  [join(DESIGN_BRAND, 'onpar_wordmark.svg'), wordmarkBrandSvg],
  [join(DESIGN_BRAND, 'onpar_symbol_white.svg'), symbolWhiteSvg],
  [join(DESIGN_BRAND, 'onpar_icon.svg'), iconSvg],
  [join(DS_LIB, 'brand.g.dart'), brandDart],
];

if (CHECK) {
  const stale = SVGS.filter(([p, want]) => !existsSync(p) || readFileSync(p, 'utf8') !== want);
  if (stale.length) {
    console.error('브랜드 생성물이 낡았다:');
    for (const [p] of stale) console.error(`  ${relative(ROOT, p)}`);
    console.error('node design/build_brand.mjs 를 실행하세요.');
    process.exit(1);
  }
  console.log(`브랜드 생성물 ${SVGS.length}개 최신.`);
  process.exit(0);
}

for (const [p, body] of SVGS) {
  mkdirSync(dirname(p), { recursive: true });
  writeFileSync(p, body);
  console.log(`  ${relative(ROOT, p)}`);
}

// ── PNG 렌더 (Playwright) ─────────────────────────────────────────────────
const require = createRequire(execSync('npm root -g', { encoding: 'utf8' }).trim() + '/');
const { chromium } = require('playwright');
const browser = await chromium.launch();
const page = await browser.newPage();

let written = 0;
async function png(svg, out, w, h, { transparent = true } = {}) {
  mkdirSync(dirname(out), { recursive: true });
  await page.setViewportSize({ width: Math.round(w), height: Math.round(h) });
  await page.setContent(
    `<style>html,body{margin:0;padding:0;background:transparent}svg{display:block;width:${Math.round(w)}px;height:${Math.round(h)}px}</style>${svg}`,
  );
  await page.screenshot({ path: out, omitBackground: transparent });
  if (statSync(out).size < 100) throw new Error(`빈 PNG 가 나왔다: ${out}`);
  written++;
  console.log(`  ${String(Math.round(w)).padStart(4)}×${String(Math.round(h)).padEnd(4)} ${relative(ROOT, out)}`);
}

console.log('\n▸ 원본');
await png(iconSvg, join(DESIGN_BRAND, 'onpar_icon_1024.png'), 1024, 1024, { transparent: false });

console.log('▸ iOS AppIcon');
const IOS_ICONS = [
  ['Icon-App-20x20@1x.png', 20], ['Icon-App-20x20@2x.png', 40], ['Icon-App-20x20@3x.png', 60],
  ['Icon-App-29x29@1x.png', 29], ['Icon-App-29x29@2x.png', 58], ['Icon-App-29x29@3x.png', 87],
  ['Icon-App-40x40@1x.png', 40], ['Icon-App-40x40@2x.png', 80], ['Icon-App-40x40@3x.png', 120],
  ['Icon-App-60x60@2x.png', 120], ['Icon-App-60x60@3x.png', 180],
  ['Icon-App-76x76@1x.png', 76], ['Icon-App-76x76@2x.png', 152],
  ['Icon-App-83.5x83.5@2x.png', 167],
  ['Icon-App-1024x1024@1x.png', 1024],
];
for (const [name, size] of IOS_ICONS) {
  // App Store 아이콘에 알파가 있으면 반려된다. 전부 불투명으로 굽는다.
  await png(iconSvg, join(IOS, 'Assets.xcassets', 'AppIcon.appiconset', name), size, size, { transparent: false });
}

console.log('▸ 스플래시 로고 (흰 심볼 · 투명)');
// 글리프가 1:2 라 90pt 로 잡으면 2x·3x 까지 전부 정수다. 반 픽셀이 남으면 기기마다 흐려진다.
const LAUNCH_W = 90;
const LAUNCH_H = LAUNCH_W * GLYPH.h / GLYPH.w;
if (!Number.isInteger(LAUNCH_H)) throw new Error(`스플래시 로고 높이가 정수가 아니다: ${LAUNCH_H}`);
for (const [suffix, scale] of [['', 1], ['@2x', 2], ['@3x', 3]]) {
  await png(symbolWhiteSvg, join(IOS, 'Assets.xcassets', 'LaunchImage.imageset', `LaunchImage${suffix}.png`),
    LAUNCH_W * scale, LAUNCH_H * scale);
}

console.log('▸ Android 런처 아이콘');
const DENSITIES = [['mdpi', 1], ['hdpi', 1.5], ['xhdpi', 2], ['xxhdpi', 3], ['xxxhdpi', 4]];
for (const [d, s] of DENSITIES) {
  await png(iconSvg, join(ANDROID_RES, `mipmap-${d}`, 'ic_launcher.png'), 48 * s, 48 * s, { transparent: false });
  // 적응형 전경은 108dp 캔버스 전체를 쓰고 실제로 보이는 것은 가운데 72dp 다.
  // 그 안에 드는지는 위 REACH 검사가 보증한다.
  await png(doc(1024, 1024, symbolBody(ON_BRAND)),
    join(ANDROID_RES, `mipmap-${d}`, 'ic_launcher_foreground.png'), 108 * s, 108 * s);
}

console.log('▸ Android 스플래시 로고');
for (const [d, s] of DENSITIES) {
  await png(symbolWhiteSvg, join(ANDROID_RES, `drawable-${d}`, 'splash_logo.png'), LAUNCH_W * s, LAUNCH_H * s);
}

await browser.close();
console.log(`\n생성물 ${SVGS.length}개 · PNG ${written}개 완료.`);

#!/usr/bin/env node
// ONPAR 앱 아이콘 · 스플래시 이미지 생성기.
//
//   node app/assets/icon/build_icons.mjs
//
// SVG 한 벌이 원본이고, iOS/Android 가 요구하는 크기의 PNG 는 전부 여기서 나온다.
// 손으로 만든 PNG 를 저장소에 흩어 두면 브랜드 색을 바꿀 때 어느 게 낡았는지 알 수 없다.
//
// 렌더러는 Playwright(Chromium)다. rsvg-convert/ImageMagick 이 없는 환경에서도 돌아야 해서다.
// 아이콘은 자주 바뀌지 않으므로 CI 드리프트 검사에는 넣지 않는다(브라우저를 받아야 한다).
//
// 모티프: 흰 점 여섯 개 = 학습지의 6단계. 읽는 순서대로 점이 커진다(진행).
// 어떤 회사의 상표도 쓰지 않는다 — 원 여섯 개와 브랜드 색뿐이다.

import { execSync } from 'node:child_process';
import { createRequire } from 'node:module';
import { mkdirSync, writeFileSync, statSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const APP = join(HERE, '..', '..'); // app/
const IOS = join(APP, 'ios', 'Runner');
const ANDROID_RES = join(APP, 'android', 'app', 'src', 'main', 'res');

// ── 브랜드 (design/design_tokens.json) ────────────────────────────────────
const BRAND = '#ff6600'; // color.brand.primary
const BRAND_DEEP = '#e14d00'; // color.brand.primaryPressed
const ON_BRAND = '#ffffff'; // color.brand.onPrimary

// ── 마크 ──────────────────────────────────────────────────────────────────
// 1024 캔버스 기준. 점은 3열 × 2행, 읽는 순서대로 반지름이 커진다.
const CX = [292, 500, 708];
const CY = [390, 598];
const R = [44, 56, 68, 80, 92, 104];
const DOTS = R.map((r, i) => ({ cx: CX[i % 3], cy: CY[(i / 3) | 0], r }));

// 마크가 중심에서 얼마나 뻗는가. Android 적응형 아이콘의 안전 원(지름 66%)에
// 들어가는지 확인하는 데 쓴다. 여기서 넘치면 런처가 점을 잘라 먹는다.
const REACH = Math.max(...DOTS.map((d) => Math.hypot(d.cx - 512, d.cy - 512) + d.r));
const SAFE = 1024 * 0.66 / 2; // 337.9
if (REACH > SAFE) throw new Error(`마크가 적응형 아이콘 안전 원을 벗어난다: ${REACH} > ${SAFE}`);

const dots = (fill) =>
  DOTS.map((d) => `<circle cx="${d.cx}" cy="${d.cy}" r="${d.r}" fill="${fill}"/>`).join('\n  ');

/** 앱 아이콘 원본. 모서리는 둥글리지 않는다 — iOS 도 Android 도 OS 가 깎는다. */
const iconSvg = `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="${BRAND}"/>
      <stop offset="1" stop-color="${BRAND_DEEP}"/>
    </linearGradient>
    <radialGradient id="glow" cx="0.26" cy="0.2" r="0.75">
      <stop offset="0" stop-color="#ffffff" stop-opacity="0.16"/>
      <stop offset="1" stop-color="#ffffff" stop-opacity="0"/>
    </radialGradient>
  </defs>
  <rect width="1024" height="1024" fill="url(#bg)"/>
  <rect width="1024" height="1024" fill="url(#glow)"/>
  ${dots(ON_BRAND)}
</svg>
`;

/** 배경 없는 흰 마크. 적응형 아이콘 전경 · 스플래시 로고. */
const markSvg = `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  ${dots(ON_BRAND)}
</svg>
`;

/** 밝은 배경 위에 얹을 주황 마크. 앱 안에서 쓰는 브랜드 이미지. */
const markOrangeSvg = `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  ${dots(BRAND)}
</svg>
`;

/** 마크만 잘라 낸 조각(투명 배경). 스플래시 로고는 정사각형일 필요가 없다. */
const cropSvg = (fill) => {
  const minX = Math.min(...DOTS.map((d) => d.cx - d.r));
  const maxX = Math.max(...DOTS.map((d) => d.cx + d.r));
  const minY = Math.min(...DOTS.map((d) => d.cy - d.r));
  const maxY = Math.max(...DOTS.map((d) => d.cy + d.r));
  const w = maxX - minX;
  const h = maxY - minY;
  return {
    w,
    h,
    svg: `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="${minX} ${minY} ${w} ${h}">
  ${dots(fill)}
</svg>
`,
  };
};

// ── 렌더 ──────────────────────────────────────────────────────────────────
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
  const size = statSync(out).size;
  if (size < 100) throw new Error(`빈 PNG 가 나왔다: ${out}`);
  written++;
  console.log(`  ${String(Math.round(w)).padStart(4)}×${String(Math.round(h)).padEnd(4)} ${relative(APP, out)}  (${size}B)`);
}

// SVG 원본을 함께 남긴다. PNG 만 있으면 다음 사람이 다시 그릴 수 없다.
writeFileSync(join(HERE, 'onpar_icon.svg'), iconSvg);
writeFileSync(join(HERE, 'onpar_mark.svg'), markSvg);
writeFileSync(join(HERE, 'onpar_mark_orange.svg'), markOrangeSvg);

console.log('▸ 원본');
await png(iconSvg, join(HERE, 'onpar_icon_1024.png'), 1024, 1024, { transparent: false });

console.log('▸ iOS AppIcon');
// Contents.json 이 요구하는 픽셀 크기 전부. 이름은 flutter create 가 만든 것과 같아야 한다.
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
  // App Store 아이콘은 알파 채널이 있으면 반려된다. 전부 불투명으로 굽는다.
  await png(iconSvg, join(IOS, 'Assets.xcassets', 'AppIcon.appiconset', name), size, size, { transparent: false });
}

console.log('▸ iOS LaunchImage (스플래시 로고 · 투명)');
const launch = cropSvg(ON_BRAND);
// 180pt 로 잡으면 마크 비율(600:380)이 정확히 180×114 가 되고, 2x/3x 도 정수로 떨어진다.
// 소수점이 남으면 기기 배율마다 반 픽셀 흐림이 생긴다.
const LAUNCH_W = 180; // pt
const LAUNCH_H = LAUNCH_W * launch.h / launch.w;
if (!Number.isInteger(LAUNCH_H)) throw new Error(`스플래시 로고 높이가 정수가 아니다: ${LAUNCH_H}`);
for (const [suffix, scale] of [['', 1], ['@2x', 2], ['@3x', 3]]) {
  await png(
    launch.svg,
    join(IOS, 'Assets.xcassets', 'LaunchImage.imageset', `LaunchImage${suffix}.png`),
    LAUNCH_W * scale,
    LAUNCH_H * scale,
  );
}

console.log('▸ Android 런처 아이콘');
// API 26+ 는 적응형 아이콘(전경 PNG + 배경 색)을 쓰고, 24~25 만 이 정사각형을 본다.
const DENSITIES = [['mdpi', 1], ['hdpi', 1.5], ['xhdpi', 2], ['xxhdpi', 3], ['xxxhdpi', 4]];
for (const [d, s] of DENSITIES) {
  await png(iconSvg, join(ANDROID_RES, `mipmap-${d}`, 'ic_launcher.png'), 48 * s, 48 * s, { transparent: false });
  // 적응형 전경은 108dp 캔버스 전체를 쓰고, 실제로 보이는 것은 가운데 72dp 다.
  // 마크가 그 안전 원에 들어가는지는 위 REACH 검사가 보증한다.
  await png(markSvg, join(ANDROID_RES, `mipmap-${d}`, 'ic_launcher_foreground.png'), 108 * s, 108 * s);
}

console.log('▸ Android 스플래시 로고');
for (const [d, s] of DENSITIES) {
  await png(launch.svg, join(ANDROID_RES, `drawable-${d}`, 'splash_logo.png'), LAUNCH_W * s, LAUNCH_H * s);
}

console.log('▸ 앱 안에서 쓰는 브랜드 마크');
await png(markOrangeSvg, join(APP, 'assets', 'brand', 'onpar_mark.png'), 512, 512);

await browser.close();
console.log(`\n${written}개 PNG 생성 완료.`);

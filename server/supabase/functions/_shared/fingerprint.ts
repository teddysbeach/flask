/**
 * 프롬프트·스키마의 지문. FNV-1a 32비트를 16진수 8자로.
 *
 * 왜 해시인가: 사람이 손으로 올리는 버전 번호는 반드시 잊어버린다.
 * 프롬프트를 고친 날 버전을 안 올리면, 나중에 품질이 떨어졌을 때
 * "언제부터 이 프롬프트였나" 를 되짚을 방법이 사라진다.
 *
 * 왜 짧은가: 대시보드에서 사람이 눈으로 비교하는 값이다. 길면 안 본다.
 * 여기서 중요한 것은 충돌 확률이 아니라 **바뀌었는지 아닌지**다.
 */
export function fingerprint(parts: string[]): string {
  let h = 0x811c9dc5
  for (const s of parts) {
    for (let i = 0; i < s.length; i++) {
      h ^= s.charCodeAt(i)
      h = Math.imul(h, 0x01000193) >>> 0
    }
    // 조각 경계. 이게 없으면 ["ab","c"] 와 ["a","bc"] 가 같은 지문이 된다 —
    // 프롬프트 한 조각의 끝이 다음 조각 앞으로 옮겨간 변경을 놓치게 된다.
    h ^= 0x1f
    h = Math.imul(h, 0x01000193) >>> 0
  }
  return h.toString(16).padStart(8, '0')
}

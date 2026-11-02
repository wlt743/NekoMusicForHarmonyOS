/**
 * PoW 在 taskpool 后台线程执行，避免阻塞 UI（否则触发 THREAD_BLOCK_6S）。
 *
 * 性能要点：
 * - seed 固定，前缀字节只编码一次，每轮只拼 counter 的 ASCII 数字
 * - 消息长度 ≤ 43 字节（seed 32 + ':' + 最多 10 位数字），永远单块，不用处理分块
 * - W 数组、消息缓冲一次性预分配，循环内零分配
 * - 直接用 h0..h7 判断前导零，不生成字节数组
 */
@Concurrent
export function solvePoW(seed: string, difficulty: number, start: number, end: number): number {
  const limit: number = difficulty > 26 ? 26 : difficulty;

  const K: Int32Array = new Int32Array([
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
  ]);

  // 前缀 "seed:" 的 UTF-8 字节，只算一次
  const prefix: number[] = [];
  const prefixSource: string = seed + ":";
  for (let i: number = 0; i < prefixSource.length; i++) {
    const code: number = prefixSource.charCodeAt(i);
    if (code < 0x80) {
      prefix.push(code);
    } else if (code < 0x800) {
      prefix.push(0xc0 | (code >> 6), 0x80 | (code & 0x3f));
    } else {
      prefix.push(0xe0 | (code >> 12), 0x80 | ((code >> 6) & 0x3f), 0x80 | (code & 0x3f));
    }
  }

  const prefixLen: number = prefix.length;
  const msg: Int32Array = new Int32Array(64);
  const w: Int32Array = new Int32Array(64);
  const digits: Int32Array = new Int32Array(12);

  for (let i: number = 0; i < prefixLen; i++) {
    msg[i] = prefix[i];
  }

  let counter: number = start;
  while (counter < end) {
    // counter 转 ASCII 数字（逆序写入再反转）
    let value: number = counter;
    let digitCount: number = 0;
    if (value === 0) {
      digits[0] = 48;
      digitCount = 1;
    } else {
      while (value > 0) {
        digits[digitCount] = 48 + (value % 10);
        value = Math.floor(value / 10);
        digitCount++;
      }
    }

    const total: number = prefixLen + digitCount;
    for (let i: number = 0; i < digitCount; i++) {
      msg[prefixLen + i] = digits[digitCount - 1 - i];
    }

    // 补齐（单块：total <= 55）
    msg[total] = 0x80;
    for (let i: number = total + 1; i < 56; i++) {
      msg[i] = 0;
    }
    const bitLength: number = total * 8;
    msg[56] = 0;
    msg[57] = 0;
    msg[58] = 0;
    msg[59] = 0;
    msg[60] = (bitLength >>> 24) & 0xff;
    msg[61] = (bitLength >>> 16) & 0xff;
    msg[62] = (bitLength >>> 8) & 0xff;
    msg[63] = bitLength & 0xff;

    for (let i: number = 0; i < 16; i++) {
      const base: number = i * 4;
      w[i] = ((msg[base] << 24) | (msg[base + 1] << 16) | (msg[base + 2] << 8) | msg[base + 3]) | 0;
    }
    for (let i: number = 16; i < 64; i++) {
      const x: number = w[i - 15];
      const y: number = w[i - 2];
      const s0: number = ((x >>> 7) | (x << 25)) ^ ((x >>> 18) | (x << 14)) ^ (x >>> 3);
      const s1: number = ((y >>> 17) | (y << 15)) ^ ((y >>> 19) | (y << 13)) ^ (y >>> 10);
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) | 0;
    }

    let a: number = 0x6a09e667 | 0;
    let b: number = 0xbb67ae85 | 0;
    let c: number = 0x3c6ef372 | 0;
    let d: number = 0xa54ff53a | 0;
    let e: number = 0x510e527f | 0;
    let f: number = 0x9b05688c | 0;
    let g: number = 0x1f83d9ab | 0;
    let h: number = 0x5be0cd19 | 0;

    for (let i: number = 0; i < 64; i++) {
      const S1: number = ((e >>> 6) | (e << 26)) ^ ((e >>> 11) | (e << 21)) ^ ((e >>> 25) | (e << 7));
      const ch: number = (e & f) ^ (~e & g);
      const temp1: number = (h + S1 + ch + K[i] + w[i]) | 0;
      const S0: number = ((a >>> 2) | (a << 30)) ^ ((a >>> 13) | (a << 19)) ^ ((a >>> 22) | (a << 10));
      const maj: number = (a & b) ^ (a & c) ^ (b & c);
      const temp2: number = (S0 + maj) | 0;

      h = g;
      g = f;
      f = e;
      e = (d + temp1) | 0;
      d = c;
      c = b;
      b = a;
      a = (temp1 + temp2) | 0;
    }

    const h0: number = (0x6a09e667 + a) | 0;
    const h1: number = (0xbb67ae85 + b) | 0;
    const h2: number = (0x3c6ef372 + c) | 0;
    const h3: number = (0xa54ff53a + d) | 0;
    const h4: number = (0x510e527f + e) | 0;
    const h5: number = (0x9b05688c + f) | 0;
    const h6: number = (0x1f83d9ab + g) | 0;
    const h7: number = (0x5be0cd19 + h) | 0;

    // 前导零比特
    let bits: number = h0 === 0 ? 32 : Math.clz32(h0 >>> 0);
    if (bits >= limit) {
      return counter;
    }
    if (bits >= 32) {
      bits += h1 === 0 ? 32 : Math.clz32(h1 >>> 0);
      if (bits >= limit) {
        return counter;
      }
    }
    if (bits >= 64) {
      bits += h2 === 0 ? 32 : Math.clz32(h2 >>> 0);
      if (bits >= limit) {
        return counter;
      }
    }
    if (bits >= 96) {
      bits += h3 === 0 ? 32 : Math.clz32(h3 >>> 0);
      if (bits >= limit) {
        return counter;
      }
    }
    if (bits >= 128) {
      bits += h4 === 0 ? 32 : Math.clz32(h4 >>> 0);
      if (bits >= limit) {
        return counter;
      }
    }
    if (bits >= 160) {
      bits += h5 === 0 ? 32 : Math.clz32(h5 >>> 0);
      if (bits >= limit) {
        return counter;
      }
    }
    if (bits >= 192) {
      bits += h6 === 0 ? 32 : Math.clz32(h6 >>> 0);
      if (bits >= limit) {
        return counter;
      }
    }
    if (bits >= 224) {
      bits += h7 === 0 ? 32 : Math.clz32(h7 >>> 0);
      if (bits >= limit) {
        return counter;
      }
    }

    counter++;
  }
  return -1;
}

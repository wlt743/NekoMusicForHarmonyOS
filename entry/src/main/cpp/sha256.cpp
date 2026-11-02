// PoW 的 SHA-256 放到 native 实现：纯 ArkTS 只有约 10 万次/秒，
// native 能到千万级，把 100 万次哈希从 10 秒压到百毫秒。
#include <napi/native_api.h>
#include <cstdint>
#include <cstring>
#include <string>

namespace {

const uint32_t K[64] = {
  0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
  0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
  0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
  0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
  0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
  0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
  0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
  0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2
};

inline uint32_t rotr(uint32_t x, int n) { return (x >> n) | (x << (32 - n)); }

// 单块 SHA-256（消息长度 < 56 字节），tail 由调用方拼好
inline void sha256OneBlock(const uint8_t* msg, int len, uint32_t out[8]) {
  uint32_t w[64];
  for (int i = 0; i < 16; i++) {
    w[i] = (uint32_t(msg[i * 4]) << 24) | (uint32_t(msg[i * 4 + 1]) << 16) |
           (uint32_t(msg[i * 4 + 2]) << 8) | uint32_t(msg[i * 4 + 3]);
  }
  for (int i = 16; i < 64; i++) {
    uint32_t s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
    uint32_t s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
    w[i] = w[i - 16] + s0 + w[i - 7] + s1;
  }
  uint32_t a = 0x6a09e667, b = 0xbb67ae85, c = 0x3c6ef372, d = 0xa54ff53a;
  uint32_t e = 0x510e527f, f = 0x9b05688c, g = 0x1f83d9ab, h = 0x5be0cd19;
  for (int i = 0; i < 64; i++) {
    uint32_t s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
    uint32_t ch = (e & f) ^ (~e & g);
    uint32_t t1 = h + s1 + ch + K[i] + w[i];
    uint32_t s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
    uint32_t maj = (a & b) ^ (a & c) ^ (b & c);
    uint32_t t2 = s0 + maj;
    h = g; g = f; f = e; e = d + t1;
    d = c; c = b; b = a; a = t1 + t2;
  }
  out[0] = a + 0x6a09e667; out[1] = b + 0xbb67ae85;
  out[2] = c + 0x3c6ef372; out[3] = d + 0xa54ff53a;
  out[4] = e + 0x510e527f; out[5] = f + 0x9b05688c;
  out[6] = g + 0x1f83d9ab; out[7] = h + 0x5be0cd19;
}

inline int leadingZeroBits(const uint32_t out[8]) {
  for (int i = 0; i < 8; i++) {
    if (out[i] != 0) return i * 32 + __builtin_clz(out[i]);
  }
  return 256;
}

}  // namespace

// solve(seed: string, difficulty: number): number  找不到返回 -1
static napi_value Solve(napi_env env, napi_callback_info info) {
  size_t argc = 2;
  napi_value argv[2] = {nullptr, nullptr};
  napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);

  size_t len = 0;
  napi_get_value_string_utf8(env, argv[0], nullptr, 0, &len);
  std::string seed(len, '\0');
  napi_get_value_string_utf8(env, argv[0], &seed[0], len + 1, &len);

  int32_t difficulty = 20;
  napi_get_value_int32(env, argv[1], &difficulty);
  if (difficulty > 26) difficulty = 26;

  // 前缀 = seed + ":"，一次拼好
  std::string prefix = seed + ":";
  uint8_t block[64];

  napi_value result;
  for (uint64_t counter = 0; counter < 200000000ULL; counter++) {
    // 拼消息
    size_t pos = prefix.size();
    memcpy(block, prefix.data(), pos);
    char digits[20];
    int dc = 0;
    uint64_t v = counter;
    if (v == 0) { digits[dc++] = '0'; }
    while (v > 0) { digits[dc++] = char('0' + (v % 10)); v /= 10; }
    for (int i = dc - 1; i >= 0; i--) block[pos++] = uint8_t(digits[i]);

    size_t total = pos;
    block[total] = 0x80;
    for (size_t i = total + 1; i < 56; i++) block[i] = 0;
    uint64_t bits = uint64_t(total) * 8;
    for (int i = 0; i < 8; i++) block[63 - i] = uint8_t((bits >> (8 * i)) & 0xff);

    uint32_t out[8];
    sha256OneBlock(block, 64, out);
    if (leadingZeroBits(out) >= difficulty) {
      napi_create_double(env, double(counter), &result);
      return result;
    }
  }
  napi_create_double(env, -1, &result);
  return result;
}

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports) {
  napi_property_descriptor desc[] = {
    {"solve", nullptr, Solve, nullptr, nullptr, nullptr, napi_default, nullptr},
  };
  napi_define_properties(env, exports, 1, desc);
  return exports;
}
EXTERN_C_END

static napi_module g_module = {
  1, 0, nullptr, Init, "pow", nullptr, {0}
};

extern "C" __attribute__((constructor)) void RegisterPowModule() {
  napi_module_register(&g_module);
}

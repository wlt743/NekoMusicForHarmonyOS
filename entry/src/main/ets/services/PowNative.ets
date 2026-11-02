import pow from 'libpow.so';
import { hilog } from '@kit.PerformanceAnalysisKit';

/**
 * PoW 的 native 实现（C++ SHA-256）。
 *
 * 纯 ArkTS 的 SHA-256 大约 10 万次/秒，难度 20（约 100 万次）要 10 秒；
 * native 版本能到千万级，同样的题百毫秒内出结果。
 */
export class PowNative {
  private static broken: boolean = false;

  static solve(seed: string, difficulty: number): number {
    if (PowNative.broken) {
      return -1;
    }
    try {
      return pow.solve(seed, difficulty);
    } catch (error) {
      PowNative.broken = true;
      hilog.warn(0x0000, 'NekoPow', 'native solve failed, fallback to JS: %{public}s',
        (error as Error).message);
      return -1;
    }
  }
}

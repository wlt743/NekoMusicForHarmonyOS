import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { preferences } from '@kit.ArkData';
import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';
import { APIConfig } from './APIConfig';

interface OpenHarmonyRegisterData {
  instance_id?: string;
  token?: string;
  expires_at?: number;
  attestation?: string;
}

interface OpenHarmonyChallengeData {
  challenge?: string;
  expiresIn?: number;
  purpose?: string;
  protocol?: string;
}

interface OpenHarmonyEnvelope<T> {
  success?: boolean;
  message?: string;
  data?: T;
}

/**
 * 客户端身份 v1。
 *
 * 后端要求除白名单外的动态接口证明「应用 + 安装实例」身份：
 * Client ID、实例 UUID、实例短期令牌、每请求签名（ECDSA P-256）。
 *
 * 流程：本机生成 EC P-256 密钥 → 取挑战 → 签名注册换令牌 → 到期前续签 → 每请求签名。
 * 私钥用 PKCS8 存在应用私有 preferences 里，不出沙箱。
 */
export class ClientIdentityService {
  private static instance: ClientIdentityService = new ClientIdentityService();

  private generator: cryptoFramework.AsyKeyGenerator | undefined = undefined;
  private keyPair: cryptoFramework.KeyPair | undefined = undefined;
  private instanceId: string = '';
  private pubBase64: string = '';
  private token: string = '';
  private expiresAt: number = 0;
  private store: preferences.Preferences | undefined = undefined;
  private pending: Promise<void> | undefined = undefined;
  private loaded: boolean = false;

  private readonly prefName: string = 'nekomusic_client_identity';
  private readonly keyPri: string = 'pri_key';
  private readonly keyPub: string = 'pub_key';
  private readonly keyIid: string = 'instance_id';
  private readonly keyToken: string = 'token';
  private readonly keyExpiry: string = 'expires_at';
  /** 提前多久续签（毫秒） */
  private readonly renewMargin: number = 600 * 1000;

  static shared(): ClientIdentityService {
    return ClientIdentityService.instance;
  }

  async init(context: common.UIAbilityContext): Promise<void> {
    if (this.store === undefined) {
      this.store = await preferences.getPreferences(context, this.prefName);
    }
    await this.loadIfNeeded();
  }

  /** 启动预热：提前完成实例注册，避免首次搜索 / 播放时才等 */
  async warmUp(): Promise<void> {
    try {
      await this.ensureToken();
      hilog.info(0x0000, 'NekoIdentity', 'warmUp ok');
    } catch (error) {
      hilog.warn(0x0000, 'NekoIdentity', 'warmUp failed: %{public}s', (error as Error).message);
    }
  }

  /**
   * 生成某个请求的身份头。nonce 必须在调用前拿到——签名串里包含它。
   */
  async headers(method: string, path: string, rawQuery: string, bodyHash: string,
    nonce: string): Promise<Record<string, string>> {
    await this.ensureToken();
    if (this.keyPair === undefined || this.instanceId.length === 0 || this.token.length === 0) {
      throw new Error('客户端身份不可用');
    }
    const timestamp: number = Math.floor(Date.now() / 1000);
    const canonical: string = [
      'neko-client-v1',
      method.toUpperCase(),
      path,
      rawQuery,
      APIConfig.clientID,
      this.instanceId,
      APIConfig.clientPlatform,
      timestamp.toString(),
      bodyHash,
      nonce
    ].join('\n');

    const signature: Uint8Array = await this.sign(canonical);
    const header: Record<string, string> = {
      'X-Neko-Client-Id': APIConfig.clientID,
      'X-Neko-Client-Instance': this.instanceId,
      'X-Neko-Client-Token': this.token,
      'X-Neko-Client-Timestamp': timestamp.toString(),
      'X-Neko-Client-Signature': ClientIdentityService.base64url(signature)
    };
    return header;
  }

  /** 服务端判定实例令牌失效时调用：清掉令牌，下次自动重新注册。 */
  invalidate(): void {
    hilog.warn(0x0000, 'NekoIdentity', 'invalidate instance token');
    this.token = '';
    this.expiresAt = 0;
    this.persist();
  }

  // ---------------- 令牌生命周期 ----------------

  private async ensureToken(): Promise<void> {
    await this.loadIfNeeded();
    if (this.token.length > 0 && this.expiresAt > 0 &&
      this.expiresAt - Date.now() > this.renewMargin) {
      return;
    }
    if (this.pending !== undefined) {
      await this.pending;
      return;
    }
    this.pending = this.registerOrRenew();
    try {
      await this.pending;
    } finally {
      this.pending = undefined;
    }
  }

  private async registerOrRenew(): Promise<void> {
    if (this.instanceId.length > 0 && this.token.length > 0 && this.expiresAt > Date.now()) {
      try {
        await this.renew();
        return;
      } catch (error) {
        hilog.warn(0x0000, 'NekoIdentity', 'renew failed, fallback to register: %{public}s',
          (error as Error).message);
        this.token = '';
        this.expiresAt = 0;
      }
    }
    await this.register();
  }

  private async register(): Promise<void> {
    const keyPair: cryptoFramework.KeyPair = await this.ensureKeyPair();
    const iid: string = await this.ensureInstanceId();
    const challenge: string = await this.fetchChallenge('register');

    const publicKey: string = this.publicKeyUrlSafe();
    const timestamp: number = Math.floor(Date.now() / 1000);
    const canonical: string = [
      'neko-client-register-v1',
      APIConfig.clientID,
      APIConfig.clientPlatform,
      iid,
      publicKey,
      challenge,
      timestamp.toString()
    ].join('\n');
    const signature: Uint8Array = await this.sign(canonical);

    const body: string = JSON.stringify({
      'client_id': APIConfig.clientID,
      'platform': APIConfig.clientPlatform,
      'instance_id': iid,
      'public_key': publicKey,
      'challenge': challenge,
      'timestamp': timestamp,
      'signature': ClientIdentityService.base64url(signature)
    } as Record<string, Object>);

    const text: string = await this.postJSON(APIConfig.clientRegisterURL(), body);
    const envelope: OpenHarmonyEnvelope<OpenHarmonyRegisterData> =
      JSON.parse(text) as OpenHarmonyEnvelope<OpenHarmonyRegisterData>;
    const data: OpenHarmonyRegisterData | undefined = envelope.data;
    if (data === undefined || data.token === undefined || data.expires_at === undefined) {
      throw new Error(envelope.message ?? '客户端注册失败');
    }
    this.token = data.token;
    this.expiresAt = data.expires_at * 1000;
    this.persist();
    hilog.info(0x0000, 'NekoIdentity',
      'registered instance=%{public}s expires=%{public}d attestation=%{public}s',
      iid, data.expires_at, data.attestation ?? 'none');
  }

  private async renew(): Promise<void> {
    if (this.keyPair === undefined) {
      throw new Error('客户端身份不可用');
    }
    const challenge: string = await this.fetchChallenge('token');
    const timestamp: number = Math.floor(Date.now() / 1000);
    const canonical: string = [
      'neko-client-token-v1',
      APIConfig.clientID,
      APIConfig.clientPlatform,
      this.instanceId,
      challenge,
      timestamp.toString()
    ].join('\n');
    const signature: Uint8Array = await this.sign(canonical);

    const body: string = JSON.stringify({
      'client_id': APIConfig.clientID,
      'platform': APIConfig.clientPlatform,
      'instance_id': this.instanceId,
      'challenge': challenge,
      'timestamp': timestamp,
      'signature': ClientIdentityService.base64url(signature)
    } as Record<string, Object>);

    const text: string = await this.postJSON(APIConfig.clientTokenURL(), body);
    const envelope: OpenHarmonyEnvelope<OpenHarmonyRegisterData> =
      JSON.parse(text) as OpenHarmonyEnvelope<OpenHarmonyRegisterData>;
    const data: OpenHarmonyRegisterData | undefined = envelope.data;
    if (data === undefined || data.token === undefined || data.expires_at === undefined) {
      throw new Error(envelope.message ?? '实例令牌续签失败');
    }
    this.token = data.token;
    this.expiresAt = data.expires_at * 1000;
    this.persist();
    hilog.info(0x0000, 'NekoIdentity', 'renewed instance=%{public}s expires=%{public}d',
      this.instanceId, data.expires_at);
  }

  private async fetchChallenge(purpose: string): Promise<string> {
    const url: string = APIConfig.clientChallengeURL() +
      '?client_id=' + encodeURIComponent(APIConfig.clientID) +
      '&platform=' + encodeURIComponent(APIConfig.clientPlatform) +
      '&purpose=' + encodeURIComponent(purpose);
    const text: string = await this.request(url, http.RequestMethod.GET, '');
    const envelope: OpenHarmonyEnvelope<OpenHarmonyChallengeData> =
      JSON.parse(text) as OpenHarmonyEnvelope<OpenHarmonyChallengeData>;
    const data: OpenHarmonyChallengeData | undefined = envelope.data;
    if (data === undefined || data.challenge === undefined) {
      throw new Error(envelope.message ?? '获取客户端挑战失败');
    }
    return data.challenge;
  }

  private async postJSON(url: string, body: string): Promise<string> {
    return this.request(url, http.RequestMethod.POST, body);
  }

  private async request(url: string, method: http.RequestMethod, body: string): Promise<string> {
    const header: Record<string, string> = APIConfig.clientHeaders();
    if (method === http.RequestMethod.POST) {
      header['Content-Type'] = 'application/json';
    }
    if (APIConfig.clientSecret.length > 0) {
      header['X-Neko-Client-Secret'] = APIConfig.clientSecret;
    }
    const client: http.HttpRequest = http.createHttp();
    try {
      const response: http.HttpResponse = await client.request(url, {
        method: method,
        header: header,
        extraData: body.length > 0 ? body : undefined,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 20000,
        readTimeout: 20000
      });
      const text: string = (response.result as string) ?? '';
      if (response.responseCode !== 200) {
        hilog.error(0x0000, 'NekoIdentity', 'identity request %{public}d: %{public}s',
          response.responseCode, text.length > 120 ? text.substring(0, 120) : text);
        throw new Error(ClientIdentityService.errorMessage(text, response.responseCode));
      }
      return text;
    } finally {
      client.destroy();
    }
  }

  private static errorMessage(text: string, code: number): string {
    try {
      const envelope: OpenHarmonyEnvelope<Object> = JSON.parse(text) as OpenHarmonyEnvelope<Object>;
      if (envelope.message !== undefined && envelope.message.length > 0) {
        return envelope.message;
      }
    } catch (error) {
      // 非 JSON，忽略
    }
    return '客户端身份请求失败（' + code + '）';
  }

  // ---------------- 本机密钥 ----------------

  private async loadIfNeeded(): Promise<void> {
    if (this.loaded) {
      return;
    }
    this.loaded = true;
    if (this.store === undefined) {
      return;
    }
    const priBase64: string = (await this.store.get(this.keyPri, '')) as string;
    this.pubBase64 = (await this.store.get(this.keyPub, '')) as string;
    this.instanceId = (await this.store.get(this.keyIid, '')) as string;
    if (priBase64.length > 0 && this.pubBase64.length > 0) {
      try {
        const codec: util.Base64Helper = new util.Base64Helper();
        const priDer: Uint8Array = codec.decodeSync(priBase64);
        const pubDer: Uint8Array = codec.decodeSync(this.pubBase64);
        const generator: cryptoFramework.AsyKeyGenerator = await this.generatorOf();
        const pair: cryptoFramework.KeyPair = await new Promise<cryptoFramework.KeyPair>(
          (resolve, reject) => {
            // 公钥必须一起传：只传私钥时返回的 KeyPair 里 pubKey 是 undefined
            generator.convertKey({ data: pubDer }, { data: priDer },
              (err, data: cryptoFramework.KeyPair) => {
                if (err !== undefined && err !== null) {
                  reject(new Error('密钥加载失败: ' + err.message));
                } else {
                  resolve(data);
                }
              });
          });
        this.keyPair = pair;
      } catch (error) {
        hilog.warn(0x0000, 'NekoIdentity', 'load key failed: %{public}s', (error as Error).message);
        this.keyPair = undefined;
        this.pubBase64 = '';
      }
    }
    if (this.instanceId.length > 0) {
      this.token = (await this.store.get(this.keyToken, '')) as string;
      this.expiresAt = (await this.store.get(this.keyExpiry, 0)) as number;
    }
  }

  private async generatorOf(): Promise<cryptoFramework.AsyKeyGenerator> {
    if (this.generator === undefined) {
      this.generator = cryptoFramework.createAsyKeyGenerator('ECC256');
    }
    return this.generator;
  }

  private async ensureKeyPair(): Promise<cryptoFramework.KeyPair> {
    await this.loadIfNeeded();
    if (this.keyPair !== undefined) {
      return this.keyPair;
    }
    const generator: cryptoFramework.AsyKeyGenerator = await this.generatorOf();
    const pair: cryptoFramework.KeyPair = await generator.generateKeyPair();
    // 换了新密钥，旧的实例 ID 和令牌都不再有效
    this.instanceId = '';
    this.token = '';
    this.expiresAt = 0;
    this.keyPair = pair;
    this.pubBase64 = new util.Base64Helper()
      .encodeToStringSync(pair.pubKey.getEncodedDer('X509|UNCOMPRESSED').data);
    this.persist();
    hilog.info(0x0000, 'NekoIdentity', 'generated new instance key');
    return pair;
  }

  private async ensureInstanceId(): Promise<string> {
    await this.loadIfNeeded();
    if (this.instanceId.length > 0) {
      return this.instanceId;
    }
    this.instanceId = util.generateRandomUUID(false);
    this.persist();
    return this.instanceId;
  }

  private async persist(): Promise<void> {
    if (this.store === undefined) {
      return;
    }
    if (this.keyPair !== undefined) {
      const priDer: Uint8Array = this.keyPair.priKey.getEncodedDer('PKCS8').data;
      await this.store.put(this.keyPri, new util.Base64Helper().encodeToStringSync(priDer));
    }
    if (this.pubBase64.length > 0) {
      await this.store.put(this.keyPub, this.pubBase64);
    }
    await this.store.put(this.keyIid, this.instanceId);
    await this.store.put(this.keyToken, this.token);
    await this.store.put(this.keyExpiry, this.expiresAt);
    await this.store.flush();
  }

  // ---------------- 签名与编码 ----------------

  private signAlg: string = '';

  /** 探测 cryptoFramework 支持的 ECC 签名算法名（不同版本字符串不一样） */
  private resolveSignAlg(): string {
    if (this.signAlg.length > 0) {
      return this.signAlg;
    }
    const candidates: string[] = [
      'ECC256|SHA256', 'ECC|SHA256', 'ECDSA|SHA256', 'ECDSA256|SHA256',
      'SHA256|ECC256', 'SHA256|ECC', 'SHA256withECDSA', 'ECC256'
    ];
    for (const name of candidates) {
      try {
        cryptoFramework.createSign(name);
        hilog.info(0x0000, 'NekoIdentity', 'sign alg OK: %{public}s', name);
        this.signAlg = name;
        return name;
      } catch (error) {
        hilog.info(0x0000, 'NekoIdentity', 'sign alg no: %{public}s', name);
      }
    }
    throw new Error('没有可用的 ECC 签名算法');
  }

  private async sign(canonical: string): Promise<Uint8Array> {
    if (this.keyPair === undefined) {
      throw new Error('客户端身份不可用');
    }
    const signer: cryptoFramework.Sign = cryptoFramework.createSign(this.resolveSignAlg());
    await signer.init(this.keyPair.priKey);
    const payload: Uint8Array = new util.TextEncoder().encodeInto(canonical);
    await signer.update({ data: payload });
    const signature: cryptoFramework.DataBlob = await signer.sign(null);
    return signature.data;
  }

  /** 请求体哈希：无体用空哈希，multipart 用固定值 "-" */
  static async bodyHashAsync(body: string): Promise<string> {
    if (body.length === 0) {
      return ClientIdentityService.emptyBodyHash;
    }
    const md: cryptoFramework.Md = cryptoFramework.createMd('SHA256');
    await md.update({ data: new util.TextEncoder().encodeInto(body) });
    const digest: cryptoFramework.DataBlob = await md.digest();
    let hex: string = '';
    for (let i: number = 0; i < digest.data.length; i++) {
      const byte: number = digest.data[i];
      hex += (byte < 16 ? '0' : '') + byte.toString(16);
    }
    return hex;
  }

  static readonly emptyBodyHash: string =
    'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
  static readonly multipartBodyHash: string = '-';

  /** 存的是标准 base64，这里转 base64url（去掉 padding） */
  private publicKeyUrlSafe(): string {
    if (this.pubBase64.length === 0) {
      throw new Error('客户端公钥缺失');
    }
    return this.pubBase64.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
  }

  static base64url(data: Uint8Array): string {
    return new util.Base64Helper().encodeToStringSync(data)
      .replace(/\+/g, '-')
      .replace(/\//g, '_')
      .replace(/=+$/g, '');
  }
}

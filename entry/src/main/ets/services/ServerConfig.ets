import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { http } from '@kit.NetworkKit';

/** 来源类型 */
export enum SourceKind {
  Neko = 'neko',
  NekoCustom = 'nekoCustom',
  Subsonic = 'subsonic',
  Jellyfin = 'jellyfin',
  Generic = 'generic'
}

export interface SourceMeta {
  kind: SourceKind;
  title: string;
  subtitle: string;
  /** 当前是否已支持播放（其余类型先支持保存与连通性校验） */
  playbackSupported: boolean;
}

/**
 * 接口服务器配置。
 *
 * 应用不内置曲库、不默认连接任何服务；来源类型与地址由用户首次启动时选择，
 * 内容来源与合法性由用户自行负责。
 */
export class ServerConfig {
  static readonly presetURL: string = 'https://music.nekocore.cn';

  static readonly sources: SourceMeta[] = [
    { kind: SourceKind.Neko, title: '使用 NekoMusic 资源', subtitle: '社区常用地址，由第三方提供与维护', playbackSupported: true },
    { kind: SourceKind.NekoCustom, title: '自配置 NekoMusic 地址', subtitle: '你自己的 NekoMusic 协议服务器', playbackSupported: true },
    { kind: SourceKind.Subsonic, title: 'Subsonic 兼容服务器', subtitle: 'Navidrome、Airsonic 等，需要账号密码', playbackSupported: false },
    { kind: SourceKind.Jellyfin, title: 'Jellyfin / Emby', subtitle: '需要服务器地址', playbackSupported: false },
    { kind: SourceKind.Generic, title: '通用接口', subtitle: '任意 HTTP 接口，仅保存地址与令牌', playbackSupported: false }
  ];

  private static readonly PREF: string = 'neko_server';
  private static kind: string = '';
  private static base: string = '';
  private static username: string = '';
  private static password: string = '';
  private static token: string = '';
  private static accepted: boolean = false;
  private static store: preferences.Preferences | undefined = undefined;

  static async init(context: common.Context): Promise<void> {
    if (ServerConfig.store !== undefined) {
      return;
    }
    const store = await preferences.getPreferences(context, ServerConfig.PREF);
    ServerConfig.store = store;
    ServerConfig.kind = await store.get('kind', '') as string;
    ServerConfig.base = await store.get('base', '') as string;
    ServerConfig.username = await store.get('username', '') as string;
    ServerConfig.password = await store.get('password', '') as string;
    ServerConfig.token = await store.get('token', '') as string;
    ServerConfig.accepted = await store.get('accepted', false) as boolean;
  }

  static get baseURL(): string {
    return ServerConfig.base;
  }

  static get currentKind(): string {
    return ServerConfig.kind;
  }

  static get isReady(): boolean {
    return ServerConfig.accepted && ServerConfig.kind.length > 0 && ServerConfig.base.length > 0;
  }

  /** 非 NekoMusic 协议当前还不能播放 */
  static get isPlaybackSupported(): boolean {
    return ServerConfig.kind === SourceKind.Neko || ServerConfig.kind === SourceKind.NekoCustom;
  }

  static get acceptedTerms(): boolean {
    return ServerConfig.accepted;
  }

  static async acceptTerms(): Promise<void> {
    ServerConfig.accepted = true;
    await ServerConfig.persist('accepted', 'true');
  }

  static metaOf(kind: string): SourceMeta | undefined {
    const found = ServerConfig.sources.filter((item: SourceMeta) => item.kind === kind);
    return found.length > 0 ? found[0] : undefined;
  }

  /**
   * 校验并保存。成功返回空字符串，失败返回原因。
   */
  static async verifyAndSave(kind: string, rawUrl: string, user: string, pass: string, tk: string): Promise<string> {
    let url: string = rawUrl.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      return '地址无效，请填入以 http:// 或 https:// 开头的完整地址';
    }
    if (kind === SourceKind.Subsonic && user.length === 0) {
      return '请填写用户名';
    }

    if (kind !== SourceKind.Neko) {
      const error: string = await ServerConfig.probe(kind, url, user, pass);
      if (error.length > 0) {
        return error;
      }
    }

    ServerConfig.kind = kind;
    ServerConfig.base = kind === SourceKind.Neko ? ServerConfig.presetURL : url;
    ServerConfig.username = user;
    ServerConfig.password = pass;
    ServerConfig.token = tk;
    await ServerConfig.persistAll();
    return '';
  }

  private static async probe(kind: string, base: string, user: string, pass: string): Promise<string> {
    let target: string = base;
    if (kind === SourceKind.NekoCustom) {
      target = base + '/api/music/latest?limit=1';
    } else if (kind === SourceKind.Subsonic) {
      target = base + '/rest/ping.view?u=' + encodeURIComponent(user) + '&p=' + encodeURIComponent(pass)
        + '&v=1.16.1&c=NekoMusic&f=json';
    } else if (kind === SourceKind.Jellyfin) {
      target = base + '/System/Info/Public';
    }

    const client = http.createHttp();
    try {
      const response = await client.request(target, {
        method: http.RequestMethod.GET,
        connectTimeout: 12000,
        readTimeout: 12000,
        header: { 'Accept': 'application/json' }
      });
      const code: number = response.responseCode as number;
      if (code < 200 || code >= 400) {
        return '服务器返回 ' + code + '，请检查地址与凭据';
      }
      if (kind === SourceKind.Subsonic) {
        const text: string = typeof response.result === 'string' ? response.result as string : '';
        if (!text.includes('"ok"')) {
          return '认证失败：请检查用户名与密码';
        }
      }
      return '';
    } catch (error) {
      return '无法连接：' + (error as Error).message;
    } finally {
      client.destroy();
    }
  }

  private static async persist(key: string, value: string): Promise<void> {
    const store = ServerConfig.store;
    if (store !== undefined) {
      await store.put(key, value);
      await store.flush();
    }
  }

  private static async persistAll(): Promise<void> {
    const store = ServerConfig.store;
    if (store === undefined) {
      return;
    }
    await store.put('kind', ServerConfig.kind);
    await store.put('base', ServerConfig.base);
    await store.put('username', ServerConfig.username);
    await store.put('password', ServerConfig.password);
    await store.put('token', ServerConfig.token);
    await store.flush();
  }
}

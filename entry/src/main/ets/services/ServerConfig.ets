import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

/**
 * 接口服务器配置。
 *
 * 应用本身不内置、也不默认连接任何服务；首次启动由用户明确选择或填写地址，
 * 内容来源与合法性由用户自行负责。
 */
export class ServerConfig {
  /** 社区常用地址（仅供用户选择，不是默认值） */
  static readonly presetURL: string = 'https://music.nekocore.cn';

  private static readonly PREF: string = 'neko_server';
  private static base: string = '';
  private static accepted: boolean = false;
  private static store: preferences.Preferences | undefined = undefined;

  static async init(context: common.Context): Promise<void> {
    if (ServerConfig.store !== undefined) {
      return;
    }
    const store = await preferences.getPreferences(context, ServerConfig.PREF);
    ServerConfig.store = store;
    ServerConfig.base = await store.get('base', '') as string;
    ServerConfig.accepted = await store.get('accepted', false) as boolean;
  }

  static get baseURL(): string {
    return ServerConfig.base;
  }

  static get hasAcceptedTerms(): boolean {
    return ServerConfig.accepted;
  }

  /** 首次启动流程是否走完 */
  static get isReady(): boolean {
    return ServerConfig.accepted && ServerConfig.base.length > 0;
  }

  static async acceptTerms(): Promise<void> {
    ServerConfig.accepted = true;
    const store = ServerConfig.store;
    if (store !== undefined) {
      await store.put('accepted', true);
      await store.flush();
    }
  }

  static async usePreset(): Promise<void> {
    await ServerConfig.apply(ServerConfig.presetURL);
  }

  /** 自配置：只接受 http/https，去掉结尾斜杠 */
  static async useCustom(raw: string): Promise<boolean> {
    let text: string = raw.trim();
    while (text.endsWith('/')) {
      text = text.substring(0, text.length - 1);
    }
    if (!text.startsWith('http://') && !text.startsWith('https://')) {
      return false;
    }
    const rest: string = text.replace('https://', '').replace('http://', '');
    if (rest.length === 0 || rest.indexOf('.') < 0) {
      return false;
    }
    await ServerConfig.apply(text);
    return true;
  }

  private static async apply(url: string): Promise<void> {
    ServerConfig.base = url;
    const store = ServerConfig.store;
    if (store !== undefined) {
      await store.put('base', url);
      await store.flush();
    }
  }
}

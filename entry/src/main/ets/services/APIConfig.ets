import { ServerConfig } from './ServerConfig';

/**
 * 后端配置与请求头。
 * 后端启用了防爬与客户端识别：请求头不完整会被判成爬虫（403 或降级成 SEO 页面）。
 */
export class APIConfig {
  /**
   * 接口地址由用户首次启动时选择或填写（见 ServerConfig）。
   * 应用本身不内置、也不默认连接任何服务。
   */
  static get baseURL(): string {
    return ServerConfig.baseURL;
  }
  static readonly clientVersion: string = "1.0.0";
  /** 平台标识：必须与后端分配的 Client ID 绑定平台一致 */
  static readonly clientPlatform: string = "other";
  /** 自报客户端：<平台>+<版本> */
  static readonly clientHeader: string = APIConfig.clientPlatform + "+" + APIConfig.clientVersion;

  /** 官方客户端 UA：严格格式 NekoMusic-<平台>/<版本>，后端据此识别为官方客户端 */
  static readonly userAgent: string = "NekoMusic-harmony/" + APIConfig.clientVersion;

  /** 浏览器指纹头（仅伪装场景使用） */
  static readonly browserUserAgent: string =
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36";

  // MARK: - 客户端身份（Client ID）
  //
  // 后端要求除白名单外的所有 /api/*、/loser/* 动态请求证明「应用 + 安装实例」身份：
  // Client ID、实例 UUID、实例短期令牌、每请求签名。Client ID 由管理员分配并绑定平台。
  static readonly clientID: string = "nkc_sec_6b7746c05da14dd2a7e3";
  /** 机密客户端 secret：注册实例时必须一起提供 */
  static readonly clientSecret: string = "7GFSIStbPK4dUS9Hx8ZNih48l1fW9R23h_idxuBDcxc";

  static clientHeaders(): Record<string, string> {
    const headers: Record<string, string> = {
      "User-Agent": APIConfig.userAgent,
      "X-Neko-Client": APIConfig.clientHeader,
      "Accept": "application/json, text/plain, */*",
      "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
      "Accept-Encoding": "identity",
      "X-Requested-With": "XMLHttpRequest",
      "sec-ch-ua": "\"Chromium\";v=\"141\", \"Not?A_Brand\";v=\"24\"",
      "sec-ch-ua-mobile": "?0",
      "sec-ch-ua-platform": "\"macOS\"",
      "Referer": APIConfig.baseURL + "/"
    };
    return headers;
  }

  /** 需要 nonce 的接口白名单（这些不需要） */
  static requiresNonce(path: string): boolean {
    const whitelist: string[] = [
      "/api/replay/",
      "/api/music/cover/",
      "/api/user/avatar/",
      "/media/",
      "/assets/",
      "/loser/"
    ];
    for (const prefix of whitelist) {
      if (path.startsWith(prefix)) {
        return false;
      }
    }
    const exact: string[] = ["/api/music/latest", "/api/music/ranking"];
    for (const p of exact) {
      if (path === p) {
        return false;
      }
    }
    return true;
  }

  /** 不需要「客户端身份」（实例令牌 + 请求签名）的接口，见后端文档第 7 节 */
  static requiresClientIdentity(path: string): boolean {
    const bootstrapPrefixes: string[] = [
      "/api/client/",
      "/api/replay/",
      "/api/music/cover/",
      "/api/user/avatar/",
      "/media/",
      "/assets/"
    ];
    for (const prefix of bootstrapPrefixes) {
      if (path.startsWith(prefix)) {
        return false;
      }
    }
    const exemptPaths: string[] = [
      "/api/music/latest",
      "/api/music/ranking",
      "/api/user/qrlogin/status",
      "/api/user/notifications/stream",
      "/api/payment/zpay/notify"
    ];
    for (const p of exemptPaths) {
      if (path.startsWith(p)) {
        return false;
      }
    }
    // 歌单导入进度 SSE 不签名，其它 /loser/* 仍要
    if (path.startsWith("/loser/") && path.endsWith("/pull")) {
      return false;
    }
    return true;
  }

  // MARK: - 客户端身份自举
  static clientChallengeURL(): string {
    return APIConfig.baseURL + "/api/client/challenge";
  }

  static clientRegisterURL(): string {
    return APIConfig.baseURL + "/api/client/register";
  }

  static clientTokenURL(): string {
    return APIConfig.baseURL + "/api/client/token";
  }

  // MARK: - 防重放
  static replayChallengeURL(): string {
    return APIConfig.baseURL + "/api/replay/challenge";
  }

  static replayNonceURL(): string {
    return APIConfig.baseURL + "/api/replay/nonce";
  }

  // MARK: - 音乐
  static musicLatestURL(): string {
    return APIConfig.baseURL + "/api/music/latest";
  }

  static musicRankingURL(): string {
    return APIConfig.baseURL + "/api/music/ranking";
  }

  static musicSearchURL(): string {
    return APIConfig.baseURL + "/api/music/search";
  }

  static musicFileURL(id: number, quality: string = "hq"): string {
    return APIConfig.baseURL + "/api/music/file/" + id + "?quality=" + quality;
  }

  static musicCoverURL(id: number): string {
    return APIConfig.baseURL + "/api/music/cover/" + id;
  }

  static musicInfoURL(id: number): string {
    return APIConfig.baseURL + "/api/music/info/" + id;
  }

  static lyricsURL(id: number): string {
    return APIConfig.baseURL + "/api/music/lyrics/" + id;
  }

  // MARK: - 用户
  static myPlaylistsURL(): string {
    return APIConfig.baseURL + '/api/user/playlists';
  }

  static playlistCreateURL(): string {
    return APIConfig.baseURL + '/api/user/playlist/create';
  }

  static playlistDeleteURL(): string {
    return APIConfig.baseURL + '/api/user/playlist/delete';
  }

  static playlistMusicURL(playlistId: number): string {
    return APIConfig.baseURL + '/api/user/playlist/music/' + playlistId;
  }

  static playlistAddMusicURL(): string {
    return APIConfig.baseURL + '/api/user/playlist/music/add';
  }

  static playlistRemoveMusicURL(): string {
    return APIConfig.baseURL + '/api/user/playlist/music/remove';
  }

  static favoritesURL(): string {
    return APIConfig.baseURL + "/api/user/favorites";
  }

  static removeFavoriteURL(musicId: number): string {
    return APIConfig.baseURL + "/api/user/favorites/" + musicId;
  }

  static loginURL(): string {
    return APIConfig.baseURL + "/api/user/login";
  }

  static dailyRecommendURL(): string {
    return APIConfig.baseURL + "/api/user/recommendations/daily";
  }

  /** 把相对路径补成完整地址 */
  static buildFullURL(path: string): string {
    if (path.startsWith("http")) {
      return path;
    }
    if (path.startsWith("/")) {
      return APIConfig.baseURL + path;
    }
    return APIConfig.baseURL + "/" + path;
  }
}

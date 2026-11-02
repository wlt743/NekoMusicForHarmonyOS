import { router } from '@kit.ArkUI';
import { ServerConfig, SourceMeta, SourceKind } from '../services/ServerConfig';

/**
 * 来源选择 + 配置表单。首次启动页和设置页共用。
 */
@Component
export struct SourceSetup {
  /** 保存成功后是否直接进入主界面（首次启动用） */
  private enterAfterSave: boolean = false;
  private onSaved?: () => void;

  @State private selected: string = '';
  @State private url: string = '';
  @State private username: string = '';
  @State private password: string = '';
  @State private token: string = '';
  @State private busy: boolean = false;
  @State private errorText: string = '';

  private isPreset(kind: string): boolean {
    return kind === SourceKind.Neko;
  }

  private needsAccount(kind: string): boolean {
    return kind === SourceKind.Subsonic || kind === SourceKind.Jellyfin;
  }

  private save(): void {
    this.busy = true;
    this.errorText = '';
    ServerConfig.verifyAndSave(this.selected, this.url, this.username, this.password, this.token)
      .then((error: string) => {
        this.busy = false;
        if (error.length > 0) {
          this.errorText = error;
          return;
        }
        // 换源后清空导航栈并回首页，避免残留上一个服务器的页面与数据
        router.clear();
        router.replaceUrl({ url: 'pages/Index' });
      });
  }

  build() {
    Column({ space: 10 }) {
      ForEach(ServerConfig.sources, (item: SourceMeta) => {
        Column({ space: 6 }) {
          Row({ space: 8 }) {
            Text(item.title)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor('#1A1A1A')
            if (!item.playbackSupported) {
              Text('播放适配中')
                .fontSize(10)
                .fontColor('#C46A00')
                .backgroundColor('#FFF0DB')
                .borderRadius(8)
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            }
            Blank()
            Text(this.selected === item.kind ? '收起' : '配置')
              .fontSize(13)
              .fontColor('#E5484D')
          }
          .width('100%')
          Text(item.subtitle)
            .fontSize(12)
            .fontColor('#8A8A8A')
            .width('100%')

          if (this.selected === item.kind && !this.isPreset(item.kind)) {
            Column({ space: 8 }) {
              TextInput({ placeholder: 'https://你的服务器地址', text: this.url })
                .height(44)
                .backgroundColor('#F2F2F5')
                .onChange((value: string) => { this.url = value; })
              if (this.needsAccount(item.kind)) {
                TextInput({ placeholder: '用户名', text: this.username })
                  .height(44)
                  .backgroundColor('#F2F2F5')
                  .onChange((value: string) => { this.username = value; })
                TextInput({ placeholder: '密码', text: this.password })
                  .height(44)
                  .type(InputType.Password)
                  .backgroundColor('#F2F2F5')
                  .onChange((value: string) => { this.password = value; })
              }
              if (this.errorText.length > 0) {
                Text(this.errorText)
                  .fontSize(12)
                  .fontColor('#E5484D')
                  .width('100%')
              }
              Button(this.busy ? '正在校验…' : '测试连接并保存')
                .width('100%')
                .height(44)
                .enabled(!this.busy && this.url.trim().length > 0)
                .backgroundColor('#E5484D')
                .onClick(() => { this.save(); })
            }
            .width('100%')
            .padding({ top: 6 })
          }
        }
        .width('100%')
        .padding(14)
        .backgroundColor('#FFFFFF')
        .borderRadius(16)
        .onClick(() => {
          if (this.isPreset(item.kind)) {
            ServerConfig.verifyAndSave(item.kind, ServerConfig.presetURL, '', '', '').then((error: string) => {
              if (error.length === 0) {
                router.clear();
                router.replaceUrl({ url: 'pages/Index' });
              }
            });
          } else {
            this.selected = this.selected === item.kind ? '' : item.kind;
            this.errorText = '';
          }
        })
      }, (item: SourceMeta) => item.kind)
    }
    .width('100%')
  }
}

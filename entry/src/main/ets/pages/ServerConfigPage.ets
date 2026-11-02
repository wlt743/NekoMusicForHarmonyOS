import { router } from '@kit.ArkUI';
import { ServerConfig } from '../services/ServerConfig';

/**
 * 设置里的「接口服务器」：运行期也能改地址。
 */
@Entry
@Component
struct ServerConfigPage {
  @State private current: string = ServerConfig.baseURL;
  @State private input: string = '';
  @State private message: string = '';
  @State private isError: boolean = false;

  private sourceLabel(): string {
    if (this.current.length === 0) {
      return '未配置';
    }
    return this.current === ServerConfig.presetURL ? '社区常用地址' : '自定义';
  }

  build() {
    Column() {
      Row() {
        Text('‹ 返回')
          .fontSize(16)
          .fontColor('#E5484D')
          .onClick(() => { router.back(); })
        Text('接口服务器')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .margin({ left: 12 })
        Blank()
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })

      Scroll() {
        Column({ space: 16 }) {
          // 当前配置
          Column({ space: 10 }) {
            Text('当前配置')
              .fontSize(13)
              .fontColor('#999999')
              .width('100%')
            Row() {
              Text('地址').fontSize(15)
              Blank()
              Text(this.current.length > 0 ? this.current : '未配置')
                .fontSize(13)
                .fontColor('#666666')
                .layoutWeight(1)
                .textAlign(TextAlign.End)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .width('100%')
            Row() {
              Text('来源').fontSize(15)
              Blank()
              Text(this.sourceLabel())
                .fontSize(13)
                .fontColor('#666666')
            }
            .width('100%')
          }
          .width('100%')
          .padding(18)
          .backgroundColor('#FFFFFF')
          .borderRadius(22)

          // 修改
          Column({ space: 12 }) {
            Text('修改')
              .fontSize(13)
              .fontColor('#999999')
              .width('100%')
            Button('使用社区常用地址')
              .width('100%')
              .height(44)
              .backgroundColor('#F2F2F5')
              .fontColor('#333333')
              .onClick(() => {
                ServerConfig.usePreset().then(() => {
                  this.current = ServerConfig.baseURL;
                  this.isError = false;
                  this.message = '已切换到社区常用地址';
                });
              })

            TextInput({ placeholder: 'https://你的服务器地址', text: this.input })
              .height(46)
              .backgroundColor('#F2F2F5')
              .onChange((value: string) => { this.input = value; })

            Button('保存自定义地址')
              .width('100%')
              .height(46)
              .backgroundColor('#E5484D')
              .enabled(this.input.trim().length > 0)
              .onClick(() => {
                ServerConfig.useCustom(this.input).then((ok: boolean) => {
                  if (ok) {
                    this.current = ServerConfig.baseURL;
                    this.isError = false;
                    this.message = '地址已保存，返回后重新加载即可生效';
                  } else {
                    this.isError = true;
                    this.message = '地址无效，请填入以 http:// 或 https:// 开头的完整地址';
                  }
                });
              })

            if (this.message.length > 0) {
              Text(this.message)
                .fontSize(12)
                .fontColor(this.isError ? '#E5484D' : '#2E9E5B')
                .width('100%')
            }
          }
          .width('100%')
          .padding(18)
          .backgroundColor('#FFFFFF')
          .borderRadius(22)

          Text('切换地址后实例身份会失效，需要重新注册；已缓存的列表与封面可在「清除缓存」处理。')
            .fontSize(12)
            .fontColor('#999999')
            .width('100%')
        }
        .padding({ left: 16, right: 16, bottom: 40 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F6F8')
  }
}

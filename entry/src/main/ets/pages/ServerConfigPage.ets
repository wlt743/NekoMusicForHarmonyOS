import { router } from '@kit.ArkUI';
import { ServerConfig } from '../services/ServerConfig';
import { SourceSetup } from '../components/SourceSetup';

@Entry
@Component
struct ServerConfigPage {
  @State private kindLabel: string = '';
  @State private address: string = '';
  @State private refreshTick: number = 0;

  aboutToAppear(): void {
    this.refresh();
  }

  private refresh(): void {
    this.address = ServerConfig.baseURL;
    const meta = ServerConfig.metaOf(ServerConfig.currentKind);
    this.kindLabel = meta !== undefined ? meta.title : '未配置';
    this.refreshTick = this.refreshTick + 1;
  }

  build() {
    Column() {
      Row() {
        Text('‹ 返回').fontSize(16).fontColor('#E5484D').onClick(() => { router.back(); })
        Text('接口服务器').fontSize(18).fontWeight(FontWeight.Bold).margin({ left: 12 })
        Blank()
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })

      Scroll() {
        Column({ space: 16 }) {
          Column({ space: 10 }) {
            Text('当前配置').fontSize(13).fontColor('#999999').width('100%')
            Row() {
              Text('来源').fontSize(15)
              Blank()
              Text(this.kindLabel).fontSize(13).fontColor('#666666')
            }.width('100%')
            Row() {
              Text('地址').fontSize(15)
              Blank()
              Text(this.address.length > 0 ? this.address : '未配置')
                .fontSize(13).fontColor('#666666')
                .layoutWeight(1).textAlign(TextAlign.End).maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }.width('100%')
          }
          .width('100%')
          .padding(18)
          .backgroundColor('#FFFFFF')
          .borderRadius(22)

          Text('切换来源')
            .fontSize(13).fontColor('#999999').width('100%')

          SourceSetup({ enterAfterSave: false, onSaved: () => { this.refresh(); } })

          Text('切换来源后会重新注册客户端实例；已缓存的列表与封面可在「清除缓存」处理。')
            .fontSize(12).fontColor('#999999').width('100%')
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

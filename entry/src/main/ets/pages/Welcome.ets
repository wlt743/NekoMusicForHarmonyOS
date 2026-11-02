import { router } from '@kit.ArkUI';
import { ServerConfig } from '../services/ServerConfig';
import { SourceSetup } from '../components/SourceSetup';

/**
 * 首次启动：先确认声明，再选择接口服务器。
 * 应用不内置任何服务地址，也不默认连接任何服务器。
 */
@Entry
@Component
struct Welcome {
  @State private step: number = 0;
  @State private agreed: boolean = false;
  @State private customInput: string = '';
  @State private errorText: string = '';

  private readonly sections: Record<string, string[]> = {
    '一、技术架构': [
      '1. 本应用是纯本地音乐播放器客户端，开发者不运营音乐服务，不存储、不上传、不中转、不筛选、不编辑任何音乐内容。',
      '2. 应用不内置曲库，也不默认连接任何接口服务器。首次启动时，需要你自行选择或填写接口地址，内容来源完全由你决定。',
      '3. 播放与下载均在你的设备与你指定的服务器之间直接进行，开发者不参与该传输，也不会在自有服务器上保存内容副本。',
      '4. 应用对第三方接口的适配属于通用技术能力，不代表开发者与该服务器存在合作、授权或背书关系。'
    ],
    '二、使用边界': [
      '1. 你应自行确保所使用的接口服务器及获取的内容具有合法授权。',
      '2. 禁止利用本应用接入、下载或传播未经授权的音乐作品。',
      '3. 禁止发布盗版链接、侵权资源教程，或引导他人获取无版权内容。'
    ],
    '三、通知与处置': [
      '如权利人、平台或管理方就某一具体接口地址发出含有初步证据的通知，开发者将对该地址断开适配或屏蔽，并留存处理记录。该处置针对具体地址，不构成对其他地址的普遍审查义务。'
    ],
    '四、责任边界': [
      '开发者不对你自行配置的第三方服务器内容承担审核责任，你需要自行承担合法使用义务。本声明不构成对任何第三方内容的授权、认可或背书。'
    ]
  };

  private titles(): string[] {
    return Object.keys(this.sections);
  }

  @Builder
  private termsStep() {
    Column() {
      Scroll() {
        Column({ space: 12 }) {
          Text('NekoMusic')
            .fontSize(30)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
            .width('100%')
          Text('使用前请阅读以下声明')
            .fontSize(14)
            .fontColor('#99FFFFFF')
            .width('100%')

          ForEach(this.titles(), (title: string) => {
            Column({ space: 6 }) {
              Text(title)
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor('#FFFFFF')
                .width('100%')
              ForEach(this.sections[title], (line: string) => {
                Text(line)
                  .fontSize(13)
                  .fontColor('#B3FFFFFF')
                  .lineHeight(20)
                  .width('100%')
              })
            }
            .width('100%')
            .margin({ bottom: 4 })
          }, (title: string) => title)

          Text('勾选并继续，表示你已阅读、理解并同意上述声明。')
            .fontSize(12)
            .fontColor('#80FFFFFF')
            .width('100%')
            .margin({ top: 8 })
        }
        .padding(20)
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)

      Column({ space: 12 }) {
        Row({ space: 10 }) {
          Checkbox({ name: 'agree' })
            .select(this.agreed)
            .onChange((value: boolean) => { this.agreed = value })
          Text('我已阅读并同意上述声明')
            .fontSize(14)
            .fontColor('#E6FFFFFF')
            .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 20, right: 20 })

        Button('继续')
          .width('90%')
          .height(46)
          .enabled(this.agreed)
          .backgroundColor(this.agreed ? '#7C5CFF' : '#33FFFFFF')
          .onClick(() => {
            ServerConfig.acceptTerms().then(() => { this.step = 1; });
          })
      }
      .width('100%')
      .padding({ bottom: 20 })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private choiceStep() {
    Column({ space: 14 }) {
      Text('选择音乐来源')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
        .width('100%')
      Text('本应用不内置曲库。请选择来源类型，或填写你自己的服务器。内容来源与合法性由你自行确认。')
        .fontSize(13)
        .fontColor('#99FFFFFF')
        .width('100%')

      Scroll() {
        Column() {
          SourceSetup({ enterAfterSave: true })
        }
        .width('100%')
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)

      Text('返回声明确认')
        .fontSize(13)
        .fontColor('#80FFFFFF')
        .onClick(() => { this.step = 0; })
    }
    .width('100%')
    .height('100%')
    .padding(20)
  }

  build() {
    Column() {
      if (this.step === 0) {
        this.termsStep()
      } else {
        this.choiceStep()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#0B0B0F')
  }
}

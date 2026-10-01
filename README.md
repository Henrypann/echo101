# Echo

给爷爷奶奶用的 iPhone 应用。打开就是「说一句」：点一下，说中文，听到这句自己的英文。另外三个标签是「单词」「今天」「爸妈」。

家庭自用。不需要 App Store、TestFlight 或付费开发者账号。用 Xcode 的免费 Apple ID，经 USB 装到 iPhone XS（A12，最高 iOS 18）。最低系统 iOS 17。

家庭数据只在这台手机上。仓库里没有孩子姓名、真实录音、API Key 或家里的句子。

## 四个标签

| 标签 | 做什么 |
| --- | --- |
| 说一句 | 默认页。点一下开始、再点一下停止。听到 3 秒安静会自己停，最长 20 秒。先对本地句库；对不上、并且爸妈开过一次同意、也填了 Key，才把识别出的文字发给模型。模型句子标「待爸妈确认」，不会自动进句库。 |
| 单词 | 常用词和置顶的「杭州旅行」。点一行先读这个词，再打开详情。详情里的英文单词可以单独点读；「播放」读单词，再慢读例句，再正常读例句。 |
| 今天 | 今天说过的句子，按时间排列。点一行听英文（先慢后正常）。有孩子跟读时可以「听孩子」。不能改、不能删。 |
| 爸妈 | 点进去是普通页面，写着「这里是爸妈用的」，并显示还有几句等确认。按住「按住 3 秒进入」三秒，外圈转满才进去。离开这个标签或 App 进后台会重新锁上。API Key 那一页才用面容或密码。 |

离开超过 10 分钟再回来，会回到「说一句」，爸妈页也会重新锁上。不到 10 分钟只重新锁爸妈，停在刚才的标签。

## 爸妈一次性设置

1. 用 Mac 上的 Xcode 打开 `Echo101.xcodeproj`，用免费 Apple ID 登录，Bundle ID 保持 `com.henrypann.echo101`，用 USB 装到 iPhone。免费签名大约 7 天过期，过期后重新签名再装一次。免费账号最多同时签 3 台设备。
2. 第一次打开时允许麦克风，并允许语音识别。识别用系统的普通话（中国大陆）设备端识别（`SFSpeechRecognizer`，`zh-CN`，`requiresOnDeviceRecognition = true`），不使用只在 iOS 26 才有的 Speech API。
3. 在系统设置里下载「普通话（中国大陆）」听写资源。没有这份资源时，App 会说「请让爸妈看看手机」，并在爸妈页记一条待处理事项。
4. 下载增强或高质量的美式英语声音（Enhanced / Premium，US English）。「说一句」和「单词」都用这一条英语声线。爸妈页可以换已安装的英语声音。
5. 需要更大的字时，在系统设置里把文字调大。老人这一侧的字不小于 20pt。
6. 可选：打开引导式访问，避免误触 Home 键。
7. 模型不是必须的。要对不上句库时才用 DeepSeek 或小米 MiMo。爸妈页打开一次同意即可（发出去的是识别后的中文文字，不是录音）。默认只走 Wi-Fi；要走蜂窝时再打开「允许使用蜂窝数据」。Key 只存在这台手机的钥匙串里。

## 杭州读音

「杭州旅行」里的专名可以在 `Sources/EchoCore/Resources/Vocabulary.json` 的 `ipa` 字段写音标。有这个字段时，朗读会带上 `AVSpeechSynthesisIPANotationAttribute`。

Henry 需要在 iPhone XS 上把每一条杭州词条听一遍。系统英语把拼音读错的，把覆盖音标写进对应条目的 `ipa`。

## 单词和星星

词表是包内只读 JSON。置顶分类靠 `pinned`，改数据就能换掉「杭州旅行」，不用改界面。分类顺序固定，不按使用次数重排，也没有上锁。

常用词和分类图标用 [OpenMoji](https://openmoji.org) 彩色插画（CC BY-SA 4.0），打在包里，大约 192 像素的 PNG。每条词的 `image` 是资源名；找不到这张图时，界面退回原来的 emoji。杭州旅行用维基共享资源上允许再使用的照片（公有领域、CC0、CC BY、CC BY-SA），长边大约 800 像素的 JPEG，同样打在包里，打开单词时不联网。照片的作者、许可和文件页写在词条的 `credit` 里。置顶卡片上的小图是西湖那一张。

来源全文在 [NOTICE.md](NOTICE.md)。爸妈页按住 3 秒进去之后，设置一栏有「图片来源」。

孩子跟读结束后，按钮区域会显示一颗大星星和「录好了」，大约 1 秒。这个词会在列表右上角留下一颗小星星。星星只加不减，清空家庭数据也不会清掉。是否跟读过按词条 id 记在旁边的 `WordStars.json`，不会为了这一件事重写整本库。

## 数据与恢复

- 库的结构版本是 **2**。版本 1 的库和旧 `.echo101` 备份会迁到现在的句库和记录；比 2 新的版本会拒绝打开。
- 导出包仍是未加密 JSON。分享完成或取消后，App 会删掉 `Exports/` 里的那份副本；每次启动也会清掉这个文件夹里的普通文件。
- 爸妈页显示上次导出时间。超过 7 天或从未导出时，只在爸妈页提醒，不弹给老人。
- 播放次数写在旁边的 `UsageLog.json`，离开 App 时再并进库。单条表达最多保留最近 30 次，全部使用记录最多 2000 条，避免写不进去。
- 种子句（大约几十句日常话，来源是 `seed`）在第一次打开、库还是空的时候写入。它们算爸妈已经确认过的句子，可以改、可以删。只有种子、没有别的内容时，仍然可以恢复备份。
- 卸载会删掉本机数据。换机或重装前先导出。

## 构建与测试

```text
Echo101/                 SwiftUI、录音、朗读、四个标签
Sources/EchoCore/        库、迁移、句库匹配、词表、导出恢复
Sources/EchoAPI/         DeepSeek / MiMo、Wi-Fi 或蜂窝开关、钥匙串
Tests/                   核心库与假网络测试
Echo101UITests/          不打开麦克风、不联网的界面测试
```

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
swift test --disable-sandbox --scratch-path /tmp/echo101-tests
```

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project Echo101.xcodeproj -scheme Echo101 \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/echo101-device-build build-for-testing
```

GitHub Actions 的「Echo checks」在 macOS 上跑单元测试、设计令牌检查、无签名编译和模拟器界面测试。模拟器通过不等于 XS 上的听感和识别已经验收。家庭验收见 [验收清单](docs/ACCEPTANCE.md)。

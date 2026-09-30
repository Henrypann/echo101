# Echo · 验收清单

版本：**v0.2.0（build 2）**。日期：2026-09-30。最低 iOS 17。

当前结论：实现、单元测试和签名设备构建已完成，主 App 已覆盖安装；**家庭功能验收尚未完成**。原生页面渲染截图与真实点击、音频、认证和模型请求是不同证据。

## 构建与自动验证

| ID | 检查 | 当前结果 |
| --- | --- | --- |
| BUILD-01 | Swift 6 / iOS 17+ 原生编译 | 通过 |
| BUILD-02 | 签名设备 `build-for-testing` | 通过；主 App 与 UI 测试目标可构建，不等于 UI 测试已执行 |
| BUILD-03 | Release 无签名编译与诊断隔离检查 | 编译通过，Release 可执行文件未检出测试诊断旁路字符串；不代替系统认证实测 |
| DEVICE-01 | 主 App 覆盖安装 | 已完成；更新保留原 Bundle ID |
| UI-01 | 4 项设备 UI 交互测试 | 未执行；免费签名的 3 个设备名额已满，测试运行器没有可用名额 |
| CI-01 | CI 模拟器上的 4 项 UI 交互测试 | [GitHub Actions](../.github/workflows/ios.yml) 已配置，待运行结果；与 iPhone XS 实测分开记录 |
| CORE-01 | Core 单元测试 | 23 项通过，0 失败；合成记录和临时库 |
| API-01 | API 单元测试 | 26 项通过，0 失败；mock 网络，不调用真实供应商 |
| TOTAL-01 | 单元测试合计 | **49 项通过，0 失败** |

Core 覆盖保存和重启、草稿确认门禁、收藏与使用记录、关联删除、批量事务及保存失败，录音文件安全与清理，导出往返、损坏与超限拒绝、非空库保护和失败回滚。新增家长提示测试覆盖旧 JSON 缺少字段、保存和归档往返、无效提示拒绝。

API 覆盖两供应商请求与输出校验、错误状态、30 秒配置、Wi-Fi 门禁、请求配额、重复点击、取消与迟到响应。真实声线听感、麦克风、设备端转写成功率和供应商服务不在这些单元测试的证明范围内。

4 项 UI 测试目标包括：生活片段与表达持久化／删除，设置诊断与云端默认关闭，不启动麦克风的采集取消，儿童页不暴露草稿或家长提示。当前均不能标记通过。XS 执行需可用的测试运行器签名名额，释放其他 App 或运行器名额需由设备所有者决定。CI 使用运行环境预装的 iPhone 模拟器，不占用 XS 签名名额；即使 CI 通过，也不能把真实音频、系统家长认证或 XS 交互标为完成。

## M0–M5 状态

| ID | 里程碑 | 实现与证据 | 待完成验收 |
| --- | --- | --- | --- |
| M0 | 工程设备验证 | 原生工程、签名设备构建、Release 编译和主 App 覆盖安装完成 | CI 模拟器及 XS 的 4 项 UI 测试；最终版本设备检查 |
| M1 | 离线词句本 | 本地 Moments / Expressions、编辑、确认、收藏和使用记录已实现；相关 Core 测试通过 | 飞行模式添加、查询、重启和编辑的实际点击流程 |
| M2 | 跟说录音 | 主动录音、30 秒上限、试听、保存、逐条删除及文件安全已实现；编译和 Core 文件测试通过 | 真实录音／回放、上限自动停止、锁屏／来电／后台／耳机中断 |
| M3 | 场景采集 | 45 秒可选采集、中文／英文设备端 ASR、人工使用转写与临时音频清理已实现 | 权限允许／拒绝、真实转写、45 秒停止、保存／取消后的设备文件行为 |
| M4 | 模型辅助 | DeepSeek / MiMo、Wi-Fi、Keychain、发送预览与双重确认、候选草稿和 parentTip 已实现；26 项 API 测试通过 | 两供应商真实请求、真实 Keychain、费用、网络限制与取消 |
| M5 | 恢复与家庭验收 | 文字／录音归档、空库恢复、完整性检查、失败回滚与旧数据兼容测试通过 | 家庭导出／分享及独立空库恢复、脱离 Mac 使用、完整家庭流程确认 |

双模式与 Echo 视觉是贯穿各里程碑的增量：儿童区 Today / Explore / My World，系统认证后的家长区 Overview / Moments / Settings；草稿和家长提示仅在家长区。App 非活跃时显示隐私遮罩，切到后台后锁回儿童区；这些行为的设备实测仍在清单中。确认表达不计为孩子已掌握。

## 原生页面截图

当前已有 13 张真机原生窗口渲染截图，包括八个关键页面与深色／大字样例。截图证明页面显示结果，**不等于按钮点击、系统认证、权限弹窗、录音、朗读或真实模型服务已验收**。深浅外观、大字、键盘与读屏仍需逐项检查。

| ID | 页面 | 浅色截图 |
| --- | --- | --- |
| VIEW-01 | Today | [today-light.png](screenshots/today-light.png) |
| VIEW-02 | Explore | [explore-light.png](screenshots/explore-light.png) |
| VIEW-03 | Listen & Say | [listen-light.png](screenshots/listen-light.png) |
| VIEW-04 | My World | [world-light.png](screenshots/world-light.png) |
| VIEW-05 | Overview | [overview-light.png](screenshots/overview-light.png) |
| VIEW-06 | Add a Moment | [moment-light.png](screenshots/moment-light.png) |
| VIEW-07 | Review an Expression | [review-light.png](screenshots/review-light.png) |
| VIEW-08 | Privacy & Settings | [settings-light.png](screenshots/settings-light.png) |

外观压力样例：[Today 深色](screenshots/today-dark.png) · [Settings 深色](screenshots/settings-dark.png) · [Overview 大字](screenshots/overview-large.png) · [Explore 大字](screenshots/explore-large.png) · [Review 大字](screenshots/review-large.png)。已检查八个原生页面及两个深色、三个辅助字号样例的可见区域；滚动、键盘与 VoiceOver 另行验收。截图使用合成数据和独立库，不含家庭记录；导出后手机已返回正常家庭库。

## 设备能力与数据保护

已有 [设备能力诊断](XS-capabilities.json) 报告 iPhone XS / iOS 18.7.4 上的英语声线和中英文设备端识别能力，以及测试目录的完整文件保护和排除备份属性。该诊断未启动麦克风或请求模型，不能证明真实 ASR 成功、离线听感或锁屏后的访问行为。

恢复包为未加密 JSON；所选录音以 Base64 包含其中。家长提示参与保存与恢复，密钥和临时采集音频不进入导出。分享出去的副本不再受 App 本地文件保护，也不随 App 内删除自动更新。

## 家庭与设备实测

未勾选项保持待验收。

- [ ] **系统家长认证**：从三个儿童页进入家长区，验证成功／取消／失败；返回儿童区和锁屏后管理数据仍受保护。
- [ ] **离线词句本**：飞行模式添加生活片段和表达，保存为草稿／确认，退出重开，查询、编辑和收藏；草稿与家长提示不进入儿童区。
- [ ] **20 句听感**：添加示例、选择声线；飞行模式听 Listen / Slow / Parts，重点检查 `I can say my ABC.`、朗读文本及语块；不出现自动续播。
- [ ] **权限**：分别测试麦克风和 Speech 允许／拒绝；拒绝后仍可听示范和手动输入，不重复强求权限。
- [ ] **跟说录音**：Say It Together → Start Recording → Stop Recording → Listen to Our Voice → Save Recording；Manage Recordings 播放、取消删除及确认删除；30 秒自动停止。
- [ ] **场景采集**：45 秒上限；中英文设备端转写、人工修改、Use This Transcript；保存／取消后临时音频清除；不可识别时可回听并输入。
- [ ] **音频中断**：录音时锁屏、切后台、来电、切换耳机；回到 App 不自动继续采集，播放与录音不串音。
- [ ] **真实模型请求**：专用按量付费 Key，Wi-Fi 下分别请求两服务；检查候选、释义和 parentTip；真实费用在供应商侧核对。
- [ ] **发送边界**：生成前检查预览、确认移除私人信息并同意发送；改字后确认重置；取消／超时不重试；恢复 Wi-Fi 不自动发送；蜂窝与低数据模式阻止请求。
- [ ] **草稿确认**：Keep as Draft 不进入儿童区；Confirm Expression 后才可使用；编辑已确认表达不会反向变成草稿，保存不产生掌握结论。
- [ ] **提醒偏好**：Off / 3 / 5 / 10 minutes 可保存；提醒后可结束并返回线下活动；不申请通知权限。
- [ ] **导出与恢复**：分别导出文字和含录音版本，在独立空测试库恢复；parentTip 保留，非空库阻止，不覆盖家庭库。
- [ ] **深浅与大字**：逐页检查语义色、字段边界、换行、键盘、固定保存／取消入口及横向空间；最大辅助功能字号下无重要内容截断。
- [ ] **无障碍**：VoiceOver 遍历、字段标签、草稿状态、播放／录音区分、删除确认和结果反馈；录音停止后状态明确。
- [ ] **脱离 Mac**：拔线、关闭 Mac 后，本地保存、朗读与录音回放继续可用；签名到期后可重新签名覆盖安装。

家庭验收结论：**待完成**。

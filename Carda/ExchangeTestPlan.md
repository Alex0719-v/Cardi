# Cardi 名片交换上线前测试计划与可行性报告

更新时间：2026-07-23

## 1. 结论摘要

Cardi 设计的“双方前台打开 App、停留在我的名片页、通过上划表达发送意图、用 Nearby Interaction 选择 1.5 米内目标明确对象、再通过点对点连接传输名片”的方案，在 Apple 公布的系统能力边界内**原则上可实现**。设备支持即时方向时同时校验前方角度；只支持精准距离时按 Apple 文档进入 distance-only 降级，且仅选择唯一、距离明确最近的对象。

当前版本尚不具备上线放行条件。主要原因不是 UI 或编译，而是：

1. 真实 Multipeer Connectivity 发现、Nearby Interaction 距离/方向、双向意图和 ACK 链路尚未经过两台兼容 iPhone 的端到端验证。
2. payload 校验上限与接收消息上限矛盾：校验允许的最大 payload 编码后为 16,845,575 字节，超过 14,680,064 字节的接收上限。
3. UI 只保存一个 `queuedReceivedCard`，多人同时投递时后来的来卡可能覆盖前一条未展示事务。
4. Nearby Interaction 权限拒绝、Local Network 权限拒绝和系统无线错误没有被分成可恢复、可引导的明确状态。
5. Multipeer Connectivity 在当前 iOS 26.5 SDK 中已弃用并要求迁移到 Network framework；它仍可编译，但属于上线后的兼容性与维护风险。

本轮已修复：不再把 `supportsDirectionMeasurement == false` 误判为整机不支持；未锁定目标时不再冻结上划副本；发送事务加入 12 秒 ACK 超时；未连接 send、对端 `.error`、断线与超时统一回收当前意图和事务。根据 2026-07-23 测试编号 `050212` 的双机 JSON，A 端开始记录后没有离开账户 Sheet，交换协调器与广播均未启动；B 端只有被动广播且没有上滑手势事件，链路在 discovery 前就已中断。现已改为开始记录后自动关闭账户 Sheet、退出搜索并回到“我的名片”，同时记录未进入手势链路的固定拒绝原因。

因此当前建议状态为：**前台 MVP 技术方向可行；上线判定 No-Go，直到 P0 缺陷修复且双真机矩阵通过。**

## 2. 已确认产品边界

- 仅交换“我的名片”页面当前展示的名片。
- 双方都必须已安装并打开 Cardi，App 位于前台，停留在“我的名片”，并存在当前名片。
- 当前不使用 AirDrop、NameDrop、二维码或 NFC。
- 前台待机只广播；上划超过 20pt 后才主动发现与测距；达到提交门槛后发送意图。
- 目标必须在 1.5 米内且稳定至少 0.4 秒；方向能力可用时还必须位于手机前方约 ±45°，否则只能选择唯一且距离明确最近的设备。
- 最近两人距离差小于 0.3 米时禁止自动投递。
- 双方意图时间差不超过 1.5 秒时互换；否则单向投递。
- 收到名片并成功写入 SwiftData 后才可发送 `persistedAck`。
- 后台接收、App 未打开接收、未安装 App 投递、锁屏入口和 Live Activity 当前均不在实现范围内。

## 3. Apple 系统能力边界

### 3.1 可以实现

- Nearby Interaction 可在前台提供兼容 iPhone 之间的距离和方向。
- 每个附近对象使用一个独立 `NISession` 符合 Apple 的会话模型。
- discovery token 可通过局域网、Multipeer Connectivity、Bluetooth 或自定义服务器交换。
- `NISession.deviceCapabilities.supportsPreciseDistanceMeasurement` 决定 Nearby Interaction 是否可用；`supportsDirectionMeasurement` 只决定使用方向+距离还是 distance-only 目标选择，不能单独作为整机不支持的判据。

### 3.2 有条件实现

- 方向依赖 UWB 硬件、设备姿态和视线条件；人、墙、车辆、厚重外壳或手机没有朝向对方时，direction 可能为 `nil`。
- Apple 的会话维护文档明确给出分支：支持 direction 时使用距离与方向；不支持 direction 但支持 precise distance 时继续使用距离。Cardi 的 distance-only 分支保留 1.5 米、0.4 秒稳定、0.3 米多人歧义保护，不猜测方向。
- Apple 建议兼容设备保持竖屏、后置相机方向相互对准并尽量保持无遮挡。Cardi 必须在真实使用姿态中验证 ±45° 规则是否稳定。
- 本地发现依赖系统无线环境和 Local Network 权限；企业 Wi-Fi 隔离、VPN、热点、Wi-Fi / Bluetooth 关闭等条件必须实测。

### 3.3 当前范围内无法实现

- 模拟器无法证明真实 UWB 距离或方向正确。
- App 已终止或未安装时，当前前台 advertiser 不能继续提供 Cardi 自定义接收体验。
- 不启用 Background Modes / Live Activity 时，不能把前台 Nearby Interaction 行为延伸为后台常驻接收。
- 第三方 App 不能拦截或关闭系统 NameDrop / Bringing Devices Together 手势。

参考：

- Apple Nearby Interaction：<https://developer.apple.com/documentation/NearbyInteraction>
- Apple 会话维护与权限：<https://developer.apple.com/documentation/nearbyinteraction/initiating-and-maintaining-a-session>
- Apple MCSession（已弃用）：<https://developer.apple.com/documentation/MultipeerConnectivity/MCSession>

## 4. 测试方法

### 4.1 静态审计

检查需求到代码的逐项映射：生命周期、权限声明、服务名、目标筛选、协议版本、数据校验、持久化 ACK、异常清理、DEBUG 隔离、Release 配置和弃用 API。

### 4.2 standalone 纯逻辑测试

直接编译生产 Swift 文件，覆盖不依赖 UI 或硬件的边界算法。此层必须至少覆盖：

- 距离、角度、稳定时长、读数 TTL 和多人歧义边界。
- 最近 5 次读数中位数与离群值。
- payload 字段数、字符串、图片、排序和总编码大小。
- 协议版本、消息缺字段、未知枚举、重复 exchange ID。
- 单向、互换、回递、拒绝、ACK、超时和冷却状态转移。

### 4.3 Simulator UI 自动化

仅验证 UI、动画、payload、SwiftData、ACK 调用和回递交互，不把结果当作真实发现或 UWB 证据。

环境变量：

- `CARDA_ENABLE_EXCHANGE_SIMULATION=1`
- `CARDA_AUTO_SIMULATE_EXCHANGE=1`
- `CARDA_SIMULATE_SINGLE_DELIVERY=1`
- `CARDA_AUTO_SIMULATE_RETURN=1`

### 4.4 双真机端到端

两台支持 precise distance 的 iPhone 安装同一 Release/TestFlight 构建；至少覆盖一组支持 direction 与一组 direction 不可用的组合。测试前在两机 `设置 → 帮助与关于` 连续轻点 `当前版本` 7 次打开 `交换诊断`，填写相同六位编号并分别选择设备 A/B 后开始记录。两机都应自动关闭账户 Sheet 并回到“我的名片”；开始实际上划前，状态页或导出 JSON 必须已经出现 `advertising_started` 与 `exchange_coordinator_started`，否则本轮不算进入交换测试。每个测试必须同时保存：

- 两机型号、系统版本、构建号、权限状态和网络状态。
- 两机屏幕录制，画面中可识别时间基准。
- 两机分别导出的交换诊断 JSON；测试编号必须一致，角色不得重复。JSON 应能按 exchange ID、匿名 peer 摘要、事件顺序、墙钟时间与 system uptime 对齐 discovery、connection、token、ranging、selection、intent、transfer、persistence 和 animation。
- 可连接 Mac 时追加 CardExchange / NearbyExchangeRanging 的 OSLog；非崩溃问题不再只依赖 OSLog。
- 交换前后两机 SwiftData / 账户归档中的名片数量和 ID。
- 实际距离、角度、朝向、遮挡和附近人数。

### 4.5 故障注入

建议把 transport、clock、ranging 和 persistence 抽象为可注入接口，再自动注入：

- send 返回失败或静默不发送。
- ACK 丢失、延迟、重复和乱序。
- 连接在 token、intent、card、保存、ACK、returnDelivery 任一阶段断开。
- NI timeout、suspend、invalidation、权限拒绝和错误 token。
- SwiftData save 失败、磁盘空间不足和模型上下文 rollback。

当前 `CardExchangeCoordinator` 直接构造具体 transport 和 selector，导致上述关键故障难以稳定单元测试；这是测试基础设施缺口。

### 4.6 性能与能耗

使用 Instruments / MetricKit 或等价工具采集：

- 首次发现、连接、token 交换、目标锁定、card 发送、持久化 ACK 的分段耗时。
- 10 秒主动发现窗口中的 CPU、网络、蓝牙/UWB 和能耗。
- 最大常规 payload 下峰值内存、编码/解码耗时和主线程卡顿。
- Metal 递出、来卡、收纳、翻转回递的帧率和掉帧。
- 连续 100 次交换后的内存、session、Task 和 peer state 是否持续增长。

### 4.7 安全与隐私

- 验证 MCSession 加密开启且 Release 日志不包含名片字段、手机号、邮箱、图片数据或 token 原文。
- 使用同 service type 的测试 App 模拟恶意 peer，验证协议版本、payload、exchange ID 和 NI token 防护。
- 重放同一 `card` / `persistedAck` / `throwIntent`，验证不重复落库、不错误成功、不永久阻塞。
- 构造超大 JSON、深层 JSON、损坏 Data、异常 Unicode 和大量字段，验证内存与响应。
- 检查隐私说明、App Store 隐私标签和用户可理解的权限用途文案。

## 5. 测试环境矩阵

### 5.1 设备

1. 两台 `supportsPreciseDistanceMeasurement == true` 且 `supportsDirectionMeasurement == true` 的 iPhone。
2. 一台支持、一台不支持 direction 的组合；两机都应进入测距，不支持方向的一端只在唯一最近目标明确时锁定。
3. 两个不同屏幕尺寸与不同代际 UWB 芯片的组合。
4. 裸机、普通保护壳、磁吸配件、厚重/金属壳。
5. 低电量、低电量模式和高温降频状态。

不要只按型号名称推断支持；每次记录 `NISession.deviceCapabilities` 实际值。

### 5.2 系统和构建

- Debug Simulator：只用于模拟回归。
- Release Simulator：验证正式编译和 DEBUG 入口隔离。
- Release generic iOS device：验证 arm64 设备架构编译。
- TestFlight / App Store 签名构建：验证真实权限、签名、配置和系统提示。
- 当前 deployment target 为 iOS 17.0；TestFlight 真机回归至少覆盖 iOS 17、iOS 18、iOS 26 与 direction 不可用设备组合。

### 5.3 无线与网络

- Wi-Fi 开 / Bluetooth 开。
- Wi-Fi 关 / Bluetooth 开。
- Wi-Fi 开 / Bluetooth 关。
- 飞行模式后手动开启 Wi-Fi。
- 同一家庭路由器、访客网络、企业网络（客户端隔离）、个人热点。
- VPN 开 / 关。
- Local Network 允许、拒绝、在 Settings 中撤销后恢复。
- Nearby Interaction 允许、拒绝、在 Settings 中撤销后恢复。

## 6. 完整测试项目

状态约定：`AUTO` 可自动化，`SIM` 可在 Simulator 验证，`DEVICE` 必须真机，`SEC` 安全测试，`PERF` 性能测试。

### A. 构建、配置与 Release 隔离

- A01 `AUTO` Debug Simulator 构建成功，Metal shader 成功编译。
- A02 `AUTO` Release Simulator 构建成功。
- A03 `AUTO` Release generic iOS device arm64 构建成功。
- A04 `DEVICE` Archive、导出、TestFlight 安装和首次启动成功。
- A05 `AUTO` `Info.plist` 存在 `NSLocalNetworkUsageDescription`。
- A06 `AUTO` `NSBonjourServices` 精确包含 `_carda-ex._tcp`。
- A07 `AUTO` 存在 `NSNearbyInteractionUsageDescription` 且发布语言可理解。
- A08 `AUTO` DEBUG 模拟按钮和四个环境变量入口不出现在 Release / 真机正式体验。
- A09 `AUTO` Release 中不包含暂停的 Live Activity / Widget Extension。
- A10 `AUTO` 记录并评估所有 Multipeer Connectivity 弃用警告。

### B. 能力、权限与错误引导

- B01 `DEVICE` 两机 capability 均支持时进入 listening。
- B02 `DEVICE` 不支持 precise distance 时禁止开始并说明设备不支持。
- B03 `DEVICE` 支持距离但不支持 direction 时进入 distance-only；只有唯一最近目标与第二名相差至少 0.3 米时允许发送，多人歧义时禁止。
- B04 `DEVICE` 首次 Local Network 允许后可以发现。
- B05 `DEVICE` 首次 Local Network 拒绝后不崩溃、不假装“附近无人”，并引导 Settings。
- B06 `DEVICE` 首次 Nearby Interaction 允许后开始测距。
- B07 `DEVICE` Nearby Interaction 拒绝产生 `userDidNotAllow` 时停止重试并引导 Settings。
- B08 `DEVICE` 权限在 Settings 中撤销后，当前事务安全失败且可恢复。
- B09 `DEVICE` 权限重新开启并回到 App 后无需重装即可恢复。
- B10 `DEVICE` 关闭“附近可发现”立即停止 advertiser、browser、连接和测距。

### C. 页面与生命周期

- C01 `DEVICE` 只有“我的名片”前台且有当前名片时启动 advertiser。
- C02 `DEVICE` 空状态不广播、不接受、不允许上划交换。
- C03 `DEVICE` 进入编辑页立即停止完整会话。
- C04 `DEVICE` 打开账户 Sheet 立即停止完整会话。
- C05 `DEVICE` 切到名片夹或搜索立即停止完整会话。
- C06 `DEVICE` App inactive / background / 锁屏立即停止完整会话。
- C07 `DEVICE` 返回前台与“我的名片”后重新进入 listening。
- C08 `DEVICE` 来卡展示或保存中切后台，不能重复保存、错误 ACK 或留下永久遮罩。
- C09 `DEVICE` 发送中切后台，连接清理后再次前台可重新交换。
- C10 `DEVICE` 系统权限弹窗、电话、通知横幅和来电中断不破坏状态机。

### D. 上划手势

- D01 `SIM/DEVICE` 从当前名片内开始，竖直上划小于 20pt：不启动发现。
- D02 `DEVICE` 达到 20pt：启动 browser、连接和短时 NI。
- D03 `SIM/DEVICE` 20...119pt 松手且预测值不足：取消并回弹。
- D04 `DEVICE` 达到 120pt 或预测阈值：提交且只绑定一个 peer。
- D05 `SIM` 手势副本与原卡重合，原卡全程不移动、不隐藏。
- D06 `SIM` 水平滑动仍切卡，不误触交换。
- D07 `SIM` 从名片外或底部导航开始上划不触发交换。
- D08 `SIM/DEVICE` context menu、编辑页、Sheet、来卡 Overlay、递出动画期间拒绝新手势。
- D09 `DEVICE` 5 秒内向同一 peer 重复递卡被阻止；5 秒后恢复。
- D10 `DEVICE` 回递不被主动手势冷却误拦截。

### E. 发现、连接和 NI token

- E01 `DEVICE` 被动方只 advertiser，不长期 browser / ranging。
- E02 `DEVICE` 主动方在 20pt 后发现被动方并建立连接。
- E03 `DEVICE` 双方同时 browser / invite 时只建立一个有效会话，不重复连接或死锁。
- E04 `DEVICE` 连接后双方 hello 与 discovery token 均完成。
- E05 `DEVICE` token 解码失败时明确失败并清理。
- E06 `DEVICE` 本机不支持方向但支持精准距离时仍能交换 token 和取得距离；唯一最近 peer 可锁定，不能显示“当前设备不支持精准方向识别”。
- E07 `DEVICE` NI timeout 后自动重新 run，并最终恢复读数。
- E08 `DEVICE` NI invalidation 后重建 NISession、发送新 token、恢复缓存的 peer token。
- E09 `DEVICE` invalidConfiguration 不无限重建循环。
- E10 `DEVICE` 10 秒没有目标后停止 browser / ranging / 连接，保留 advertiser。

### F. 距离、方向和多人目标选择

- F01 `AUTO` 1.5000m 可选；1.5001m 不可选。
- F02 `AUTO` 45° 内可选；超过 45° 不可选。
- F03 `AUTO` 稳定不足 0.4 秒不可选；超过门槛可选。
- F04 `AUTO` 读数年龄 1.25 秒可用；超过 1.25 秒过期。
- F05 `AUTO` 方向模式下零向量、NaN、infinite 和缺失 direction 不可选；distance-only 模式不要求 direction，但仍执行距离、稳定性、TTL 与歧义检查。
- F06 `AUTO` 最近五次距离使用中位数，单个离群值不能错误锁定。
- F07 `DEVICE` 0.3m 距离差恰好允许最近目标；小于 0.3m 提示歧义。
- F08 `DEVICE` 三人以上按最近有效目标排序，最近两人歧义时不选第三人。
- F09 `DEVICE` 用户转向、交叉走动、有人穿过时不投递给旧目标。
- F10 `DEVICE` 前后、左右、背对、遮挡、桌面平放、口袋、保护壳姿态均记录 direction 行为。
- F11 `DEVICE` 目标锁定后到发送前目标离开，事务失败且可以再次上划。
- F12 `DEVICE` 100 次多人场景错误收件人为 0。
- F13 `AUTO/DEVICE` distance-only 模式可锁定唯一最近目标，最近两人差距小于 0.3 米时必须返回 ambiguous。

### G. 单向投递

- G01 `DEVICE` 仅 A 上划：1.5 秒窗口结束后 A 发送 delivery。
- G02 `DEVICE` B 展示来卡，A 只显示等待，不提前成功。
- G03 `SIM/DEVICE` B 3 秒无操作自动收纳、保存、ACK。
- G04 `DEVICE` B 点击拒绝：不保存，发送 rejected，A 不显示成功。
- G05 `SIM/DEVICE` B 点击“分到列表”：弹出全部现有列表，未选择时确认禁用；选择并确认后保存到所选列表，再发送 ACK。
- G05a `SIM/DEVICE` 列表弹窗显示取消按钮，列表区域与弹窗使用同一玻璃材质和颜色；弹窗打开期间不得自动收纳，点击取消或外部遮罩关闭后返回接收界面并重新开始完整 3 秒自动接收计时。没有现有列表时显示空状态且确认不可用。
- G06 `DEVICE` 保存失败：rollback、rejected、无 ACK、可重试。
- G07 `DEVICE` A 收到 persistedAck 后才成功反馈。
- G08 `DEVICE` ACK 丢失后事务有超时、可重试且不重复保存。
- G09 `DEVICE` card 发送失败或 peer 已断开时不得进入无限等待。
- G10 `DEVICE` 断线重连后不会把旧事务误判为新成功。

### H. 双向互换

- H01 `DEVICE` 两机在 1.5 秒内互相锁定并上划，双方发送 mutual。
- H02 `DEVICE` 1.5 秒边界内外分别稳定得到 mutual / delivery。
- H03 `DEVICE` 两机系统时钟存在 ±2 秒偏差时仍按本地接收窗口正确判定，或明确证明产品要求自动校时。
- H04 `DEVICE` 双方来卡均保存后各自收到 ACK。
- H05 `DEVICE` 一方保存失败时另一方不能把“双向互换”整体误报成功。
- H06 `DEVICE` 一方拒绝时两端状态一致、可重新交换。
- H07 `DEVICE` 双方同时邀请、同时发 token、同时发 intent 时无重复 card。
- H08 `DEVICE` mutual 来卡不可再次触发翻面回递。

### I. 单向翻面回递

- I01 `SIM/DEVICE` 仅 delivery 且本机有当前卡时显示回递提示。
- I02 `SIM/DEVICE` 不足翻面阈值回弹，不保存、不 ACK、不回递。
- I03 `SIM/DEVICE` 达到阈值后先完成翻面，再保存来卡和 ACK。
- I04 `DEVICE` ACK 后以新 exchange ID 发送 returnDelivery。
- I05 `SIM` 只播放本机卡回递，不并行收纳对方卡。
- I06 `DEVICE` 回递连接已断开时来卡仍保持已保存，UI 明确提示回递失败。
- I07 `DEVICE` returnDelivery 成功后等待对方 persistedAck。
- I08 `DEVICE` returnDelivery 不被 5 秒冷却拦截。
- I09 `DEVICE` returnDelivery 来卡不可再次翻面。

### J. 数据校验、持久化和重复处理

- J01 `AUTO` 名称/拼音/职位 256 字符边界。
- J02 `AUTO` 公司 512 字符边界。
- J03 `AUTO` 32 个字段、每字段 2,048 字符和 sortOrder 0...31。
- J04 `AUTO` 头像/Logo 各 6MiB 边界与总编码大小一致性。
- J05 `SEC` 超过任一限制不得展示、保存或 ACK，必须给发送者终止响应。
- J06 `SEC` 无效 JSON、协议版本、必填字段、枚举、token 均安全拒绝。
- J07 `DEVICE` ownerKind 必须为 received，created/updated/received 时间正确。
- J08 `DEVICE` 默认列表 ID 有效时写入该列表，无效时进入未分类。
- J09 `DEVICE` duplicate ask/keep/replace 三种策略符合设置。
- J10 `DEVICE` 保存后账户 `cards.json` 归档包含收到名片及图片。
- J11 `SEC` 重复同一 exchange ID 不重复保存，重新连接/重启 App 后仍防重放。
- J12 `DEVICE` App 在 ACK 前崩溃，重启后不出现“对方已接住”的假成功。

### K. 并发和压力

- K01 `DEVICE` 两人同时向一人投递，两个事务都被排队或明确拒绝，不覆盖。
- K02 `DEVICE` 三至七个 peer 被发现时不超过系统会话资源限制。
- K03 `DEVICE` 第八个以上 peer 的降级行为明确且不崩溃。
- K04 `DEVICE` 连续 100 次单向投递无永久卡住、重复或丢失。
- K05 `DEVICE` 连续 100 次 mutual 无永久卡住、重复或丢失。
- K06 `PERF` 最大常规名片连续交换无内存持续增长。
- K07 `PERF` 快速反复达到 20pt 后取消，不残留 browser、连接、NISession 或 Task。

### L. 网络故障

- L01 `DEVICE` invite 超时后可再次发现。
- L02 `DEVICE` 连接在 hello 前断开。
- L03 `DEVICE` 连接在 token 交换中断开。
- L04 `DEVICE` 连接在 throwIntent 后断开。
- L05 `DEVICE` 连接在 card 传输中断开。
- L06 `DEVICE` 连接在保存后、ACK 前断开。
- L07 `DEVICE` 连接在 returnDelivery 前断开。
- L08 `DEVICE` send 目标不在 connectedPeers 时产生可清理失败，不静默等待。
- L09 `DEVICE` Wi-Fi/Bluetooth/VPN/网络切换中状态可恢复。
- L10 `DEVICE` 发送端、接收端强制退出后另一端在有限时间内恢复 listening。

### M. UI、动画与辅助功能

- M01 `SIM` 原卡不动，副本手势、锁定吸附、递出形变连续。
- M01a `SIM/DEVICE` 提交时尚未锁定目标，手势副本在 0.2 秒内回弹并移除，逻辑发现继续；之后锁定再从原卡位置递出，页面不得停留图 1 式双卡冻结状态。
- M02 `SIM` 来卡从顶部收束态连续展开，同一视图承载翻面。
- M03 `SIM` 收纳完成后才持久化；持久化完成后才 ACK。
- M04 `SIM` Reduce Motion 下不执行大幅 shader 形变，流程仍可完成。
- M05 `DEVICE` haptics / sound 总开关与交换开关组合正确。
- M06 `DEVICE` VoiceOver 可读状态、拒绝、分到列表和回递提示。
- M07 `DEVICE` 动态字体、显示缩放、浅色固定主题下信息不遮挡。
- M08 `SIM/DEVICE` 动画中切页、旋转尝试、系统弹窗不残留遮罩。
- M09 `PERF` 关键动画帧率无持续卡顿或 Metal 错误。

### N. 安全、隐私与商店审核

- N01 `SEC` 同 service type 的非 Cardi peer 不能绕过协议与 NI 校验投递任意数据。
- N02 `SEC` MCSession 传输加密保持 required。
- N03 `SEC` hello 名称、MCPeerID 和 payload 均视为不可信输入。
- N04 `SEC` token、intent、card、ACK 重放不造成重复或假成功。
- N05 `SEC` 超大数据在完整载入前受限制，避免内存拒绝服务。
- N06 `AUTO` 日志不包含名片字段和图片；Release 关闭高频方向调试日志。
- N07 `DEVICE` 权限说明与真实用途一致，拒绝后功能仍可理解。
- N08 `AUTO` App Store 构建不包含私有 API、模拟入口或未声明后台能力。
- N09 `MANUAL` App Privacy、隐私政策和用户协议覆盖附近设备、局域网和本地名片数据。

## 7. 建议上线门槛

以下为建议门槛，产品可提高但不应降低安全项：

- P0 未解决数为 0。
- 两台兼容 iPhone 的单向、mutual、回递、拒绝、保存失败、断线和权限矩阵全部通过。
- 错误收件人 0；未持久化却显示成功 0；重复落库 0；永久阻塞 0。
- 连续 100 次单向与 100 次 mutual 中，除明确注入的无线故障外成功率至少 99%。
- 主动发现窗口结束后 browser、NISession 和连接全部清理。
- Release/TestFlight 不显示任何模拟入口。
- 无崩溃、无主线程卡死、无持续内存增长、无敏感日志。
- Multipeer Connectivity 迁移计划有明确版本；若以弃用实现首发，必须接受并登记回归与回滚风险。

## 8. 本轮已执行结果

| 项目 | 结果 | 证据 |
| --- | --- | --- |
| Debug iPhone 17 Pro / iOS 26.5 Simulator 构建 | PASS | `xcodebuild ... -configuration Debug ... build` |
| Metal shader 编译 | PASS | 构建生成 `default.metallib` |
| Release Simulator 构建 | PASS | `xcodebuild -quiet ... -configuration Release ... build` |
| Release generic iOS device arm64 无签名构建 | PASS | `destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO` |
| Release 可执行文件调试入口隔离 | PASS | 未检出交换模拟环境变量、`debug.simulateExchange` 或模拟按钮文案 |
| Release 应用包资源最小化 | RISK | `.app` 仍包含 `AGENTS.md`、`README.md`、`contributing_ai.md` 等内部文档 |
| UI test bundle build-for-testing | PASS | Cardi + CardiUITests 均成功 |
| DEBUG mutual 模拟 | PASS | 来卡、自动收纳、SwiftData received、ACK 路径完成 |
| DEBUG 单向来卡 + 自动翻面回递 | PASS | 来卡、翻面、保存、ACK、回递动画完成 |
| 新增交换 UI 自动化 | PASS 2/2 | `CardExchangeSimulationUITests`，0 failures |
| 隐藏交换诊断入口 UI 自动化 | PASS | 版本行 7 次解锁、六位编号、开始后自动返回“我的名片”、重新进入后结束记录、导出状态 |
| 交换诊断隐私 standalone 测试 | PASS | 六位编号规范化、peer 摘要稳定且 JSON 不含明文 peer ID |
| 目标选择边界 standalone 测试 | PASS | 距离/角度/稳定/TTL/歧义/最近目标 |
| payload 限制 standalone 测试 | PASS + KNOWN RISK | 最大合法编码 16,845,575 > 14,680,064 |
| Info.plist 静态检查 | PASS | Local Network、Bonjour、NI usage 均存在 |
| 真机 Multipeer 发现 | BLOCKED | 需要两台兼容 iPhone |
| 真机 UWB 距离/方向 | BLOCKED | Simulator 无法验证 |
| 真机错误收件人、多目标、遮挡 | BLOCKED | 需要至少三人/三机现场 |
| TestFlight 权限与签名 | NOT RUN | 需要发布签名和真机 |

测试结果包：`/tmp/CardaExchangeUITests-20260719.xcresult`。

## 9. 已发现风险与优先级

### P0 — 上线阻塞

1. **缺少双真机端到端证据。** 当前只证明编译、UI、SwiftData 和模拟 ACK；真实发现、方向和传输未验证。
2. **payload / transport 上限冲突。** 最大校验通过 payload 超过接收消息上限，会被接收端 guard 静默丢弃。
3. **NI 权限拒绝未识别。** `userDidNotAllow` 需要停止重建并明确引导用户去 Settings；当前 invalidation 路径会尝试重建与重新 run。

本轮已关闭的 P0：发送事务已有 12 秒最终超时；transport 未连接不再静默 return；`.error`、send failure、断线与超时会统一回收当前 `localIntent`、`outgoingTransactions`、browser 和 timeout task。

### P1 — 高风险

1. **单槽来卡队列。** `queuedReceivedCard` 不是数组，多个同时来卡可能覆盖并悬挂旧事务。
2. **重放防护只存在于当前 peerState。** idle cleanup / 重连后 exchange ID 记录丢失，同一 card 可能重复保存。
3. **mutual 使用两机 wall clock 时间戳。** 时钟偏差可能把同时上划误判为单向；应优先按本地收到意图的单调时间窗口判断。
4. **缺少 peer 身份认证。** `.required` 保护传输加密，但 hello 名称与 service peer 仍不构成可信账户身份；附近恶意 App 可模拟协议。
5. **Multipeer Connectivity 已弃用。** 当前可编译，不代表后续 SDK 或系统行为稳定。
6. **最低系统为 iOS 26.5。** 若目标用户包含未升级设备，会形成覆盖率阻塞，需要产品确认。
7. **Release 包包含内部 Markdown 文档。** 文件同步分组会把工程文档复制进应用包；调试代码虽未进入 Release 可执行文件，但内部规则和调试开关名称仍会随包分发，归档前必须排除并复查产物。

### P2 — 中风险

1. `hasNearbyPeerWithoutClearDirection` 没有使用读数 TTL，可能基于旧距离持续显示“请朝向对方”。
2. 距离样本不足 5 个时也会计算中位数；需要确认“最近 5 次”是否要求满 5 个才可锁定。
3. 允许 12MiB 原始图片通过 JSON reliable data 传输，峰值内存、延迟和 MCSession 适用性均未压测。
4. Release 仍包含 deprecated API，需在 CI 把新警告升级为可见质量门槛。
5. Coordinator 直接构造硬件/传输依赖，故障注入与状态机单元测试成本高。

## 10. 下一轮执行顺序

1. 修复剩余 P0 大小上限和权限分支，并继续补充可注入的 coordinator 状态机测试；本轮 distance-only 目标选择逻辑测试已覆盖唯一最近与多人歧义。
2. 从 Release Target Resources 排除内部 Markdown 文档，重新归档并验证应用包只包含运行必需资源。
3. 把单槽来卡改为有上限、可拒绝、按 exchange ID 管理的队列。
4. 使用已接入的 App 内交换诊断：两机采用同一六位编号与不同 A/B 角色，测试后同时导出两份 JSON，并与屏幕录制、设备/系统/构建信息一并归档。
5. 先跑最小双机链路：发现 → token → distance/direction → delivery → save → persistedAck。
6. 再跑 mutual、returnDelivery、权限、断线与多目标。
7. 通过后执行 100 次稳定性、性能/能耗、安全与 TestFlight 发布检查。
8. 决定首发前还是首发后迁移到 Network framework，并记录回滚策略。

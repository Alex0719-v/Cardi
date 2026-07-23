# contributing_ai.md

> 本文件约束开发协作 AI 如何改动 Cardi 仓库。
> 若与 `AGENTS.md` 冲突：以 `AGENTS.md` 为准。

---

## 0. 范围说明

- **Dev AI**：修改代码、文档、资源、测试或项目配置的 AI。
- **Runtime AI**：未来如在产品内集成的 AI 能力，当前不在本文范围内。

---

## 1. 默认工作协议

处理开发任务时，应尽量明确以下信息：

1. **Goal（目标）**：本次要解决什么。
2. **DoD（验收）**：如何判断完成。
3. **Plan（步骤）**：分步、可回滚。
4. **Files to add/change**：新增或修改哪些文件。
5. **Design source（设计来源）**：涉及 Figma 时写明节点或页面。
6. **Verification（验证）**：如何构建、运行或检查。
7. **Final Output（交付）**：说明实际完成内容。
8. **Self-check（自检）**：哪些已验证，哪些未验证。
9. **Docs Sync（文档同步）**：本次代码、资源或设计规则变化需要同步更新哪些 `.md` 文件。

如果用户请求很小，可以简化表达；但不明确的地方必须先问。

---

## 2. 读档顺序

每次会话或新任务开始前，优先阅读：

1. `AGENTS.md`
2. `contributing_ai.md`
3. `README.md`
4. `Designsystem.md`
5. `ROADMAP.md`

---

## 3. 非谈判规则

- 不明确就询问用户，不自行猜测。
- 一次只做一个任务，避免混入无关改动。
- 不删除资源、模型、配置或用户已有代码，除非用户明确要求。
- 不新增第三方依赖，除非用户确认。
- 不进行大范围重构，除非用户确认。
- 不把模板示例代码当作正式产品逻辑扩展。
- 不自行补充 Figma 中尚未设计的页面或流程。
- 修改视觉、交互、数据模型、导航结构前必须确认方向。
- 修改名片生成规则前必须确认，因为这是当前最复杂、最关键的功能。
- 名片夹默认排序必须统一读取 `CardaDefaultCardSort.defaultValue`；没有已保存偏好或设置被重置时固定进入“姓名”，不得在 `AppShellView`、设置页或测试中分别写入“最近添加”作为默认值。用户明确保存的其他排序偏好仍必须优先。
- 写代码、改资源或调整设计规则时，必须根据用户最新指令同步维护相关 `.md` 文件，不能让文档滞后于实现。
- 若用户明确指定资源来源，例如 `My icon/` 或 `Card photo/`，实现和文档都必须记录该来源，不得继续引用旧实现方式。
- 名片右侧操作按钮中的手机、邮箱、地址、链接图标来源为 `My icon/Phone.svg`、`My icon/Mail.svg`、`My icon/Map pin.svg`、`My icon/Link.svg`；名片夹删除按钮图标来源为 `My icon/Trash 2.svg`；不得继续使用旧的 SwiftUI 手绘版本，也不得用 `WKWebView` / HTML 异步加载本地图标。
- 名片夹展开完整名片中的手机、邮箱、地址、链接按钮使用 Figma `10064:3390` / `Group 72` 的自绘固定弹窗，不使用系统 action sheet；弹窗由 `AppShellView` 绘制在页面最顶层，固定 x=51、y=675、w=300、h=153，不随名片位置变化。弹窗下方一层渐变背景模糊蒙必须从 y=675 覆盖到屏幕底部并遮住底部菜单栏；弹窗出现时从屏幕底部用 S 型曲线自然滑入。弹窗正文显示字段内容，左侧统一 `复制` 写入 `UIPasteboard`；右侧按钮按字段类型为 `拨打`、`邮件`、`查询`、`前往`。电话继续打开 `tel://`；邮箱、地址、链接必须通过 `LinkedApplicationRouter` 读取 Cardi 内部关联应用偏好并提供系统降级。
- 底部导航和名片右侧操作按钮这类高频重建区域中的本地 SVG 图标必须复用 `LocalSVGIconView` 的缓存解析和 SwiftUI `Canvas` 渲染路径，避免页面切换或名片滑动时出现闪烁、延迟。
- Cardi 最低支持 iOS 17.0。底部导航 Liquid Glass 保留 Figma `10063:3134` 的轮廓和三层配方，但按最新增强指令把白色 Normal、`#DDD` Color Burn、`#F7F7F7` Darken 的可见强度调整为 44% / 48% / 42%，玻璃基底保持 0.4% 黑色，阴影调整为 x=0/y=10/blur=44/16% 黑色。Figma 不包含普通 stroke，描边必须来自无额外 tint 的原生 `.glassEffect(.regular)` 高光折射；左侧导航、搜索按钮/搜索栏和清空按钮在 iOS 26 及以上共享 `GlassEffectContainer(spacing: 0)`，避免相邻玻璃表面在页面进入或稳定布局时自动融合。公共玻璃按钮不得追加乳白 tint，交互表面继续追加 `.interactive()`，点击反馈只能由真实按压触发。选中 tab 保留不透明 `#EDEDED` 灰色滑块，并参考登录/注册原生 segmented control 使用 0.24 秒、零回弹的 `.smooth` 位移动画；减弱动态效果时立即切换。低于 iOS 26 的系统不得引用 Liquid Glass API，降级为固定浅色 `ultraThinMaterial` / 毛玻璃。修改时不得破坏现有搜索形变和无动画交接时序。
- “我的名片 / 名片夹”真实切换时，新选中 SVG 使用 0.90 → 1.045 → 1.0 的四阶段低 bounce 反馈，整条底栏同步使用最大约 2.2% 的纵向压缩与轻微回弹；反馈 trigger 只能是 `selectedSection` 的变化，不能由重复点击、搜索形变或键盘态触发。必须读取 `accessibilityReduceMotion`，开启时禁用该缩放/位移动画。
- 名片夹姓名/公司 → 列表的顶部交接必须保留稳定视图身份：标题只做 34pt→22pt 缩放和左侧→居中位移，不做模式渐隐；右侧 44pt 头像入口用 0.56 秒 S 型曲线拉伸为 112 x 46 跑道圆，头像按填充轮廓放大、blur 0→15、alpha 在几何半程到 20% 后归零，四字按钮文案从中心重叠、blur=15、alpha=0 同步散开，并在主曲线实际达到 50% 宽度的约 0.07725 秒开始、用 0.58275 秒清晰显现，结束点仍为轮廓完成后 0.10 秒。左侧 72 x 46 按钮从 scale≈0 放大，文字从 blur=15/alpha=0 还原。玻璃背景与前景文字不得一起放入会再次折射文字的合成容器；完成态文字必须清晰。列表返回姓名/公司必须复用正向的 0.56 秒 `cubic-bezier(0.2, 0.72, 0.18, 1)`，不得再使用反向 ease-in 控制点。右侧玻璃在整段双向动画中必须是同一个 `.circular` `RoundedRectangle` 原生玻璃视图，宽高与圆角从 112 x 46 / 23pt 连续插值到 44 x 44 / 22pt 的完全倒角正方形；`.glassEffect` 的接收图形必须在施加效果前显式固定为当前宽高，头像与四字文案只能作为不参与本体布局的 overlay，避免隐藏文案扩大玻璃取样边界；禁止改用 `Circle` / `Capsule`，也禁止在终点替换 `UserAvatarButton`。仅跨越列表边界时触发，姓名/公司互切不得播放；减弱动态效果直接到终态。
- 灵动岛 / Live Activity 交换 UI 暂停实现：当前工程不得保留 `CardaExchangeLiveActivity` Widget Extension、`ExchangeLiveActivityController`、`ExchangeLiveActivityAttributes` 或 `NSSupportsLiveActivities`。后续如重新接入灵动岛，必须等用户明确恢复该需求后再设计。
- 名片交换当前边界：不得调用 AirDrop、NameDrop、二维码或手机碰手机 NFC；只在双方都打开 Cardi、App 位于前台、都停留在“我的名片”页面、当前有名片且未进入创建/编辑或添加弹窗时启用。页面待机只运行 `MCNearbyServiceAdvertiser`；用户从当前名片上划 20pt 后才启动 browser、连接和短时 Nearby Interaction 测距，上划达到 120pt 后提交意图。Nearby Interaction 支持性只以 `supportsPreciseDistanceMeasurement` 判断：支持 direction 时目标必须位于 1.5 米内、手机前方约 ±45°且稳定 0.4 秒；不支持 direction 时按 Apple 的 distance-only 路径，仅允许选择 1.5 米内唯一且距离明确最近的设备。距离按最近 5 次读数中位数计算；任一模式下最近两人差距小于 0.3 米都禁止自动投递。上划由覆盖原卡的独立 UI 动画层承担：手势阶段从 0.96 倍连续增长到最高 1.08 倍并加入不超过 5° 的姿态，锁定时向递出方向吸附 12pt；提交时目标尚未锁定则立即回收副本、继续逻辑发现，禁止冻结在手势终点，之后锁定再从原卡位置播放递出；已锁定时沿用稳定 ID 直接进入 `distortionEffect` + `CardGenieShader.metal` 连续奇幻形变，页面原卡不得移动或隐藏。禁止重新引入多份横向切片。来卡也必须使用同一形变的反向过程，在约 0.85 秒内从屏幕顶部收束点连续展开到接收位置，并由同一个视图继续承载翻转手势，不允许普通直线滑入或淡入替换。双方 `throwIntent` 时间差不超过 1.5 秒时升级为 `mutual`，否则为单向 `delivery`；单向来卡翻面后先保存来卡并发送 `persistedAck` 与新 exchange ID 的回递，再只让本机卡从翻转位置以完整不透明的连续形变递出，不再同时收纳对方名片；普通接收仍保留约 1.2 秒的奇幻收纳。收到 payload 后先校验；拒绝或保存失败发送 `rejected`，发送侧只能在收到 `persistedAck` 后显示“对方已接住”并触发成功震动。`card` 发送成功后必须有 12 秒 ACK 超时，ACK、拒绝、断线、send 失败、对端 `.error` 和超时都必须清除本次 intent/transaction/browser/task，确保后续上划不被永久阻塞。构建环境需要 Xcode 官方 Metal Toolchain；开启“减弱动态效果”时降级为移动、缩放和淡出。`Info.plist` 必须保留本地网络用途说明、`_carda-ex._tcp` Bonjour service 和 `NSNearbyInteractionUsageDescription`。模拟器不能验证真实 UWB；DEBUG + Simulator 使用 `CARDA_ENABLE_EXCHANGE_SIMULATION` / `CARDA_AUTO_SIMULATE_EXCHANGE`，可追加 `CARDA_SIMULATE_SINGLE_DELIVERY` 与 `CARDA_AUTO_SIMULATE_RETURN` 回归单向翻面动画；所有入口不得进入 Release 或真机正式体验。
- 真机/TestFlight 交换问题必须优先使用 App 内诊断包复核：在 `设置 → 帮助与关于` 连续点击 `当前版本` 7 次解锁 `交换诊断`，两机使用相同六位测试编号并分别选择 A/B。开始记录后必须自动关闭账户 Sheet、退出搜索并回到“我的名片”，同时验证新 JSON 依次出现 `diagnostic_return_to_my_cards_requested`、`advertising_started` 与 `exchange_coordinator_started`；不得再依赖用户手动退出多层设置页。`CardExchangeDiagnostics` 只在用户明确开始后记录，覆盖 discovery、connection、token、ranging、selection、intent、transfer、persistence、animation、手势 UI 拒绝原因和 source location；后台前必须 flush，最近只保留 5 次。诊断 JSON 严禁包含姓名、手机号、邮箱、名片文字/图片、原始 token 或明文 peer ID，新增埋点的 details 必须继续使用固定状态、数值、错误 domain/code、exchange ID 或匿名摘要。修改交换链路时同时更新埋点，并回归隐藏入口、自动返回、开始/结束与导出可用状态。
- iOS 26.5 SDK 已将部分 Multipeer Connectivity API 标为弃用并建议使用 Network framework；前台 MVP 继续复用当前传输层，后续迁移时必须保留现有消息协议、目标选择、持久化 ACK 和 UI 状态边界，不得顺带重写名片数据模型。
- Nearby Interaction 的 timeout / invalidation 属于可恢复测距状态：timeout 后要重新 `run`，invalidation 后要重建 `NISession` 并重新发送 discovery token，不得把“近距离测距已停止”作为常驻错误提示展示。
- 当前全局字体规则为中文 PingFang SC、英文 SF Pro；视觉或文本相关改动必须遵守并同步记录。
- 账户 Sheet 的登录信息卡片必须作为完整按钮使用同一个 `NavigationStack`：未登录时依次推入 `LocalAccountAuthenticationPage` → `AccountProfilePage`，已登录时才可直接进入资料页，不得新增嵌套 Sheet或跳过认证。登录使用手机号+密码，注册增加确认密码；密码只能通过 `LocalAccountCredentialStore` 写入 iOS Keychain，禁止写入 `UserDefaults`、JSON、测试附件或日志。资料页手机号只读，`手机号` 标题必须固定单行完整显示，54pt 顶栏必须保持高于下方 Form，避免返回圆形底部被覆盖；昵称与邮箱均有效才可完成。头像必须使用系统 `PhotosPicker`，中心裁成 512 x 512 并压缩后持久化，不得读取任意名片头像或申请整库照片权限。保存后必须同步刷新“我的名片”和名片夹；已登录但没有头像时继续显示空白玻璃入口。
- 修改主页面账户头像时，必须同时验证“我的名片”与名片夹姓名/公司模式。两处 44 x 44 终态必须复用 `AccountAvatarGlassSurface`；先固定 `.circular` RoundedRectangle 的 44 x 44 / r22 frame 再应用玻璃，登录头像只能作为 `scaledToFill` overlay，不得使用会改变玻璃布局边界的 ZStack 子视图，也不得把“我的名片”改回旧 `FigmaGlassShape + Circle`。
- 本地账户隔离必须统一通过 `LocalAccountCardStore`，目录为 Application Support 下的 `Carda/Accounts/phone-<规范化手机号>/`；`profile.json` 保存头像、昵称、手机号和邮箱，`cards.json` 归档全部 `BusinessCard`、`CardInfoField`、`BusinessCardList`、列表归属、日期与图片数据。不得在归档成功前清空 SwiftData；退出失败必须保留当前数据。已有手机号须先通过密码认证，再回填资料并载入数据；切换账户必须先退出，不得重新允许资料页修改手机号。数据变化和 App 进入后台时继续刷新归档；发布版本不得重新注入示例数据，旧归档/备份中的 `13800010001...13800010030` 演示名片必须在恢复时过滤，且空状态头像仍必须能打开账户 Sheet 以完成恢复。
- 账户 Sheet 的 `关联应用`、总览和分类选择页共用同一个 `NavigationStack`，不得使用嵌套 `.sheet`；进入时旧页向左、新页从右进入，返回或完成选择时反向滑回，外层 `.height(465)` / `.large` detent、遮罩、圆角、grabber 与拖拽状态不得重建。账户页的 `设置 / 关联应用` 使用 370 x 104pt、26pt 圆角两行组件，与 `退出登录` 保持 27pt；“添加名片”必须保持 50% `SearchBackground` 灰色跑道与黑色文字，“退出登录”和“恢复默认设置”文字统一使用 `CardaTheme.destructive` / `#FF383C`。总览页返回按钮沿用 Figma `10924:15888` / `10924:15889` 的相对工具栏 x=16、y=16、w=44、h=44 圆形 frame，图标使用 SF Symbol `chevron.left`、17pt Medium；顶部标题 `关联应用` 保持 x=167、y=29、w=68、h=22，PingFang SC Medium 17pt。浏览器、邮箱、地图三行继续使用单个 370 x 156pt、26pt 圆角组件和 52pt 行高，但不得显示左侧图标，标题与分隔线从 x=19 开始；下方 27pt 的 `恢复默认设置` 必须确认后才同时重置三类 `@AppStorage`。邮箱选择页同样不显示图标，浏览器与地图选择页保留。不得使用私有 API或枚举任意 App：只允许从 `LinkedApplicationID` 固定注册表调用 `canOpenURL`，并在 `Info.plist/LSApplicationQueriesSchemes` 登记 Scheme。浏览器顺序固定为 Safari、Chrome、夸克、QQ浏览器、Edge、UC，第三方标志读取 `My icon/Browser *.svg`；邮箱为邮件/QQ 邮箱/网易邮箱大师/Outlook/Gmail，地图为 Apple/高德/百度/Google Maps/Waze。只展示已安装项，选择仅保存到 Cardi `UserDefaults`；应用卸载或打开失败必须降级。夸克、QQ浏览器、UC浏览器要预复制网址并按“直达候选 → App 主页 → 系统默认”降级，QQ 邮箱与网易邮箱大师复制收件人后启动 App；非公开 Scheme 必须真机验证。
- 账户 Sheet 的 `设置` 必须与账户页、关联应用共用同一个 `NavigationStack`，首页只保留 `名片交换`、`名片管理`、`数据与存储`、`交互与辅助功能`、`帮助与关于` 五组，不得重新加入独立的“隐私与安全”或“通知”组。偏好统一通过 `CardaSettingsPreferenceKeys` 的 `@AppStorage` 管理，并验证它们实际作用于交换发现/确认/反馈、默认列表与排序、重复名片、删除确认、动画、动态字号和左右翻页。数据备份必须排除 Keychain 密码、限制相同手机号恢复；删除当前账户或全部本地数据必须先显示破坏性确认，并同步检查 SwiftData、账户目录、凭据和偏好清理范围。设置 UI 回归至少检查五组存在、已移除两组不存在、同一 Sheet 返回路径和一个偏好的持久化。
- “我的名片”页面背景以 Figma `10063:3262` 为准，使用 `MyCardsBackground` / `#E1E0E3`，不得回退到全局 `PageBackground`；该页面的完整名片不绘制名片本体外框阴影。
- 完整名片外框、右下按钮裁切槽、折叠名片和空名片占位卡必须使用普通 `.circular` / 圆弧圆角，不使用 Corner smoothing、`.continuous` 或平滑圆角。
- 创建/编辑页的动态字段类型只包含手机、邮箱、地址、链接；公司 logo 属于固定 LOGO 上传行，不得重新加入动态字段选择菜单。
- 创建/编辑页的公司/职位/LOGO 固定信息组必须独立实现和定位，不得复用动态字段行组件；否则动态高度、点击层或分隔线容易导致公司栏和 LOGO 行跑偏。
- 创建/编辑页文本输入控件必须使用确认/完成提交键并在 `onSubmit` 中释放焦点；动态字段可因宽度自动换行，但键盘不得继续显示换行键而导致无法主动收起。
- 创建/编辑名片页顶部预览必须在 `Group 42.png`、`color2.png`、`color3.png` 三张本地底图间横向分页，固定顺序且首尾停止。使用 402pt 整画板步长与“我的名片”同款分页曲线；只允许底图和以同一图片坐标裁切的圆形按钮底色水平移动，文字、头像、Logo 和按钮图标必须保持固定。预览正下方显示无外层跑道圆的三点指示器。选择由 `BusinessCardDraft.backgroundTemplate` 持有并在确认时写入名片；完整渲染、PNG 导出、本地账户归档/备份和交换 payload 必须保留同一模板标识，旧数据缺失时回退到 `color1`。
- PNG 导出必须使用独立渲染模式：保持真实动态高度和当前底图，但输出完整直角矩形，去掉屏幕名片的外圆角、右下裁切槽及按钮圆形底图；仅保留缩小到 75% 并左移 10pt 的字段图标。导出图标必须按信息行真实高度与 6pt 间距逐项计算 y 坐标，并与对应信息的第一行竖向居中；右对齐信息文字列相对屏幕名片总计右移 15pt（较上一版导出继续右移 10pt）。不得把这些导出专用坐标带回屏幕展示、编辑预览、名片夹或交换动画。
- 编辑页姓名占位中的“名”字当前总计向左偏移 43pt；英文名/拼音只有空白占位 `Xing Ming` 使用 16pt tracking，用户输入文本必须使用正常 0 tracking。
- SwiftUI 的 `TextField(axis: .vertical)` 可能把 `.submitLabel(.done)` 仍作为换行处理；动态字段必须保留换行拦截逻辑，检测到新增 `newline` 后恢复文本并释放焦点。
- 手机字段格式化必须复用 `PhoneNumberFormatter`，不得在编辑页和名片展示层分别手写分组规则。显示采用 `3 4 4`，拨号和搜索采用纯数字。
- 动态字段输入必须上报焦点状态给 `CardEditorView`。键盘输入时临时增加足够的底部滚动空间，并使用字段稳定 ID 滚动到键盘上方；结束后通过 `ScrollOffsetBridge` 恢复进入动态字段输入前的 offset 并移除临时空间。不得依赖系统在固定 Figma 画布内自动避让。
- 名片夹顶部栏、分类栏、模式切换、空状态和历史演示数据清理属于名片夹核心交互，修改时必须同步记录 Figma 节点、坐标规则与数据来源。
- 名片夹列表模式使用 `BusinessCard.cardListID` 表达唯一归属；不得用重叠索引范围或多个列表 ID 让同一张名片重复出现。无有效归属的名片必须进入最底部 `未分类`。列表模式展开出的折叠名片可拖放到其他列表行以更新 `cardListID`；投放到 `未分类` 时写入 `nil`，拖回原列表不得重复保存。折叠名片进入可更换所属列表的系统拖拽状态时，必须立即收起来源列表，并在收起动画完成后滚回来源列表行顶部，避免列表卡在屏幕外；若拖拽取消、投放失败、投回原列表或保存失败，必须恢复之前因拖动收起的来源列表，并滚回拖拽开始前的滚动位置。折叠名片拖拽源必须使用 `UIDragInteraction` 桥接，在 `itemsForBeginning` 中记录拖拽源、来源列表和当前滚动偏移，在 drag session end 中兜底恢复仍未成功清理的拖拽；不能只用 SwiftUI `.onDrag`，因为它没有可靠的结束回调。投回原列表和保存失败这类已处理失败必须返回已消费，恢复或成功投放的收尾期必须使用过期时间戳短暂忽略列表行点击/长按，避免松手触发列表行 `toggle` 后刚展开又收起；不得用 `draggingListCardID` 等可能残留的拖拽状态作为长期手势拦截条件，用户下一次明确列表操作前必须清理残留拖拽状态；不得再叠加辅助 `DragGesture` 做位移检测，也不得使用 drag preview 的 `onDisappear` 作为拖拽结束信号，避免抢占普通滚动或在拖拽刚开始时误恢复展开。
- 新版名片夹以 Figma `10063:3011` / `10064:3390` / `10064:3656` 为准：页面底色为白色叠加 `#303136` 6%，内容面板为白色叠加 `#C3C2C8`；不得继续套用旧版 `PageBackground` 顶部栏、灰线和黑色下划线。顶部列表/姓名/公司切换必须按 Figma Union path 绘制，选中项必须先将内容面板与顶部标签矩形拼合再统一倒角，且圆角使用普通 `.circular` / 圆弧圆角，不使用 Corner smoothing、`.continuous` 或平滑圆角；未选中项为白色布尔标签并按 Figma 三态固定镜像映射绘制：列表态姓名/公司为右尾，姓名态列表为左尾、公司为右尾，公司态列表/姓名为左尾；不得用普通圆角矩形近似。
- 名片夹列表/姓名/公司按钮必须以当前 Figma 标签 frame 和 `HolderModeTabShape` 作为完整 `contentShape`，不得把命中范围限制在文字 frame；调整点击区域时必须保持文字中心、标签外观和模式切换动画不变。
- 名片夹姓名/公司模式展开态的内容可见上沿为 y=164，并以 24pt 透明顶部安全区让分组标题起始在 x=16、y≈188；顶部收起时可见上沿随统一偏移连续移动到 y=54。索引及悬顶容器必须透明，不得出现遮挡名片的背景色块。下一标题顶部距旧悬顶标题底部 2.5pt 时旧标题开始淡出，到达旧标题中心时完全透明；标题身份仍在下一标题越过吸顶线时切换，不能使用无过渡的硬替换。
- 名片夹姓名/公司模式必须按 Figma `10592:4348` 的顶部过渡范围在名片上方增加 x=16、y=178、w=370、h=47 的 `TransparentGradientBlur(direction: .top)`；该实例使用 `.systemUltraThinMaterialLight` 实时取样背景，以 `SearchBackground` / `#D8D7DB`、84% 透明度校色，并启用 `matchesOpaqueEdgeColor`，保证顶部边界为 100% 不透明同色以消除断层。下方仍须使用真实模糊和 alpha 渐变，禁止扩展成大面积纯色保持区。名片超过 y=178 的部分必须被裁切，顶部标题栏、右上角头像、分段标签和分组标题必须位于该模糊过渡上方，不得被遮住。
- 名片夹折叠名片和展开完整名片都必须支持左滑删除：未展开态参考 Figma `10592:4167`，使用 52pt 红色圆形按钮与 22pt `Trash 3.svg`；展开态参考 Figma `9574:2114`，保留动态高度长条按钮，并将原 28pt `Trash 2.svg` 缩放至 80%（22.4pt）。删除按钮透明度必须直接使用 `clamp(-offsetX / 70, 0...1)` 与实时滑动位移双向绑定，展开从 0% 连续显现到 100%，收起沿同一进度连续消失；按钮只在释放达到阈值并进入删除模式后可点击。同一页面只允许一张名片处于删除模式，开始左滑另一张时必须先连续收起前一张。删除按钮点击后必须先弹出确认，用户确认后才删除对应 `BusinessCard`。
- 名片夹姓名/公司模式的卡片左滑删除必须使用识别开始前的横向轴锁定；纵向或近似纵向输入应让子级 pan 直接失败，使父级 `ScrollView` 无延迟接管。禁止用覆盖整张卡片的低阈值 SwiftUI `DragGesture` 参与纵向手势竞争后才在 `onChanged` 中过滤方向。
- 名片夹列表/姓名/公司模式共用 0/110pt 二态顶部状态：手指上推、浏览页面更下方内容累计约 1pt 后收起，手指下拉、浏览页面更上方内容累计约 1pt 后展开；列表模式必须先确认 `expandedListID` 非空才能接受向上收起，全部列表收起时顶部导航保持展开。列表顶部 26pt 可滚同色区域只维持 Sticky Header 内部结构，不再延迟导航收起；ScrollView/Sticky Header 模块必须整体移动并整体裁切，不得对单个 Header 累计 offset。滚动物理视口固定为 820pt，禁止随顶部收起动态改变 frame 高度和 `ScrollGeometry.containerSize`。完全收起时模块 top=y54、Header top=y61、裁切线 y66。
- 顶部方向的唯一数据源是原生 `UIScrollView.panGestureRecognizer` 的逐帧手指 delta；只能观察现有识别器，不得增加竞争手势。iOS 17 兼容的 `ScrollOffsetBridge` 只用于记录 clamp 后的内容位置和执行程序化 offset 请求，布局变化、程序化滚动、减速和触底回弹均不得触发顶部状态。禁止重新加入 ScrollPhase、连续 offset 投影、速度/进度端点吸附、时间 suppression、列表专用展开锁/方向状态或标题动画期间的内容 offset 写回。进入名片夹、跨页面返回、退出搜索及切换列表/姓名/公司模式必须先清除方向状态并无动画展开顶部。
- 修改名片夹模式切换或滚动观察器时，必须保留原生 `UIScrollView.panGestureRecognizer`，并使用模式交互代际阻断切换前已开始手势的迟到 `.changed` / `.ended`。分组标题偏好必须按“模式 + 标题”去重且只消费当前模式；禁止用节流、禁用点击或改动画参数掩盖竞态。
- 修改名片夹顶部文字淡出时，透明度必须从可中断插值后的同一 `headerCollapseOffset` 展示值推导，不能让每个 `Text` 只接收独立的 0/1 `opacity` 动画端点。滚动稳定性 UI 回归除 `exists` / `isHittable` 外还必须检查标题截图中的实际深色文字像素，因为辅助功能树不会反映文字是否停留在全透明状态。
- 名片夹滚动、分组和拖放 UI 回归必须自带 DEBUG Simulator 种子数据；需要多张未分类收到名片时使用 `CARDA_SEED_LOCAL_ACCOUNT_TEST_DATA=1` + `CARDA_SEED_CARD_HOLDER_BATCH_TEST_DATA=1`，不得依赖其他 UI test 的执行顺序、用户本地数据或旧演示名片残留。
- 新版姓名/公司模式顶部 `Scroll Edge Effect - Soft` 在 Figma 中为隐藏状态，不再显式渲染旧版顶部 `TransparentGradientBlur(height: 63.255, direction: .top)`；名片夹滚动视口必须延伸到画板底部，不得在底部导航上沿 y=779 裁切折叠名片。名片夹 ScrollView 的 820pt 固定物理高度不可为了显示原生 edge effect 而缩短；底部只允许一层屏幕定位的 `FigmaScrollEdgeSoftOverlay`，固定 y=737、h=140，使用单一线性 Alpha Mask 和 Figma 对应的双层背景模糊 / 90% Screen 结构，禁止额外 tint、实色色块、面板色块或裁切层；右侧 A-Z/# 索引必须位于其前景。
- 名片夹列表模式最顶行不显示顶部分隔线；第二行及后续行使用 Figma iOS Light Row Separator 对应的 `#C6C6C8`，标题行始终保持 53pt 间距。
- 名片夹列表多选状态必须由 `CardHolderView` 的页面局部状态持有，不写入 SwiftData。进入多选后顶部按钮原位切换为左侧 `退出`、右侧 `取消选择`；前者清空并退出，后者只清空。展开列表中的折叠名片在该模式下只响应选中切换，必须停用完整名片展开、左滑删除和长按菜单；已选名片右上角显示 26pt `SystemSelectionGreen` / `#34C759` 圆形及白色勾，任一列表包含已选名片时，列表标题使用 `SystemSelectionBlue` / `#007AFF`。选择清空、切换模式或卡片从数据源移除时及时清理对应状态。
- 进入/退出多选只能更新稳定点击/拖动层的模式、数据和手势启用状态；禁止通过 `if isMultiSelecting` 在 `Button`、`ListCardDragSource` 或左滑手势修饰器之间替换视图类型。模式切换事务必须关闭卡片级隐式动画，勾选反馈使用自己的局部动画，避免折叠名片闪烁。
- 批量移动继续使用现有 `UIDragInteraction`：多选模式只允许从已选名片开始拖动，并一次返回全部已选名片对应的多个 `UIDragItem`，被拖名片排在第一项以成为堆叠顶层。投放后必须在单次 SwiftData 保存中批量变更所有需要移动名片的归属，并复用原有来源列表收起、失败恢复与投放收尾协议。只有保存成功后才能从页面局部选择集合中移除实际改变归属的名片 ID；未改变归属的已选名片继续选中，保存失败则完整保留选择。
- Cardi 是固定浅色视觉系统，必须保留应用根视图的 `.preferredColorScheme(.light)`。涉及 Liquid Glass、SwiftUI Material 或 `UIVisualEffectView` 的修改，至少需要在模拟器深色模式下复测一次，确认系统材质不会变成深灰/黑色。
- 名片夹右侧 A-Z/# 索引必须同时支持点击与连续拖动；姓名模式定位同名字母 Section，公司模式按公司拼音首字母定位该字母下第一个公司 Section。不存在目标分组时不得跳到其他字母。
- 姓名/公司索引交互提示复用 `ContactAlphabetIndex` 内的轻量 overlay 状态，不得插入列表布局：69 x 58pt `AlphabetIndexIndicatorFill` / `#000000` 右向水滴形、30pt 纯白色 SF Pro Regular 大字、尖端距索引中心 32pt；当前索引字母使用 14pt 纯黑圆底和白字。按住时跟随选中字母行，松手后收起，并保持 overlay `allowsHitTesting(false)`。
- 索引定位必须为末尾 Section 保留完整吸顶所需的底部滚动空间，不能因内容已接近列表末尾而停在目标字母之前。
- 名片夹所有字母/公司分组标题通过 Anchor Preference 整体绘制在前景层，分组 `LazyVStack` 必须关闭系统 `pinnedViews`。深灰 body 上沿随顶部收起从 y=164 移动到 y=54；初始首标题 top=y188，因此唯一吸顶文字 top 始终为 body 上沿 + 24pt，即 y=188...78。吸顶标题必须由独立持久槽绘制，并缓存最后一个有效标题 ID；Lazy Section 回收当前锚点时不得清空该槽。下一标题顶部距悬顶标题底部 2.5pt 时，当前标题开始按实际几何距离淡出；下一标题顶部到达悬顶标题中心时，当前标题完全透明。下一标题越过吸顶线后再更新槽内身份，反向滚动使用同一映射恢复。
- 名片夹列表模式使用 `LazyVStack(pinnedViews: [.sectionHeaders])`；每个分类标题为独立 `ListStickyHeader`，模块顶部通过 7pt pin inset 与 26pt 可滚同色区域保持初始 33pt、首行 y=197、后续行每 53pt 连续排列。独立 mask 在模块局部 y=12 裁切名片内容；禁止恢复单 Header `visualEffect`、累计 offset 或 `listPinnedEdgeSeal`。列表模式需要在顶部导航前景重绘姓名/公司白色标签轮廓，确保标签尾部不会被列表内容覆盖。
- 名片夹滚动期间禁止把 offset、方向判定和每行 Geometry frame 分别写入多个 `@State`。非观察运行时只保存 clamp 后的内容位置及当前原生 pan 的轻量方向确认值，不得恢复 ScrollPhase、速度、回弹标志或投影锚点；拼音分组与列表归属结果按输入 key 缓存；AppShell 根视图不得因顶部二态动画整体失效。
- 名片夹标题/头像栏上方不得再绘制 402 x 62pt 顶部 `TransparentGradientBlur` 或任何替代遮罩。删除该层时不得连带删除顶部栏/AppShell 在 y=62 的既有裁切逻辑、列表 Header top=y61 / 裁切线 y66，或姓名/公司名片上方 y=178 的独立渐变模糊。
- 分组标题与该分组首张折叠名片的间距必须在上一版基础上缩小 13pt。
- 添加列表交互必须校准 Figma `9522:1321`：全屏 35% 遮罩覆盖底部导航，名称为空时禁用创建，成功后新列表置顶，取消不写入。
- 列表行长按编辑必须校准 Figma `10240:4332` / `10368:4034`：真实用户列表长按菜单为 250 x 104、两项纯文字按钮；`删除列表` 必须先走 iOS 原生确认弹窗，确认后把原列表名片移入 `未分类`；`修改列表名称` 使用 300 x 254 Alert 和 35% 全屏遮罩，并沿用 `添加列表` 弹窗的标题、胶囊输入框和胶囊按钮样式，不得退回系统分隔线式 Alert。`未分类` 是系统兜底列表，不允许重命名或删除。
- 列表展开必须保留真实位移动画：折叠名片组从当前列表行后方向下滑出，列表行在前景遮住动画起点；不得只做静态裁切揭示，也不得使用相对整个 ScrollView 顶部的移动转场。列表 Header 初始 top=y197；顶部进入收起态后模块移动到 y54，Header 悬顶 top=y61，名片内容统一在 y66 裁切，不得穿过 Header 进入顶部导航区域。
- 用户主动点击收起列表时，必须从点击开始同步请求滚回 `y=0` 并展开顶部导航；不得把该回顶挂到所有 `expandedListID = nil` 路径，避免覆盖拖拽临时折叠后的来源行/原偏移恢复。删除、清空和拖拽收起只负责恢复顶部导航；展开列表中的名片继续复用折叠/完整名片点击切换，并同步更新容器真实高度。
- 长按菜单必须有明确的菜单外点击关闭行为；新增或修改长按菜单时，同步确认透明点击层不会拦截菜单内部按钮。
- 搜索页修改必须分别校准 `4096:14211` 最近添加态、`7648:3795` 键盘态和 `4096:14285` 搜索结果态；不得把搜索页顶部统一成通用大标题，也不得让键盘态搜索栏继续停留在底部 y=779。
- 最近添加和名片搜索结果必须复用 `AppShellView` 注入给名片夹的同一份名片夹数据源，不得直接把全量名片集合传给搜索页后再临时筛除自己的名片。
- 修改搜索栏交互时，必须验证整条玻璃搜索栏均可触发输入态，不能只让 TextField 文本区域可点击；右侧叉号必须独立执行清空，不得被搜索栏点击层抢占。
- 搜索输入文本必须直接驱动实时结果：非空时立即进入 `名片搜索`，每次变化刷新结果；确认/完成键只收起键盘，叉号清空文本并返回 `最近添加`。
- 所有滚动边缘渐变毛玻璃复用 `Components/TransparentGradientBlur.swift`。修改名片夹或搜索页时，必须同时检查名片夹顶部与底部、最近添加顶部、搜索页底部以及输入态 top=433 的覆盖位置。

---

## 4. Figma 使用规则

Cardi 当前设计来源为 Figma 文件 `交互名片 Copy`。

唯一设计链接：
- `https://www.figma.com/design/Vk8sBUsQh05R11tJMJPI32/%E4%BA%A4%E4%BA%92%E5%90%8D%E7%89%87--Copy-?node-id=0-1&t=fJIUVe3NlvYaytkV-1`

File Key：
- `Vk8sBUsQh05R11tJMJPI32`

以后只使用该链接和该 File Key 读取 Figma。涉及 Figma 来源的文档、说明或实现记录，都必须使用这个链接。

实现 UI 前：
- 优先读取对应 frame 的 metadata / design context。
- 保留关键节点 ID 到文档或实现注释中，便于回溯。
- 如果 Figma 无法访问或达到调用限制，必须说明哪些坐标来自 Figma，哪些来自用户文字描述。

不能做：
- 不根据单张截图臆造整个页面。
- 不把 Figma 生成的 React/Tailwind 代码直接复制进 SwiftUI。
- 不为了还原视觉而引入未经确认的第三方依赖。

---

## 5. 变更影响清单

当改动触及以下区域时，需要在动手前说明影响：

- `CardiApp.swift`：应用入口、依赖注入、数据容器。
- `ContentView.swift`：首屏 UI、导航、主要交互。
- `Item.swift`：当前 SwiftData 示例模型，后续大概率会被真实业务模型替换。
- `Assets.xcassets/`：颜色、图标、图片资源。
- 项目配置文件：构建、签名、权限、平台设置。
- 新增目录结构：架构边界与命名规则。
- 名片渲染组件：影响动态高度、保存为图片和交换预览。
- 创建/编辑名片页：影响数据输入、字段类型选择和名片预览。
- 名片夹：影响排序、分类、展开、复制、分享和保存。
- 搜索页：影响底部导航形态、键盘状态和结果保留逻辑。
- 交换能力：影响本地网络权限、Nearby Interaction、Multipeer Connectivity 和跨设备数据传递。

---

## 6. 名片布局改动专项要求

凡是改动名片生成或布局，必须在 Plan 中说明：

- 是否影响基准尺寸 370 x 222。
- 是否影响动态高度公式。
- 是否影响头像显示/隐藏。
- 是否影响公司 logo 显示/隐藏。
- 是否影响职位、姓名、英文名/拼音组的竖向居中。
- 是否影响右下角信息模块的底部锁定。
- 是否影响保存为 PNG。
- 是否影响名片夹折叠/展开展示。
- 是否影响交换时发送的图片或数据。

验收时必须检查：
- 无头像时头像圆形不占位。
- 无公司 logo 时公司名称左对齐到 logo 原位置。
- 3 段以内单行信息时名片高度为 222pt。
- 超过 3 段或文本换行时高度按规则增加。
- 最底部信息距离名片下边缘保持 20pt。
- 信息图标与对应文本第一行竖向居中。

---

## 7. 验证门槛

代码改动后，优先完成至少一种验证：

- Xcode Build 成功。
- 命令行构建成功。
- SwiftUI Preview 可正常打开。
- 核心交互可在模拟器或预览中复现。
- 针对纯文档改动，检查文件路径、命名和引用一致。
- 修改 `AppIcon.icon/` 时，必须同时确认 Target 的 App Icon 名称仍为 `AppIcon`，完成 Debug、Release 构建，并在模拟器主屏幕检查实际图标；具备条件时继续核对 Default、Dark、Tinted 三种外观。

若无法执行验证，最终交付中必须标注 **NOT VERIFIED**。

---

## 8. 输出规则

- 输出保持简洁、可复核。
- 明确列出新增或修改的文件。
- 说明已运行的验证命令或未验证原因。
- 文档状态变化后，同步更新 `README.md`、`ROADMAP.md` 或其他相关 `.md`。
- 视觉系统、图标来源、Figma 坐标或布局约束变化后，同步更新 `Designsystem.md` 或 `AGENTS.md`。
- 若任务涉及 Figma，但部分 frame 未能读取，需要说明限制。

---

## 9. 待补充

以下规则将在正式编码阶段继续补充：

- SwiftUI 模块命名规范。
- SwiftData 持久化模型。
- 图片资源存储策略。
- App 内上滑交换的完整回归清单已固化到 `ExchangeTestPlan.md`；后续实现变更必须同步更新对应测试项、当前结果和风险级别。
- 交换纯逻辑测试放在 `../CardiLogicTests/`，DEBUG Simulator 交换 UI 回归放在 `../CardiUITests/CardExchangeSimulationUITests.swift`；模拟器结果不得替代双真机 UWB 与方向证据。
- 交换修改至少回归目标选择边界、payload 总编码大小、单向/互换/回递、持久化 ACK、超时/断线和 Release 模拟入口隔离。

//
//  CardaSettingsPage.swift
//  Cardi
//

import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct CardaSettingsPage: View {
    let accountPhoneNumber: String?
    let onDestructiveDataChange: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            CardaSettingsToolbar(title: "设置")

            Form {
                Section {
                    settingsLink("名片交换") {
                        CardExchangeSettingsPage()
                    }
                    settingsLink("名片管理") {
                        CardManagementSettingsPage()
                    }
                } header: {
                    settingsSectionHeader("名片")
                }

                Section {
                    settingsLink("数据与存储") {
                        DataStorageSettingsPage(
                            accountPhoneNumber: accountPhoneNumber,
                            onDestructiveDataChange: onDestructiveDataChange
                        )
                    }
                    settingsLink("交互与辅助功能") {
                        InteractionSettingsPage()
                    }
                    settingsLink("帮助与关于") {
                        HelpAboutSettingsPage()
                    }
                } header: {
                    settingsSectionHeader("通用")
                }
            }
            .cardaSettingsFormStyle()
        }
        .cardaSettingsPageStyle()
        .accessibilityElement(children: .contain)
    }

    private func settingsLink<Destination: View>(
        _ title: String,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink(destination: destination()) {
            Text(title)
                .font(CardaTheme.pingFang(size: 17))
                .foregroundStyle(Color.black)
        }
        .accessibilityLabel(title)
    }

    private func settingsSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(CardaTheme.pingFang(size: 13))
            .accessibilityAddTraits(.isHeader)
    }
}

private struct CardExchangeSettingsPage: View {
    @AppStorage(CardaSettingsPreferenceKeys.allowsNearbyDiscovery)
    private var allowsNearbyDiscovery = true
    @AppStorage(CardaSettingsPreferenceKeys.confirmsIncomingCards)
    private var confirmsIncomingCards = true
    @AppStorage(CardaSettingsPreferenceKeys.exchangeHaptics)
    private var exchangeHaptics = true
    @AppStorage(CardaSettingsPreferenceKeys.exchangeSound)
    private var exchangeSound = true

    var body: some View {
        VStack(spacing: 0) {
            CardaSettingsToolbar(title: "名片交换")

            Form {
                Section {
                    Toggle("允许附近的 Cardi 用户发现我", isOn: $allowsNearbyDiscovery)
                    Toggle("接收名片前需要确认", isOn: $confirmsIncomingCards)
                    settingsValueRow(
                        title: "附近交换连接状态",
                        value: NearbyExchangeRangingSession.isSupported ? "本机可用" : "本机不可用"
                    )
                } header: {
                    Text("附近交换")
                } footer: {
                    Text("关闭发现后，Cardi 不会广播或搜索附近设备；正在进行的交换会立即停止。")
                        .font(CardaTheme.pingFang(size: 13))
                }

                Section("交换反馈") {
                    Toggle("交换成功时振动", isOn: $exchangeHaptics)
                    Toggle("交换成功时播放提示音", isOn: $exchangeSound)
                }
            }
            .cardaSettingsFormStyle()
        }
        .cardaSettingsPageStyle()
    }
}

private struct CardManagementSettingsPage: View {
    @Query(sort: \BusinessCardList.sortOrder) private var cardLists: [BusinessCardList]
    @AppStorage(CardaSettingsPreferenceKeys.defaultReceivedListID)
    private var defaultReceivedListID = ""
    @AppStorage(CardaSettingsPreferenceKeys.defaultCardSort)
    private var defaultCardSortRawValue = CardaDefaultCardSort.defaultValue.rawValue
    @AppStorage(CardaSettingsPreferenceKeys.duplicatePolicy)
    private var duplicatePolicyRawValue = CardaDuplicateCardPolicy.ask.rawValue
    @AppStorage(CardaSettingsPreferenceKeys.confirmsCardDeletion)
    private var confirmsCardDeletion = true

    var body: some View {
        VStack(spacing: 0) {
            CardaSettingsToolbar(title: "名片管理")

            Form {
                Section {
                    NavigationLink {
                        DefaultReceivedListSettingsPage()
                    } label: {
                        settingsValueRow(
                            title: "收到的名片默认存入",
                            value: defaultReceivedListName
                        )
                    }

                    Picker("默认排序方式", selection: $defaultCardSortRawValue) {
                        ForEach(CardaDefaultCardSort.allCases) { sort in
                            Text(sort.title).tag(sort.rawValue)
                        }
                    }

                    Picker("收到重复名片时", selection: $duplicatePolicyRawValue) {
                        ForEach(CardaDuplicateCardPolicy.allCases) { policy in
                            Text(policy.title).tag(policy.rawValue)
                        }
                    }

                    Toggle("删除名片前二次确认", isOn: $confirmsCardDeletion)
                } footer: {
                    Text("“询问”会沿用接收名片时的确认步骤；选择覆盖时会保留原名片所在列表。")
                        .font(CardaTheme.pingFang(size: 13))
                }
            }
            .cardaSettingsFormStyle()
        }
        .cardaSettingsPageStyle()
    }

    private var defaultReceivedListName: String {
        guard
            let id = UUID(uuidString: defaultReceivedListID),
            let list = cardLists.first(where: { $0.id == id })
        else {
            return "未分类"
        }
        return list.name
    }
}

private struct DefaultReceivedListSettingsPage: View {
    @Query(sort: \BusinessCardList.sortOrder) private var cardLists: [BusinessCardList]
    @AppStorage(CardaSettingsPreferenceKeys.defaultReceivedListID)
    private var defaultReceivedListID = ""

    var body: some View {
        VStack(spacing: 0) {
            CardaSettingsToolbar(title: "默认存入列表")

            Form {
                Section {
                    selectionRow(title: "未分类", rawValue: "")
                    ForEach(cardLists) { list in
                        selectionRow(title: list.name, rawValue: list.id.uuidString)
                    }
                }
            }
            .cardaSettingsFormStyle()
        }
        .cardaSettingsPageStyle()
        .onChange(of: cardLists.map(\.id)) { _, availableIDs in
            guard
                let selectedID = UUID(uuidString: defaultReceivedListID),
                !availableIDs.contains(selectedID)
            else {
                return
            }
            defaultReceivedListID = ""
        }
    }

    private func selectionRow(title: String, rawValue: String) -> some View {
        Button {
            defaultReceivedListID = rawValue
        } label: {
            HStack {
                Text(title)
                    .font(CardaTheme.pingFang(size: 17))
                    .foregroundStyle(Color.black)
                Spacer()
                if defaultReceivedListID == rawValue {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(CardaTheme.systemSelectionBlue)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(defaultReceivedListID == rawValue ? "已选择" : "")
    }
}

private struct InteractionSettingsPage: View {
    @AppStorage(CardaSettingsPreferenceKeys.interactionHaptics)
    private var interactionHaptics = true
    @AppStorage(CardaSettingsPreferenceKeys.interactionSound)
    private var interactionSound = true
    @AppStorage(CardaSettingsPreferenceKeys.motionPreference)
    private var motionPreferenceRawValue = CardaMotionPreference.followSystem.rawValue
    @AppStorage(CardaSettingsPreferenceKeys.followsSystemFontSize)
    private var followsSystemFontSize = true
    @AppStorage(CardaSettingsPreferenceKeys.allowsCardPaging)
    private var allowsCardPaging = true

    var body: some View {
        VStack(spacing: 0) {
            CardaSettingsToolbar(title: "交互与辅助功能")

            Form {
                Section("反馈") {
                    Toggle("触觉反馈", isOn: $interactionHaptics)
                    Toggle("操作提示音", isOn: $interactionSound)
                }

                Section {
                    Picker("动画效果", selection: $motionPreferenceRawValue) {
                        ForEach(CardaMotionPreference.allCases) { preference in
                            Text(preference.title).tag(preference.rawValue)
                        }
                    }
                    Toggle("字体大小跟随系统", isOn: $followsSystemFontSize)
                    Toggle("左右滑动切换名片", isOn: $allowsCardPaging)
                } header: {
                    Text("显示与操作")
                } footer: {
                    Text("系统开启“减弱动态效果”时，Cardi 始终优先遵循系统辅助功能设置。")
                        .font(CardaTheme.pingFang(size: 13))
                }
            }
            .cardaSettingsFormStyle()
        }
        .cardaSettingsPageStyle()
    }
}

private struct DataStorageSettingsPage: View {
    private enum PresentedAlert: Identifiable {
        case deleteCurrentAccount
        case deleteAllData
        case message(title: String, message: String)

        var id: String {
            switch self {
            case .deleteCurrentAccount:
                "delete-current"
            case .deleteAllData:
                "delete-all"
            case .message(let title, let message):
                "message-\(title)-\(message)"
            }
        }
    }

    @Environment(\.modelContext) private var modelContext
    @AppStorage(AccountPreferenceKeys.avatarImageData)
    private var storedAccountAvatarImageData = Data()
    @AppStorage(AccountPreferenceKeys.name)
    private var storedAccountName = ""
    @AppStorage(AccountPreferenceKeys.phoneNumber)
    private var storedAccountPhoneNumber = ""
    @AppStorage(AccountPreferenceKeys.email)
    private var storedAccountEmail = ""
    @AppStorage(AccountPreferenceKeys.hasActivatedLocalAccountStorage)
    private var hasActivatedLocalAccountStorage = false

    let accountPhoneNumber: String?
    let onDestructiveDataChange: () -> Void

    @State private var storageDescription = "计算中…"
    @State private var exportDocument = CardaBackupDocument()
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var presentedAlert: PresentedAlert?

    var body: some View {
        VStack(spacing: 0) {
            CardaSettingsToolbar(title: "数据与存储")

            Form {
                Section("存储") {
                    settingsValueRow(title: "本地账户占用空间", value: storageDescription)
                    Button("清理图片缓存", action: clearImageCache)
                        .foregroundStyle(Color.black)
                }

                Section {
                    Button("导出账户与名片备份", action: prepareExport)
                        .disabled(canonicalPhoneNumber == nil)
                    Button("从备份文件恢复", action: { isImporting = true })
                        .disabled(canonicalPhoneNumber == nil)
                } header: {
                    Text("备份")
                } footer: {
                    Text("备份文件包含当前本地账户资料、自己的名片、收到的名片和列表，不包含登录密码。仅可恢复到相同手机号。")
                        .font(CardaTheme.pingFang(size: 13))
                }

                Section {
                    Button("删除当前账户的本地数据", role: .destructive) {
                        presentedAlert = .deleteCurrentAccount
                    }
                    .disabled(canonicalPhoneNumber == nil)

                    Button("删除全部 Cardi 本地数据", role: .destructive) {
                        presentedAlert = .deleteAllData
                    }
                }
            }
            .cardaSettingsFormStyle()
        }
        .cardaSettingsPageStyle()
        .task { refreshStorageDescription() }
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .json,
            defaultFilename: backupFileName
        ) { result in
            switch result {
            case .success:
                presentedAlert = .message(title: "备份已导出", message: "请妥善保存备份文件。")
            case .failure(let error):
                presentedAlert = .message(title: "无法导出备份", message: error.localizedDescription)
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            importBackup(result)
        }
        .alert(item: $presentedAlert) { alert in
            switch alert {
            case .deleteCurrentAccount:
                Alert(
                    title: Text("删除当前账户的本地数据？"),
                    message: Text("该手机号的资料、名片、列表和本机登录凭据都会被永久删除，无法撤销。"),
                    primaryButton: .destructive(Text("删除"), action: deleteCurrentAccountData),
                    secondaryButton: .cancel(Text("取消"))
                )
            case .deleteAllData:
                Alert(
                    title: Text("删除全部 Cardi 本地数据？"),
                    message: Text("所有本地账户、名片、列表、登录凭据和设置都会被永久删除，无法撤销。"),
                    primaryButton: .destructive(Text("全部删除"), action: deleteAllLocalData),
                    secondaryButton: .cancel(Text("取消"))
                )
            case .message(let title, let message):
                Alert(
                    title: Text(title),
                    message: Text(message),
                    dismissButton: .default(Text("好"))
                )
            }
        }
    }

    private var canonicalPhoneNumber: String? {
        LocalAccountCardStore.canonicalPhoneNumber(
            accountPhoneNumber ?? storedAccountPhoneNumber
        )
    }

    private var backupFileName: String {
        guard let canonicalPhoneNumber else { return "Cardi-Backup" }
        return "Cardi-\(canonicalPhoneNumber)-Backup"
    }

    private func refreshStorageDescription() {
        do {
            let store = LocalAccountCardStore()
            let bytes: Int64
            if let canonicalPhoneNumber {
                bytes = try store.storageSize(for: canonicalPhoneNumber)
            } else {
                bytes = try store.totalStorageSize()
            }
            storageDescription = ByteCountFormatter.string(
                fromByteCount: bytes,
                countStyle: .file
            )
        } catch {
            storageDescription = "无法读取"
        }
    }

    private func clearImageCache() {
        URLCache.shared.removeAllCachedResponses()
        LocalSVGIconView.clearCache()
        refreshStorageDescription()
        presentedAlert = .message(title: "缓存已清理", message: "名片、账户头像和公司 Logo 不会被删除。")
    }

    private func prepareExport() {
        guard let canonicalPhoneNumber else { return }
        do {
            let data = try LocalAccountCardStore().portableBackupData(
                for: canonicalPhoneNumber,
                in: modelContext
            )
            exportDocument = CardaBackupDocument(data: data)
            isExporting = true
        } catch {
            presentedAlert = .message(title: "无法创建备份", message: error.localizedDescription)
        }
    }

    private func importBackup(_ result: Result<[URL], Error>) {
        do {
            guard
                let canonicalPhoneNumber,
                let url = try result.get().first
            else {
                return
            }
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            let data = try Data(contentsOf: url)
            if let profile = try LocalAccountCardStore().restorePortableBackup(
                from: data,
                for: canonicalPhoneNumber,
                in: modelContext
            ) {
                storedAccountAvatarImageData = profile.avatarImageData ?? Data()
                storedAccountName = profile.name
                storedAccountPhoneNumber = profile.phoneNumber
                storedAccountEmail = profile.email
                hasActivatedLocalAccountStorage = true
            }
            refreshStorageDescription()
            presentedAlert = .message(title: "备份已恢复", message: "账户资料、名片和列表已经从备份文件恢复。")
        } catch {
            presentedAlert = .message(title: "无法恢复备份", message: error.localizedDescription)
        }
    }

    private func deleteCurrentAccountData() {
        guard let canonicalPhoneNumber else { return }
        do {
            let store = LocalAccountCardStore()
            try store.clearCurrentDatabase(in: modelContext)
            try store.removeAccountDirectory(for: canonicalPhoneNumber)
            try LocalAccountCredentialStore().removeCredential(for: canonicalPhoneNumber)
            clearActiveAccountProfile()
            hasActivatedLocalAccountStorage = true
            onDestructiveDataChange()
        } catch {
            presentResult(title: "无法删除本地账户", message: error.localizedDescription)
        }
    }

    private func deleteAllLocalData() {
        do {
            let store = LocalAccountCardStore()
            try store.clearCurrentDatabase(in: modelContext)
            try store.removeAllAccountDirectories()
            try LocalAccountCredentialStore().removeAllCredentials()
            clearActiveAccountProfile()
            resetApplicationPreferences()
            hasActivatedLocalAccountStorage = true
            onDestructiveDataChange()
        } catch {
            presentResult(title: "无法删除全部数据", message: error.localizedDescription)
        }
    }

    private func clearActiveAccountProfile() {
        storedAccountAvatarImageData = Data()
        storedAccountName = ""
        storedAccountPhoneNumber = ""
        storedAccountEmail = ""
    }

    private func resetApplicationPreferences() {
        CardaSettingsPreferenceKeys.reset()
        UserDefaults.standard.set(
            LinkedApplicationCategory.browser.defaultApplicationID.rawValue,
            forKey: LinkedApplicationPreferenceKeys.browser
        )
        UserDefaults.standard.set(
            LinkedApplicationCategory.mail.defaultApplicationID.rawValue,
            forKey: LinkedApplicationPreferenceKeys.mail
        )
        UserDefaults.standard.set(
            LinkedApplicationCategory.maps.defaultApplicationID.rawValue,
            forKey: LinkedApplicationPreferenceKeys.maps
        )
        UserDefaults.standard.removeObject(forKey: "CardaExchangeLocalPeerUUID")
    }

    private func presentResult(title: String, message: String) {
        DispatchQueue.main.async {
            presentedAlert = .message(title: title, message: message)
        }
    }
}

private struct HelpAboutSettingsPage: View {
    @StateObject private var exchangeDiagnostics = CardExchangeDiagnostics.shared
    @State private var diagnosticUnlockTapCount = 0
    @State private var diagnosticsUnlocked = false

    private var appVersion: String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "1.0"
        let build = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "1"
        return "\(version) (\(build))"
    }

    private var feedbackTemplate: String {
        """
        Cardi 意见反馈

        版本：\(appVersion)
        设备：请补充
        问题或建议：请补充
        """
    }

    var body: some View {
        VStack(spacing: 0) {
            CardaSettingsToolbar(title: "帮助与关于")

            Form {
                Section("帮助") {
                    NavigationLink("Cardi 使用帮助") {
                        SettingsTextPage(
                            title: "使用帮助",
                            paragraphs: CardaSettingsCopy.usageHelp
                        )
                    }
                    NavigationLink("名片交换说明") {
                        SettingsTextPage(
                            title: "名片交换说明",
                            paragraphs: CardaSettingsCopy.exchangeHelp
                        )
                    }
                    ShareLink(item: feedbackTemplate) {
                        Text("意见反馈")
                            .font(CardaTheme.pingFang(size: 17))
                            .foregroundStyle(Color.black)
                    }
                }

                Section("关于") {
                    Button(action: registerVersionTap) {
                        settingsValueRow(title: "当前版本", value: appVersion)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if diagnosticsUnlocked || exchangeDiagnostics.isRecording {
                        NavigationLink("交换诊断") {
                            CardExchangeDiagnosticsPage()
                        }
                        .accessibilityIdentifier("settings.exchangeDiagnostics")
                    }
                    NavigationLink("隐私政策") {
                        SettingsTextPage(
                            title: "隐私政策",
                            paragraphs: CardaSettingsCopy.privacy
                        )
                    }
                    NavigationLink("用户协议") {
                        SettingsTextPage(
                            title: "用户协议",
                            paragraphs: CardaSettingsCopy.terms
                        )
                    }
                    NavigationLink("开源许可") {
                        SettingsTextPage(
                            title: "开源许可",
                            paragraphs: CardaSettingsCopy.licenses
                        )
                    }
                }
            }
            .cardaSettingsFormStyle()
        }
        .cardaSettingsPageStyle()
    }

    private func registerVersionTap() {
        guard !diagnosticsUnlocked else { return }
        diagnosticUnlockTapCount += 1
        if diagnosticUnlockTapCount >= 7 {
            diagnosticsUnlocked = true
            diagnosticUnlockTapCount = 0
        }
    }
}

private struct SettingsTextPage: View {
    let title: String
    let paragraphs: [String]

    var body: some View {
        VStack(spacing: 0) {
            CardaSettingsToolbar(title: title)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                        Text(paragraph)
                            .font(CardaTheme.pingFang(size: 16))
                            .foregroundStyle(Color.black.opacity(0.78))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 40)
            }
        }
        .cardaSettingsPageStyle()
    }
}

struct CardaSettingsToolbar: View {
    @Environment(\.dismiss) private var dismiss

    let title: String

    var body: some View {
        ZStack(alignment: .top) {
            Button(action: dismiss.callAsFunction) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.black)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(CardaTheme.searchBackground.opacity(0.5)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 16)
            .padding(.top, 16)
            .accessibilityLabel("返回")

            Text(title)
                .font(CardaTheme.pingFang(size: 17, weight: .medium))
                .foregroundStyle(Color.black)
                .frame(height: 22)
                .padding(.top, 29)
                .accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 70, alignment: .top)
        .background(CardaTheme.pageBackground)
    }
}

private struct CardaBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private enum CardaSettingsCopy {
    static let usageHelp = [
        "在“我的名片”中创建和左右切换自己的名片；长按名片可以编辑、保存为图片或删除。",
        "在“名片夹”中按列表、姓名或公司查看收到的名片，并可搜索、分类和调整所属列表。",
        "点击页面右上角头像可以添加名片、登录本地账户、进入设置或修改关联应用。"
    ]

    static let exchangeHelp = [
        "在“我的名片”页面向上滑动当前名片，Cardi 会寻找约 1.5 米内最近且目标明确的 Cardi 用户。",
        "双方在短时间内同时上滑时会互换名片；单向收到名片后，也可以在接收界面选择回递自己的名片。",
        "附近交换依赖蓝牙、本地网络和精准距离测量；设备支持时会同时校验方向，不支持方向时只会选择唯一且距离明确最近的设备。关闭“允许附近的 Cardi 用户发现我”后不会进行附近交换。"
    ]

    static let privacy = [
        "Cardi 当前为本地版本。账户资料、名片、列表和设置默认保存在当前设备，不提供云端登录或跨设备同步。",
        "附近名片交换只在用户发起或允许交换时，通过本地连接把所选名片发送给附近设备。",
        "导出的备份文件可能包含头像、联系方式和名片内容，请由用户自行选择安全位置保存。备份文件不包含登录密码。"
    ]

    static let terms = [
        "Cardi 当前处于本地功能阶段。用户应确保创建、保存和交换的名片内容真实、合法，并已获得处理相关联系方式和图片的必要授权。",
        "删除本地账户或全部本地数据后无法撤销；执行删除前请根据需要导出备份。",
        "正式发布前，用户协议内容仍可能根据产品功能和服务范围更新。"
    ]

    static let licenses = [
        "当前工程未引入第三方 Swift Package。项目自身许可仍为 TBD。",
        "界面中出现的浏览器、邮箱和地图应用名称及标志属于各自权利人，仅用于帮助用户识别已安装的关联应用。"
    ]
}

private func settingsValueRow(title: String, value: String) -> some View {
    HStack(spacing: 12) {
        Text(title)
            .font(CardaTheme.pingFang(size: 17))
            .foregroundStyle(Color.black)
        Spacer(minLength: 8)
        Text(value)
            .font(CardaTheme.pingFang(size: 16))
            .foregroundStyle(Color.black.opacity(0.5))
            .lineLimit(1)
    }
}

extension View {
    func cardaSettingsFormStyle() -> some View {
        formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(CardaTheme.pageBackground)
            .environment(\.defaultMinListRowHeight, 52)
            .tint(CardaTheme.systemSelectionBlue)
    }

    func cardaSettingsPageStyle() -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(CardaTheme.pageBackground)
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
    }
}

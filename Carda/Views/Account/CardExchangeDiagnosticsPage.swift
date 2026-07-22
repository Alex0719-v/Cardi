//
//  CardExchangeDiagnosticsPage.swift
//  Cardi
//

import SwiftUI
import UniformTypeIdentifiers

struct CardExchangeDiagnosticsPage: View {
    private enum PresentedAlert: Identifiable {
        case invalidCode
        case exportFailure(String)
        case clearConfirmation

        var id: String {
            switch self {
            case .invalidCode:
                "invalid-code"
            case .exportFailure(let message):
                "export-\(message)"
            case .clearConfirmation:
                "clear-confirmation"
            }
        }
    }

    @StateObject private var diagnostics = CardExchangeDiagnostics.shared
    @State private var testCode = ""
    @State private var role: CardExchangeDiagnosticRole = .deviceA
    @State private var exportDocument = CardExchangeDiagnosticDocument()
    @State private var exportFilename = "Cardi-Exchange-Diagnostic"
    @State private var isExporting = false
    @State private var presentedAlert: PresentedAlert?
    @FocusState private var isTestCodeFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            CardaSettingsToolbar(title: "交换诊断")

            Form {
                Section {
                    HStack(spacing: 12) {
                        Text("测试编号")
                            .font(CardaTheme.pingFang(size: 17))
                        Spacer(minLength: 8)
                        TextField("六位数字", text: $testCode)
                            .font(.system(size: 17))
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .focused($isTestCodeFocused)
                            .disabled(diagnostics.isRecording)
                            .accessibilityIdentifier("diagnostics.testCode")
                    }

                    Picker("本机标记", selection: $role) {
                        ForEach(CardExchangeDiagnosticRole.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(diagnostics.isRecording)

                    if diagnostics.isRecording {
                        Button("结束本次记录", role: .destructive) {
                            isTestCodeFocused = false
                            diagnostics.stop()
                        }
                    } else {
                        Button("开始记录") {
                            startRecording()
                        }
                        .disabled(testCode.count != 6)
                    }
                } header: {
                    Text("双机配对")
                } footer: {
                    Text("两台设备填写相同编号，并分别选择设备 A 和设备 B。开始后返回“我的名片”完成一次交换，再回到这里结束并导出。")
                        .font(CardaTheme.pingFang(size: 13))
                }

                Section("当前状态") {
                    diagnosticValueRow(
                        title: "记录状态",
                        value: diagnostics.isRecording ? "记录中" : "已停止"
                    )
                    diagnosticValueRow(
                        title: "事件数量",
                        value: String(diagnostics.eventCount)
                    )
                    diagnosticValueRow(
                        title: "最近阶段",
                        value: latestStageDescription
                    )
                }

                Section("本机能力") {
                    diagnosticValueRow(
                        title: "精准距离测量",
                        value: NearbyExchangeRangingSession.supportsPreciseDistanceMeasurement
                            ? "支持"
                            : "不支持"
                    )
                    diagnosticValueRow(
                        title: "方向测量",
                        value: NearbyExchangeRangingSession.supportsDirectionMeasurement
                            ? "支持"
                            : "不支持，使用距离模式"
                    )
                }

                Section {
                    Button("导出诊断 JSON") {
                        prepareExport()
                    }
                    .disabled(!hasExportableSession)

                    Button("清除诊断记录", role: .destructive) {
                        presentedAlert = .clearConfirmation
                    }
                    .disabled(diagnostics.isRecording || !hasExportableSession)
                } header: {
                    Text("诊断包")
                } footer: {
                    Text("仅保留最近 5 次记录。诊断包不包含姓名、手机号、邮箱、名片文字、图片或原始识别令牌；设备与附近对象只记录不可逆摘要。")
                        .font(CardaTheme.pingFang(size: 13))
                }
            }
            .cardaSettingsFormStyle()
        }
        .cardaSettingsPageStyle()
        .onAppear(perform: restoreActiveSessionFields)
        .onChange(of: testCode) { _, newValue in
            let normalized = CardExchangeDiagnostics.normalizedTestCode(newValue)
            if normalized != newValue {
                testCode = normalized
            }
        }
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .json,
            defaultFilename: exportFilename
        ) { _ in }
        .alert(item: $presentedAlert) { alert in
            switch alert {
            case .invalidCode:
                Alert(
                    title: Text("测试编号无效"),
                    message: Text("请输入六位数字，并确保两台设备使用相同编号。"),
                    dismissButton: .default(Text("好"))
                )
            case .exportFailure(let message):
                Alert(
                    title: Text("无法导出诊断包"),
                    message: Text(message),
                    dismissButton: .default(Text("好"))
                )
            case .clearConfirmation:
                Alert(
                    title: Text("清除全部交换诊断记录？"),
                    message: Text("清除后无法恢复。"),
                    primaryButton: .destructive(Text("清除")) {
                        diagnostics.clearSavedSessions()
                    },
                    secondaryButton: .cancel(Text("取消"))
                )
            }
        }
    }

    private var hasExportableSession: Bool {
        diagnostics.activeSummary != nil || diagnostics.latestSavedSummary != nil
    }

    private var latestStageDescription: String {
        guard let stage = diagnostics.latestStage else { return "暂无" }
        let stageName: String
        switch stage {
        case .session: stageName = "诊断会话"
        case .lifecycle: stageName = "交换生命周期"
        case .gesture: stageName = "上滑手势"
        case .discovery: stageName = "附近发现"
        case .connection: stageName = "设备连接"
        case .token: stageName = "识别令牌"
        case .ranging: stageName = "距离与方向"
        case .targetSelection: stageName = "目标选择"
        case .intent: stageName = "交换意图"
        case .transfer: stageName = "名片传输"
        case .persistence: stageName = "保存确认"
        case .animation: stageName = "交换动画"
        case .failure: stageName = "失败"
        }
        if let eventName = diagnostics.latestEventName {
            return "\(stageName) · \(eventName)"
        }
        return stageName
    }

    private func startRecording() {
        isTestCodeFocused = false
        let capabilities = CardExchangeDiagnosticCapabilities(
            preciseDistance: NearbyExchangeRangingSession.supportsPreciseDistanceMeasurement,
            direction: NearbyExchangeRangingSession.supportsDirectionMeasurement
        )
        guard diagnostics.start(
            testCode: testCode,
            role: role,
            capabilities: capabilities
        ) else {
            presentedAlert = .invalidCode
            return
        }
    }

    private func prepareExport() {
        do {
            exportDocument = CardExchangeDiagnosticDocument(
                data: try diagnostics.exportData()
            )
            exportFilename = diagnostics.suggestedExportFilename
            isExporting = true
        } catch {
            presentedAlert = .exportFailure(error.localizedDescription)
        }
    }

    private func restoreActiveSessionFields() {
        guard let summary = diagnostics.activeSummary else { return }
        testCode = summary.testCode
        role = summary.role
    }

    private func diagnosticValueRow(title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(CardaTheme.pingFang(size: 17))
                .foregroundStyle(Color.black)
            Spacer(minLength: 8)
            Text(value)
                .font(CardaTheme.pingFang(size: 15))
                .foregroundStyle(Color.black.opacity(0.5))
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct CardExchangeDiagnosticDocument: FileDocument {
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

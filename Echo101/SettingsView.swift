import SwiftUI
import UIKit
import UniformTypeIdentifiers
import EchoCore
import EchoAPI

struct ParentSettingsSection: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var store: EchoStore
    @EnvironmentObject private var audio: AudioController
    @ScaledMetric(relativeTo: .title3) private var bodySize: CGFloat = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("设置")
                .font(.system(size: max(24, bodySize), weight: .semibold))
            Picker("模型", selection: Binding(get: { model.api.configuration.provider }, set: { model.setProvider($0) })) {
                Text("DeepSeek").tag(ModelProvider.deepSeek)
                Text("小米 MiMo").tag(ModelProvider.miMo)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("providerPicker")
            Text("只有句库对不上时，才会把老人这句话识别出的文字发给 \(model.api.configuration.provider == .deepSeek ? "DeepSeek" : "小米 MiMo")。声音不上传。生成的英文可以先听，但不会自动进句库，也不会进每天轮换，除非你在上面确认。")
                .font(.system(size: max(20, bodySize)))
            Toggle("我已了解，并同意在需要时发送这句话", isOn: Binding(
                get: { store.snapshot.settings.consentGranted },
                set: { model.setConsent($0) }
            ))
            .font(.system(size: max(20, bodySize)))
            .accessibilityIdentifier("consentToggle")
            Toggle("允许使用蜂窝数据", isOn: Binding(
                get: { store.snapshot.settings.allowCellular },
                set: { model.setCellular($0) }
            ))
            .font(.system(size: max(20, bodySize)))
            .accessibilityIdentifier("cellularToggle")
            Text(store.snapshot.settings.allowCellular ? "没有 Wi-Fi 时也可以问模型。" : "模型默认只用 Wi-Fi。")
                .font(.system(size: max(20, bodySize)))
                .foregroundStyle(EchoStyle.quiet)
            Picker("英文声音", selection: $audio.selectedVoiceID) {
                Text("系统美式英语").tag("")
                ForEach(audio.voices) { voice in
                    Text("\(voice.name) · \(voice.quality)").tag(voice.id)
                }
            }
            .accessibilityIdentifier("voicePicker")
            NavigationLink("填写 API Key") { KeyEntryView() }
                .font(.system(size: max(20, bodySize), weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 64)
                .accessibilityIdentifier("openKeyEntry")
            Button("试听当前英文声音") {
                audio.speakEnglishLesson("Let's wash our hands.")
            }
            .buttonStyle(GrandparentButtonStyle(filled: false))
            .accessibilityIdentifier("previewVoice")
        }
        .onAppear { audio.refreshCapabilities() }
    }
}

struct KeyEntryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var key = ""
    @State private var checking = true
    @ScaledMetric(relativeTo: .title3) private var bodySize: CGFloat = 20

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if checking {
                    Text("正在确认是爸妈本人。")
                        .font(.system(size: max(20, bodySize)))
                } else if model.keyUnlocked {
                    Text("Key 只存在这台手机的钥匙串里，不会写进句库，也不会出现在导出文件里。")
                        .font(.system(size: max(20, bodySize)))
                    SecureField("API Key", text: $key)
                        .font(.system(size: max(20, bodySize)))
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("apiKeyField")
                    Button("保存 Key") { save() }
                        .buttonStyle(GrandparentButtonStyle())
                        .accessibilityIdentifier("saveKey")
                    Button("删除 Key") { remove() }
                        .buttonStyle(GrandparentButtonStyle(filled: false))
                        .accessibilityIdentifier("deleteKey")
                    Text(model.api.hasKey(for: model.api.configuration.provider) ? "当前供应商已有 Key。" : "当前供应商还没有 Key。")
                        .font(.system(size: max(20, bodySize)))
                } else {
                    Text(model.parentStatus.isEmpty ? "需要设备密码才能填写 Key。" : model.parentStatus)
                        .font(.system(size: max(20, bodySize)))
                }
            }
            .padding(24)
        }
        .background(Color.white)
        .foregroundStyle(Color.black)
        .navigationTitle("API Key")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            checking = true
            _ = await model.authorizeKeyEntry()
            checking = false
        }
    }

    private func save() {
        do {
            try model.api.setAPIKey(key, provider: model.api.configuration.provider)
            key = ""
            model.parentStatus = "Key 已保存。"
        } catch {
            model.parentStatus = "Key 没有保存。请检查没有空格或中文。"
        }
    }

    private func remove() {
        try? model.api.deleteAPIKey(for: model.api.configuration.provider)
        key = ""
        model.parentStatus = "Key 已从这台手机删除。供应商那边的 Key 需要你自己作废。"
    }
}

struct ParentExportSection: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var store: EchoStore
    @State private var includeAudio = true
    @State private var exportFile: ExportFile?
    @State private var importing = false
    @State private var importURL: URL?
    @State private var confirmingImport = false
    @State private var confirmingDelete = false
    @ScaledMetric(relativeTo: .title3) private var bodySize: CGFloat = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("导出与恢复")
                .font(.system(size: max(24, bodySize), weight: .semibold))
            Text(exportLabel)
                .font(.system(size: max(20, bodySize)))
                .accessibilityIdentifier("exportReminder")
            Toggle("导出时包含录音", isOn: $includeAudio)
                .font(.system(size: max(20, bodySize)))
                .accessibilityIdentifier("includeAudioToggle")
            Button("导出一份") { prepareExport() }
                .buttonStyle(GrandparentButtonStyle())
                .accessibilityIdentifier("prepareExport")
            Button("从恢复包恢复") { importing = true }
                .buttonStyle(GrandparentButtonStyle(filled: false))
                .accessibilityIdentifier("restoreArchive")
            Button("清空本机内容") { confirmingDelete = true }
                .buttonStyle(GrandparentButtonStyle(filled: false))
                .accessibilityIdentifier("deleteAll")
            Text("恢复包是未加密的 JSON。分享之后就不再受 App 的文件保护。导出副本会在分享结束时从 App 里删掉，下次打开也会清掉残留。")
                .font(.system(size: max(20, bodySize)))
                .foregroundStyle(EchoStyle.quiet)
        }
        .sheet(item: $exportFile) { file in
            ShareSheet(url: file.url) { completed in
                try? store.removeExportFile(at: file.url)
                if completed { try? store.markExported() }
                exportFile = nil
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                importURL = url
                confirmingImport = true
            } else {
                model.parentStatus = "没有选中文件。本机内容没有改。"
            }
        }
        .alert("用这个恢复包替换本机内容？", isPresented: $confirmingImport) {
            Button("恢复") { restore() }
            Button("取消", role: .cancel) { importURL = nil }
        } message: {
            Text(store.snapshot.isEmpty || store.snapshot.isPristineSeededLibrary
                 ? "只会写入这个空的或仅有内置例句的资料库。Key 不会被恢复。"
                 : "请先清空本机内容，再恢复。现在还没有改动。")
        }
        .alert("清空这台手机上的句子和录音？", isPresented: $confirmingDelete) {
            Button("清空", role: .destructive) { model.clearAllContent() }
            Button("取消", role: .cancel) {}
        } message: { Text("清空后才能把一份旧的恢复包导回来。导出的文件不会被这步删掉。") }
    }

    private var exportLabel: String {
        if let date = store.snapshot.settings.lastExportAt {
            let formatted = date.formatted(date: .abbreviated, time: .shortened)
            if model.exportOverdue { return "上次导出是 \(formatted)，已经超过 7 天。" }
            return "上次导出：\(formatted)。"
        }
        return "还没有导出过。手机丢了或删了 App，句子和录音就没了。"
    }

    private func prepareExport() {
        do {
            let url = try store.exportArchive(includeAudio: includeAudio)
            exportFile = ExportFile(url: url)
        } catch {
            model.parentStatus = "导出没有完成。"
        }
    }

    private func restore() {
        guard let importURL else { return }
        let access = importURL.startAccessingSecurityScopedResource()
        defer {
            if access { importURL.stopAccessingSecurityScopedResource() }
            self.importURL = nil
        }
        guard store.snapshot.isEmpty || store.snapshot.isPristineSeededLibrary else {
            model.parentStatus = "请先清空本机内容，再恢复。"
            return
        }
        do {
            try store.restoreArchive(fromURL: importURL)
            model.parentStatus = "已经恢复。"
        } catch {
            model.parentStatus = "没有恢复。文件可能损坏，或这不是 Echo 的恢复包。"
        }
    }
}

struct ExportFile: Identifiable {
    let url: URL
    var id: String { url.path }
}

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    var onFinish: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        nonisolated(unsafe) let finish = onFinish
        controller.completionWithItemsHandler = { _, completed, _, _ in
            let finished = completed
            Task { @MainActor in finish(finished) }
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

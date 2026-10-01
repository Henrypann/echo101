import SwiftUI
import EchoCore
import EchoAPI
import UniformTypeIdentifiers

struct ParentGateView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var store: EchoStore
    var body: some View {
        if model.parentUnlocked {
            ParentHome()
        } else {
            VStack(spacing: 24) {
                Text("这里是爸妈用的")
                    .font(.system(size: 34, weight: .bold))
                    .multilineTextAlignment(.center)
                Text(model.pendingCount == 0 ? "没有句子等确认" : "\(model.pendingCount) 句等着确认")
                    .font(.system(size: 24, weight: .semibold))
                HoldToEnterButton { model.parentUnlocked = true }
            }
            .foregroundStyle(Color.black)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white)
            .padding(24)
        }
    }
}

struct ParentHome: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var store: EchoStore
    @EnvironmentObject private var api: ModelService
    @EnvironmentObject private var audio: AudioController
    @State private var exportFile: ExportFile?
    @State private var includeAudio = true
    @State private var importing = false
    @State private var confirmErase = false
    @State private var editing: SpokenRecord?
    @State private var editingPhrase: LibraryPhrase?
    @State private var message = ""
    @State private var showCredits = false
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                Text("晚间回看")
                    .font(.system(size: 28, weight: .bold))
                if store.snapshot.records.isEmpty {
                    Text("还没有句子").font(.system(size: 20))
                }
                ForEach(store.snapshot.records) { record in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(record.recognizedText.isEmpty ? "（没有原话）" : record.recognizedText)
                            .font(.system(size: 20, weight: .semibold))
                        Text(record.chineseMeaning.isEmpty ? "中文还空着" : record.chineseMeaning)
                            .font(.system(size: 20))
                        Text(record.english.isEmpty ? "英文还空着" : record.english)
                            .font(.system(size: 20))
                        if record.waitsForParent {
                            Text("待确认").font(.system(size: 20)).foregroundStyle(EchoStyle.textSecondary)
                        }
                        HStack {
                            if let name = record.grandparentAudio {
                                Button("听原话") { model.playChild(filename: name) }.font(.system(size: 20, weight: .semibold))
                            }
                            if let name = record.childAudio {
                                Button("听孩子") { model.playChild(filename: name) }.font(.system(size: 20, weight: .semibold))
                            }
                            Button("修改") { editing = record }.font(.system(size: 20, weight: .semibold))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                }
                Text("句库").font(.system(size: 28, weight: .bold))
                ForEach(store.snapshot.phrases) { phrase in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(phrase.chinese).font(.system(size: 20, weight: .semibold))
                            Text(phrase.english).font(.system(size: 20))
                        }
                        Spacer()
                        Button("改") { editingPhrase = phrase }.font(.system(size: 20, weight: .semibold))
                    }
                }
                Text("需要处理").font(.system(size: 28, weight: .bold))
                if store.snapshot.setupIssues.isEmpty {
                    Text("没有待处理的设置").font(.system(size: 20))
                }
                ForEach(store.snapshot.setupIssues) { issue in
                    VStack(alignment: .leading) {
                        Text(issue.message).font(.system(size: 20))
                        Button("我处理好了") { try? store.resolveSetupIssue(code: issue.code) }
                            .font(.system(size: 20, weight: .semibold))
                    }
                }
                Text("备份").font(.system(size: 28, weight: .bold))
                Text(exportLabel).font(.system(size: 20))
                if store.snapshot.exportIsOverdue {
                    Text("已经超过 7 天没有导出。手机丢了，这些话就找不回来。")
                        .font(.system(size: 20))
                }
                Toggle("导出时带上录音", isOn: $includeAudio).font(.system(size: 20))
                Button("导出备份") {
                    if let url = try? store.exportArchive(includeAudio: includeAudio) {
                        exportFile = ExportFile(url: url)
                    }
                }
                .font(.system(size: 20, weight: .semibold))
                Button("从备份恢复") { importing = true }.font(.system(size: 20, weight: .semibold))
                Button("清空本机数据") { confirmErase = true }.font(.system(size: 20, weight: .semibold))
                if !message.isEmpty { Text(message).font(.system(size: 20)) }
                Text("设置").font(.system(size: 28, weight: .bold))
                Picker("模型", selection: Binding(
                    get: { api.configuration.provider },
                    set: { provider in
                        api.configuration.provider = provider
                        api.configuration.modelID = provider.defaultModelID
                    })) {
                    Text("DeepSeek").tag(ModelProvider.deepSeek)
                    Text("小米 MiMo").tag(ModelProvider.miMo)
                }
                .font(.system(size: 20))
                Toggle("我知道老人说的中文文字会发给 DeepSeek 或小米", isOn: Binding(
                    get: { store.snapshot.consentGrantedAt != nil },
                    set: { model.setConsent($0) }))
                    .font(.system(size: 20))
                Text("只发送识别后的文字，不发送录音。不打开的话，对不上句库的句子会先记下来。")
                    .font(.system(size: 20))
                    .foregroundStyle(EchoStyle.textSecondary)
                Toggle("允许使用蜂窝数据", isOn: Binding(
                    get: { store.snapshot.allowCellular },
                    set: { model.setCellular($0) }))
                    .font(.system(size: 20))
                Button("填写 API Key") { Task { _ = await model.authorizeKeyEntry() } }
                    .font(.system(size: 20, weight: .semibold))
                Text("英语声音").font(.system(size: 24, weight: .semibold))
                ForEach(audio.voices) { voice in
                    Button {
                        audio.selectedVoiceID = voice.id
                        audio.speakWord("Hello")
                    } label: {
                        Text("\(voice.name) · \(voice.quality)")
                            .font(.system(size: 20, weight: audio.selectedVoiceID == voice.id ? .bold : .regular))
                    }
                }
                Button("刷新声音") { audio.refreshCapabilities() }.font(.system(size: 20, weight: .semibold))
                Button("图片来源") { showCredits = true }
                    .font(.system(size: 20, weight: .semibold))
                    .accessibilityIdentifier("imageCredits")
            }
            .padding(20)
        }
        .background(Color.white)
        .foregroundStyle(Color.black)
        .sheet(item: $exportFile) { file in
            ShareSheet(url: file.url) {
                try? store.discardExport(at: file.url)
                exportFile = nil
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .data]) { result in
            guard case .success(let url) = result else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                try store.restoreArchive(fromURL: url)
                message = "恢复好了"
            } catch {
                message = "恢复没有成功。如果手机里已经有句子，先清空再恢复。"
            }
        }
        .confirmationDialog("清空本机的句子和录音？星星会留下。", isPresented: $confirmErase, titleVisibility: .visible) {
            Button("清空", role: .destructive) {
                try? store.eraseFamilyData()
                try? store.installSeedPhrasesIfEmpty()
            }
        }
        .sheet(item: $editing) { record in
            RecordEditSheet(record: record)
        }
        .sheet(item: $editingPhrase) { phrase in
            PhraseEditSheet(phrase: phrase)
        }
        .sheet(isPresented: Binding(get: { model.keyUnlocked }, set: { model.keyUnlocked = $0 })) {
            KeyEntrySheet()
        }
        .sheet(isPresented: $showCredits) {
            NavigationStack {
                ImageCreditsPage(catalog: model.vocabulary)
            }
        }
    }

    private var exportLabel: String {
        guard let date = store.snapshot.lastExportAt else { return "上次导出：还没有导出过" }
        return "上次导出：\(date.formatted(date: .abbreviated, time: .shortened))"
    }
}

struct ImageCreditsPage: View {
    var catalog: VocabularyCatalog
    @Environment(\.dismiss) private var dismiss

    private var photos: [VocabularyWord] {
        catalog.categories.flatMap(\.words).filter { $0.credit != nil }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("图片来源")
                    .font(.system(size: 34, weight: .bold))
                Text("插画")
                    .font(.system(size: 28, weight: .bold))
                Text(VocabularyImages.openMojiAttribution)
                    .font(.system(size: 20))
                Link("openmoji.org", destination: VocabularyImages.openMojiProjectURL)
                    .font(.system(size: 20, weight: .semibold))
                Link("CC BY-SA 4.0", destination: VocabularyImages.openMojiLicenseURL)
                    .font(.system(size: 20, weight: .semibold))
                Text("杭州照片")
                    .font(.system(size: 28, weight: .bold))
                Text("这些照片来自维基共享资源。置顶卡片上的小图就是西湖那一张。")
                    .font(.system(size: 20))
                ForEach(photos) { word in
                    if let credit = word.credit {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(word.chinese) · \(word.english)")
                                .font(.system(size: 20, weight: .semibold))
                            Text("作者：\(credit.author)")
                                .font(.system(size: 20))
                            if let url = URL(string: credit.licenseURL) {
                                Link(credit.license, destination: url)
                                    .font(.system(size: 20, weight: .semibold))
                            } else {
                                Text(credit.license).font(.system(size: 20))
                            }
                            Text(credit.sourceURL)
                                .font(.system(size: 20))
                            if let url = URL(string: credit.sourceURL) {
                                Link("打开文件页", destination: url)
                                    .font(.system(size: 20, weight: .semibold))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.white)
        .foregroundStyle(Color.black)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("返回") { dismiss() }
                    .font(.system(size: 20, weight: .semibold))
            }
        }
    }
}

private struct ExportFile: Identifiable {
    var id: String { url.path }
    var url: URL
}

private struct RecordEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: EchoStore
    let record: SpokenRecord
    @State private var english = ""
    @State private var chinese = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("原话").font(.system(size: 20, weight: .semibold))
            Text(record.recognizedText).font(.system(size: 20))
            TextField("英文", text: $english).font(.system(size: 20)).textFieldStyle(.roundedBorder)
            TextField("中文意思", text: $chinese).font(.system(size: 20)).textFieldStyle(.roundedBorder)
            Button("确认并放进句库") {
                try? store.confirmSpokenRecord(id: record.id, english: english, chinese: chinese)
                dismiss()
            }
            .font(.system(size: 20, weight: .semibold))
            Button("只保存修改") {
                var next = record
                next.english = english
                next.chineseMeaning = chinese
                try? store.updateSpokenRecord(next)
                dismiss()
            }
            .font(.system(size: 20, weight: .semibold))
            Button("关闭") { dismiss() }.font(.system(size: 20))
        }
        .padding(24)
        .onAppear {
            english = record.english
            chinese = record.chineseMeaning
        }
    }
}

private struct PhraseEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: EchoStore
    let phrase: LibraryPhrase
    @State private var english = ""
    @State private var chinese = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("中文", text: $chinese).font(.system(size: 20)).textFieldStyle(.roundedBorder)
            TextField("英文", text: $english).font(.system(size: 20)).textFieldStyle(.roundedBorder)
            Button("保存") {
                var next = phrase
                next.english = english
                next.chinese = chinese
                try? store.savePhrase(next)
                dismiss()
            }
            .font(.system(size: 20, weight: .semibold))
            Button("从句库移除") {
                try? store.deletePhrase(id: phrase.id)
                dismiss()
            }
            .font(.system(size: 20, weight: .semibold))
            Button("关闭") { dismiss() }.font(.system(size: 20))
        }
        .padding(24)
        .onAppear {
            english = phrase.english
            chinese = phrase.chinese
        }
    }
}

private struct KeyEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var api: ModelService
    @State private var key = ""
    @State private var note = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("API Key 只存在这台手机的钥匙串里。")
                .font(.system(size: 20))
            SecureField("Key", text: $key).font(.system(size: 20)).textFieldStyle(.roundedBorder)
            Button("保存 Key") {
                do {
                    try api.setAPIKey(key, provider: api.configuration.provider)
                    note = "保存好了"
                    key = ""
                } catch {
                    note = "这把 Key 没法保存"
                }
            }
            .font(.system(size: 20, weight: .semibold))
            Button("删除 Key") {
                try? api.deleteAPIKey(for: api.configuration.provider)
                note = "已经删除"
            }
            .font(.system(size: 20, weight: .semibold))
            if !note.isEmpty { Text(note).font(.system(size: 20)) }
            Button("关闭") { dismiss() }.font(.system(size: 20))
        }
        .padding(24)
    }
}

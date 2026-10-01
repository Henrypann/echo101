import SwiftUI
import EchoCore

struct ParentHome: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var store: EchoStore
    @ScaledMetric(relativeTo: .title) private var titleSize: CGFloat = 28
    @ScaledMetric(relativeTo: .title3) private var bodySize: CGFloat = 20

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HStack {
                        Text("晚间回看")
                            .font(.system(size: max(28, titleSize), weight: .bold))
                            .accessibilityIdentifier("parentTitle")
                        Spacer()
                        Button("返回") { model.leaveParentArea() }
                            .font(.system(size: max(20, bodySize), weight: .semibold))
                            .frame(minHeight: 64)
                            .accessibilityIdentifier("leaveParent")
                    }
                    if !model.parentStatus.isEmpty {
                        Text(model.parentStatus)
                            .font(.system(size: max(20, bodySize)))
                            .accessibilityIdentifier("parentStatus")
                    }
                    reviewSection
                    NavigationLink("句库（\(store.snapshot.library.count)）") { LibraryList() }
                        .font(.system(size: max(20, bodySize), weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                        .accessibilityIdentifier("openLibrary")
                    setupSection
                    ParentExportSection()
                    ParentSettingsSection()
                }
                .padding(24)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.white)
            .foregroundStyle(Color.black)
            .navigationBarHidden(true)
        }
    }

    private var reviewSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("今天和更早的句子")
                .font(.system(size: max(24, titleSize), weight: .semibold))
            if store.snapshot.records.isEmpty {
                Text("还没有记下的话。")
                    .font(.system(size: max(20, bodySize)))
            }
            ForEach(store.snapshot.records) { record in
                NavigationLink {
                    RecordReview(recordID: record.id)
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(record.recognizedText)
                            .font(.system(size: max(20, bodySize), weight: .semibold))
                            .foregroundStyle(Color.black)
                        Text(record.english.isEmpty ? "还没有英文" : record.english)
                            .font(.system(size: max(20, bodySize), weight: .bold))
                            .foregroundStyle(Color.black)
                        Text(record.chinese.isEmpty ? "还没有中文意思" : record.chinese)
                            .font(.system(size: max(20, bodySize)))
                            .foregroundStyle(EchoStyle.quiet)
                        if record.needsConfirmation {
                            Text("待确认")
                                .font(.system(size: max(20, bodySize), weight: .semibold))
                                .foregroundStyle(EchoStyle.quiet)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                }
                .accessibilityIdentifier(record.needsConfirmation ? "pendingRow" : "recordRow")
            }
        }
    }

    private var setupSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("需要爸妈处理")
                .font(.system(size: max(24, titleSize), weight: .semibold))
            if model.setupIssues.isEmpty {
                Text("没有待处理的权限或语音包。")
                    .font(.system(size: max(20, bodySize)))
            } else {
                ForEach(model.setupIssues, id: \.self) { issue in
                    Text(issue)
                        .font(.system(size: max(20, bodySize)))
                        .accessibilityIdentifier("setupIssue")
                }
            }
            Button("重新检查") { model.refreshSetupIssues() }
                .buttonStyle(GrandparentButtonStyle(filled: false))
                .accessibilityIdentifier("refreshSetup")
        }
    }
}

struct LibraryList: View {
    @EnvironmentObject private var store: EchoStore
    @ScaledMetric(relativeTo: .title3) private var bodySize: CGFloat = 20

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                NavigationLink("加一句") { LibraryEditor(phraseID: nil) }
                    .font(.system(size: max(20, bodySize), weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                    .accessibilityIdentifier("addPhrase")
                ForEach(store.snapshot.library) { phrase in
                    NavigationLink {
                        LibraryEditor(phraseID: phrase.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(phrase.english)
                                .font(.system(size: max(20, bodySize), weight: .bold))
                                .foregroundStyle(Color.black)
                                .accessibilityIdentifier("libraryEnglish")
                            Text(phrase.chinese)
                                .font(.system(size: max(20, bodySize)))
                                .foregroundStyle(EchoStyle.quiet)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(24)
        }
        .background(Color.white)
        .navigationTitle("句库")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct RecordReview: View {
    let recordID: UUID
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var store: EchoStore
    @EnvironmentObject private var audio: AudioController
    @Environment(\.dismiss) private var dismiss
    @State private var english = ""
    @State private var chinese = ""
    @State private var scene = "日常"
    @ScaledMetric(relativeTo: .title3) private var bodySize: CGFloat = 20

    private var record: SpeechRecord? { store.snapshot.records.first { $0.id == recordID } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let record {
                    Text(record.recognizedText)
                        .font(.system(size: max(24, bodySize), weight: .semibold))
                        .accessibilityIdentifier("recognizedText")
                    labeledField("英文", text: $english, identifier: "englishText")
                    labeledField("中文意思", text: $chinese, identifier: "chineseText")
                    labeledField("场景", text: $scene, identifier: "sceneText")
                    clipButtons(record)
                    if record.needsConfirmation {
                        Button("确认并放入句库") { confirm() }
                            .buttonStyle(GrandparentButtonStyle())
                            .accessibilityIdentifier("confirmPending")
                    }
                    Button("删除这条") { remove() }
                        .buttonStyle(GrandparentButtonStyle(filled: false))
                        .accessibilityIdentifier("deleteRecord")
                } else {
                    Text("这条已经不在了。")
                        .font(.system(size: max(20, bodySize)))
                }
            }
            .padding(24)
        }
        .background(Color.white)
        .foregroundStyle(Color.black)
        .navigationTitle("这句话")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let record {
                english = record.english
                chinese = record.chinese
                scene = record.scene
            }
        }
    }

    private func clipButtons(_ record: SpeechRecord) -> some View {
        let clips = store.snapshot.clips.filter { $0.recordID == record.id }
        return VStack(spacing: 12) {
            ForEach(clips) { clip in
                Button(clip.role == "child" ? "播放孩子跟读" : "播放老人原话") {
                    if let url = try? store.clipURL(for: clip) { audio.playRecording(url: url) }
                }
                .buttonStyle(GrandparentButtonStyle(filled: false))
                .accessibilityIdentifier(clip.role == "child" ? "playChild" : "playGrandparent")
            }
        }
    }

    private func confirm() {
        guard let store = model.store, let record else { return }
        let englishValue = english.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? record.english : english
        let chineseValue = chinese.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? record.chinese : chinese
        let sceneValue = scene.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? record.scene : scene
        do {
            _ = try store.confirmRecord(id: recordID, english: englishValue, chinese: chineseValue, scene: sceneValue.isEmpty ? "日常" : sceneValue)
            model.parentStatus = "已放入句库。下次会优先用这句，不会再问模型。"
            dismiss()
        } catch {
            model.parentStatus = "没有放进句库。请检查英文和中文都写了。"
        }
    }

    private func remove() {
        try? model.store?.deleteRecord(id: recordID)
        dismiss()
    }

    private func labeledField(_ title: String, text: Binding<String>, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: max(20, bodySize), weight: .semibold))
            TextField(title, text: text, axis: .vertical)
                .font(.system(size: max(20, bodySize)))
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier(identifier)
        }
    }
}

struct LibraryEditor: View {
    let phraseID: UUID?
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var english = ""
    @State private var chinese = ""
    @State private var scene = "日常"
    @State private var keywords = ""
    @ScaledMetric(relativeTo: .title3) private var bodySize: CGFloat = 20

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                field("英文", text: $english, identifier: "libraryEnglishField")
                field("中文意思", text: $chinese, identifier: "libraryChineseField")
                field("场景", text: $scene, identifier: "librarySceneField")
                field("别的说法，用逗号分开", text: $keywords, identifier: "libraryKeywordField")
                Button(phraseID == nil ? "放入句库" : "保存修改") { save() }
                    .buttonStyle(GrandparentButtonStyle())
                    .accessibilityIdentifier("savePhrase")
                if phraseID != nil {
                    Button("从句库删除") { remove() }
                        .buttonStyle(GrandparentButtonStyle(filled: false))
                        .accessibilityIdentifier("deletePhrase")
                }
            }
            .padding(24)
        }
        .background(Color.white)
        .foregroundStyle(Color.black)
        .navigationTitle(phraseID == nil ? "加一句" : "改一句")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
    }

    private func load() {
        guard let phraseID, let phrase = model.store?.snapshot.library.first(where: { $0.id == phraseID }) else { return }
        english = phrase.english
        chinese = phrase.chinese
        scene = phrase.scene
        keywords = phrase.keywords.joined(separator: "，")
    }

    private func save() {
        guard let store = model.store else { return }
        let keys = keywords.split { "，,".contains($0) }.map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        do {
            if let phraseID, var phrase = store.snapshot.library.first(where: { $0.id == phraseID }) {
                phrase.english = english
                phrase.chinese = chinese
                phrase.scene = scene.isEmpty ? "日常" : scene
                phrase.keywords = keys
                phrase.source = "parent"
                try store.updateLibraryPhrase(phrase)
            } else {
                try store.addLibraryPhrase(LibraryPhrase(english: english, chinese: chinese, scene: scene.isEmpty ? "日常" : scene, keywords: keys, source: "parent"))
            }
            dismiss()
        } catch {
            model.parentStatus = "这句没有保存。英文和中文都要写。"
        }
    }

    private func remove() {
        if let phraseID { try? model.store?.deleteLibraryPhrase(id: phraseID) }
        dismiss()
    }

    private func field(_ title: String, text: Binding<String>, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: max(20, bodySize), weight: .semibold))
            TextField(title, text: text, axis: .vertical)
                .font(.system(size: max(20, bodySize)))
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier(identifier)
        }
    }
}

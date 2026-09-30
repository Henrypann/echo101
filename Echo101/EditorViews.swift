import SwiftUI
import EchoCore
import EchoAPI

struct ParentTextInput: View {
    let title: String
    var placeholder = ""
    @Binding var text: String
    var lines: ClosedRange<Int> = 1...4
    var identifier = ""
    var verbatim = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.caption.weight(.semibold))
                .foregroundStyle(EchoStyle.textSecondary)
            TextField(placeholder, text: $text, axis: .vertical)
                .lineLimit(lines).font(.body).foregroundStyle(EchoStyle.text)
                .textInputAutocapitalization(verbatim ? .never : .sentences)
                .autocorrectionDisabled(verbatim).focused($focused)
                .padding(16).frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                .background(EchoStyle.surface, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(focused ? EchoStyle.focus : EchoStyle.controlBorder, lineWidth: focused ? 3 : 1.5))
                .accessibilityLabel(title).accessibilityIdentifier(identifier)
        }
    }
}

private struct EditorHeading: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(.title, design: .rounded, weight: .bold))
                .foregroundStyle(EchoStyle.text).accessibilityAddTraits(.isHeader)
            Text(subtitle).font(.body).foregroundStyle(EchoStyle.textSecondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct EditorNotice: View {
    let title: String
    let message: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: "info.circle").font(.headline)
            Text(message).font(.body)
        }.foregroundStyle(EchoStyle.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading).echoCard(color: EchoStyle.surfaceAlt)
    }
}

struct MomentEditor: View {
    var existing: Moment?
    var initialCapture = false
    @EnvironmentObject var store: EchoStore
    @EnvironmentObject var audio: AudioController
    @Environment(\.dismiss) var dismiss
    @State private var scene = "Everyday"
    @State private var note = ""
    @State private var showCapture = false
    @State private var locale = "zh-CN"
    @State private var error: String?

    private var canSave: Bool {
        !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !audio.isRecording && audio.phase != .transcribing
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                EditorHeading(title: existing == nil ? "Add a Moment" : "Edit Moment",
                              subtitle: "A little part of your day can become something to say.")
                VStack(alignment: .leading, spacing: 8) {
                    ParentTextInput(title: "What happened?", placeholder: "Chinese or English is welcome.", text: $note,
                                    lines: 4...10, identifier: "momentNote")
                    Text("For example: 今天指着红色玩具车说车车。 Keep names, addresses and private details out.")
                        .font(.caption).foregroundStyle(EchoStyle.textSecondary)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("CHOOSE A SCENE").font(.caption.weight(.semibold)).foregroundStyle(EchoStyle.textSecondary)
                    Picker("Choose a scene", selection: $scene) {
                        ForEach(AppModel.scenes, id: \.self) { Text($0).tag($0) }
                    }.pickerStyle(.menu).tint(EchoStyle.onAccent)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(EchoStyle.accent, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(EchoStyle.controlBorder, lineWidth: 1.5))
                }
                VStack(alignment: .leading, spacing: 16) {
                    Toggle(isOn: $showCapture) { Label("Add a voice note", systemImage: "mic") }
                        .tint(EchoStyle.action)
                        .onChange(of: showCapture) { _, on in if !on { audio.discardTemporaryRecording() } }
                    Text("Optional · recording starts only when you tap Record.")
                        .font(.caption).foregroundStyle(EchoStyle.textSecondary)
                    if showCapture {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Spoken language").font(.headline)
                            Picker("Spoken language", selection: $locale) {
                                Text("Chinese").tag("zh-CN"); Text("English").tag("en-US")
                            }.pickerStyle(.segmented).disabled(audio.isRecording)
                        }
                        RecordingPanel(mode: .context, locale: locale)
                        if !audio.transcript.isEmpty {
                            Text(audio.transcript).font(.body)
                            Button("Use This Transcript") {
                                note = note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? audio.transcript : note + "\n" + audio.transcript
                            }.buttonStyle(EchoActionStyle(primary: false))
                            Text("Please check the words. Echo does not know who said them.")
                                .font(.body).foregroundStyle(EchoStyle.textSecondary)
                        }
                    }
                }.foregroundStyle(EchoStyle.text).echoCard()
                EditorNotice(title: "Saved on this iPhone", message: "Saving a moment does not send it to a model service. Temporary voice notes are removed when you finish or cancel.")
                if let error { Label(error, systemImage: "exclamationmark.circle").foregroundStyle(EchoStyle.danger).font(.body) }
            }.padding(24).frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
        }.scrollDismissesKeyboard(.interactively).background(EchoStyle.background)
            .navigationTitle(existing == nil ? "Add a Moment" : "Edit Moment").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { audio.discardTemporaryRecording(); dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                Button(existing == nil ? "Save Moment" : "Save Changes", action: save)
                    .buttonStyle(EchoActionStyle()).disabled(!canSave).accessibilityIdentifier("saveMoment")
                    .padding(.horizontal, 24).padding(.vertical, 12).frame(maxWidth: 640)
                    .frame(maxWidth: .infinity).background(EchoStyle.background)
            }
            .onAppear { if let existing { scene = existing.scene; note = existing.note }; showCapture = initialCapture }
            .onDisappear { audio.discardTemporaryRecording() }
            .alert("Could not save", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
    }

    private func save() {
        do {
            if var existing { existing.scene = scene; existing.note = note; try store.updateMoment(existing) }
            else { _ = try store.createMoment(scene: scene, note: note) }
            audio.discardTemporaryRecording(); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct ExpressionEditor: View {
    let momentID: UUID
    var existing: Expression?
    @EnvironmentObject var store: EchoStore
    @Environment(\.dismiss) var dismiss
    @State private var text = ""
    @State private var meaning = ""
    @State private var spokenText = ""
    @State private var parentTip = ""
    @State private var chunks = ""
    @State private var error: String?
    private var isReview: Bool { existing?.isConfirmed != true }
    private var canSave: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                EditorHeading(title: isReview ? "Check it together" : "Edit an Expression",
                              subtitle: "Only confirmed expressions appear in child mode.")
                if isReview {
                    Label("Draft · Adult review", systemImage: "pencil.and.outline")
                        .font(.caption.weight(.semibold)).foregroundStyle(EchoStyle.accentText)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(EchoStyle.accentSoft, in: Capsule())
                        .accessibilityLabel("Draft expression; not yet available in child mode")
                }
                ParentTextInput(title: "English", placeholder: "English word or short sentence", text: $text, identifier: "englishText")
                ParentTextInput(title: "Meaning · Optional", placeholder: "Chinese meaning", text: $meaning, identifier: "chineseMeaning")
                VStack(alignment: .leading, spacing: 8) {
                    ParentTextInput(title: "Say it in parts · Optional", placeholder: "One phrase per line", text: $chunks,
                                    lines: 2...6, identifier: "expressionParts")
                    Text("Use meaningful phrases, such as “I can say” and “my A, B, C”. A single word does not need splitting.")
                        .font(.caption).foregroundStyle(EchoStyle.textSecondary)
                }
                VStack(alignment: .leading, spacing: 8) {
                    ParentTextInput(title: "Read-aloud text · Optional", placeholder: "Leave blank to read the English text", text: $spokenText)
                    Text("For ABC, you may use “A, B, C” here. Echo reads; it does not sing a melody or teach letter sounds automatically.")
                        .font(.caption).foregroundStyle(EchoStyle.textSecondary)
                }
                ParentTextInput(title: "Parent note · Optional", placeholder: "A gentle idea for using this in real life", text: $parentTip,
                                lines: 2...6, identifier: "parentTip")
                EditorNotice(title: "Does it fit your moment?", message: "Check the meaning and keep words simple. Edit anything that feels wrong. Confirmation records your review, not what your child has mastered.")
                if let error { Label(error, systemImage: "exclamationmark.circle").font(.body).foregroundStyle(EchoStyle.danger) }
            }.padding(24).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }.scrollDismissesKeyboard(.interactively).background(EchoStyle.background)
            .navigationTitle(isReview ? "Review an Expression" : "Expression").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 12) {
                    Group {
                        if isReview {
                            Button { save(confirmed: true) } label: { Label("Confirm Expression", systemImage: "checkmark") }
                                .buttonStyle(EchoCoralStyle())
                        } else {
                            Button("Save Changes") { save(confirmed: true) }.buttonStyle(EchoActionStyle())
                        }
                    }.disabled(!canSave).accessibilityIdentifier("saveExpression")
                    if isReview {
                        Button("Keep as Draft") { save(confirmed: false) }
                            .buttonStyle(EchoActionStyle(primary: false)).disabled(!canSave).accessibilityIdentifier("keepExpressionDraft")
                    }
                }.padding(.horizontal, 24).padding(.vertical, 12).frame(maxWidth: 640)
                    .frame(maxWidth: .infinity).background(EchoStyle.background)
            }
            .onAppear {
                if let existing {
                    text = existing.text; meaning = existing.meaning; spokenText = existing.spokenText
                    parentTip = existing.parentTip ?? ""; chunks = existing.segments.joined(separator: "\n")
                }
            }
            .alert("Could not save", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
    }

    private func save(confirmed: Bool) {
        var value = existing ?? Expression(momentID: momentID, text: text)
        value.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        value.meaning = meaning.trimmingCharacters(in: .whitespacesAndNewlines)
        value.spokenText = spokenText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTip = parentTip.trimmingCharacters(in: .whitespacesAndNewlines)
        value.parentTip = trimmedTip.isEmpty ? nil : trimmedTip
        value.segments = chunks.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        value.isConfirmed = confirmed || existing?.isConfirmed == true
        do { try store.saveExpression(value); dismiss() } catch { self.error = error.localizedDescription }
    }
}

struct GenerateView: View {
    let moment: Moment
    @EnvironmentObject var api: ModelService
    @EnvironmentObject var store: EchoStore
    @Environment(\.dismiss) var dismiss
    @State private var preview = ""
    @State private var privacyReviewed = false
    @State private var consent = false
    @State private var error: String?
    @State private var requestTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                EditorHeading(title: "English Ideas", subtitle: "Review exactly what you choose to share.")
                ParentTextInput(title: "Only this text will be sent", placeholder: "Describe the scene without personal details", text: $preview,
                                lines: 5...10, identifier: "generationPreview").disabled(api.isBusy)
                EditorNotice(title: "Your choice, every time", message: "Remove names, addresses and anything private. No audio, recordings or other moments are attached. The selected provider's data policy applies.")
                VStack(alignment: .leading, spacing: 16) {
                    LabeledContent("Provider", value: api.configuration.provider.title)
                    LabeledContent("Network", value: api.wifiAvailable ? "Wi-Fi available" : "Wi-Fi required")
                    LabeledContent("Today's requests", value: "\(api.requestsToday) / 20")
                    Toggle("I removed names and private details", isOn: $privacyReviewed)
                        .disabled(api.isBusy).tint(EchoStyle.action).accessibilityIdentifier("generationPrivacyReview")
                    Toggle("Send this preview to generate ideas", isOn: $consent).disabled(api.isBusy).tint(EchoStyle.action)
                    if !api.configuration.enabled { Text("Enable a model and add its key in Settings first.").foregroundStyle(EchoStyle.textSecondary) }
                }.font(.body).foregroundStyle(EchoStyle.text).echoCard()
                VStack(alignment: .leading, spacing: 16) {
                    if api.isBusy {
                        ProgressView("Finding a few simple expressions…").tint(EchoStyle.action)
                        Button("Cancel Request", role: .cancel) { requestTask?.cancel(); api.cancel() }
                            .buttonStyle(EchoActionStyle(primary: false))
                    } else {
                        Button("Generate Up to 3 Ideas", action: generate).buttonStyle(EchoActionStyle())
                            .disabled(!privacyReviewed || !consent || !api.configuration.enabled || !api.wifiAvailable || preview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    Text("Ideas are saved as drafts. Open each draft to edit and confirm before it can be played. Nothing is sent automatically when Wi-Fi returns.")
                        .font(.body).foregroundStyle(EchoStyle.textSecondary)
                }
            }.padding(24).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }.scrollDismissesKeyboard(.interactively).background(EchoStyle.background)
            .navigationTitle("English Ideas").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { requestTask?.cancel(); api.cancel(); dismiss() } } }
            .onAppear { preview = moment.note }
            .onChange(of: preview) { _, _ in privacyReviewed = false; consent = false }
            .onDisappear { requestTask?.cancel(); api.cancel() }
            .alert("Ideas were not generated", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
    }

    private func generate() {
        guard privacyReviewed, consent, api.configuration.enabled, api.wifiAvailable, !api.isBusy,
              !preview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let submitted = preview
        requestTask = Task { @MainActor in
            do {
                let candidates = try await api.generate(sceneText: submitted)
                try Task.checkCancellation()
                let drafts = candidates.map { item in
                    Expression(momentID: moment.id, text: item.text, meaning: item.meaning, segments: item.segments, isConfirmed: false,
                               source: "\(api.configuration.provider.rawValue) suggestion", parentTip: item.tip)
                }
                try store.saveExpressions(drafts)
                dismiss()
            } catch is CancellationError { }
            catch ModelServiceError.cancelled { }
            catch { self.error = error.localizedDescription }
        }
    }
}

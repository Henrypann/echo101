import SwiftUI
import AVFoundation
import UIKit
import EchoCore
import EchoAPI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var store: EchoStore
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var audio: AudioController
    @EnvironmentObject var api: ModelService
    @State private var key = ""
    @State private var status = ""
    @State private var includeAudio = false
    @State private var exportURL: URL?
    @State private var importing = false
    @State private var importURL: URL?
    @State private var confirmingImport = false
    @State private var addingSamples = false
    @State private var serviceTask: Task<Void, Never>?
    @FocusState private var keyFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                EchoBrandHeader(parent: true)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your family. Your choices.")
                        .font(.system(.title, design: .rounded, weight: .bold)).accessibilityAddTraits(.isHeader)
                    Text("Private by default. Clear when sharing.").font(.body).foregroundStyle(EchoStyle.textSecondary)
                }
                microphoneCard
                cloudCard
                reminderCard
                recordingsSection
                exportCard
                deleteNotice
                samplesCard
                privacyCard
            }.foregroundStyle(EchoStyle.text).padding(24)
                .frame(maxWidth: 640).frame(maxWidth: .infinity)
        }.scrollDismissesKeyboard(.interactively).background(EchoStyle.background)
            .toolbar(.hidden, for: .navigationBar)
            .onAppear { audio.refreshCapabilities() }
            .onDisappear { key = ""; serviceTask?.cancel(); api.cancel(); audio.stopPlayback() }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls): importURL = urls.first; confirmingImport = importURL != nil
                case .failure: model.errorMessage = "The file could not be selected. Your collection was not changed."
                }
            }
            .alert("Restore this export?", isPresented: $confirmingImport) {
                Button("Restore") {
                    guard let importURL else { return }
                    let access = importURL.startAccessingSecurityScopedResource()
                    defer { if access { importURL.stopAccessingSecurityScopedResource() }; self.importURL = nil }
                    model.perform { try store.restoreArchive(fromURL: importURL) }
                }
                Button("Cancel", role: .cancel) { importURL = nil }
            } message: { Text("Echo will validate the archive before restoring it into this empty collection. Model keys are not restored.") }
            .alert("Add sample expressions?", isPresented: $addingSamples) {
                Button("Add Samples") { model.perform { try model.addSamples() } }
                Button("Cancel", role: .cancel) { }
            } message: { Text("This adds a separate sample moment with 20 expressions. It will not change your existing moments.") }
    }

    private var microphoneCard: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 16) {
                Text("Echo never listens in the background. Microphone access is requested only when you choose Record.").font(.body)
                LabeledContent("Microphone access", value: microphoneStatus)
                Link("Open iPhone Settings", destination: URL(string: UIApplication.openSettingsURLString)!)
                    .font(.headline).frame(minHeight: 44).tint(EchoStyle.action)
                Divider().overlay(EchoStyle.border)
                Text("Voice · On this iPhone").font(.headline)
                Picker("English voice", selection: $audio.selectedVoiceID) {
                    Text("System English voice").tag("")
                    ForEach(audio.voices) { Text("\($0.name) · \($0.quality)").tag($0.id) }
                }.pickerStyle(.menu).frame(minHeight: 56).accessibilityIdentifier("voicePicker")
                Button("Preview Voice") { audio.speak(text: "Water, please. I can say my A, B, C.") }
                    .buttonStyle(EchoActionStyle(primary: false))
                if audio.phase == .speaking || audio.phase == .playingRecord {
                    Button("Stop Playback") { audio.stopPlayback() }.buttonStyle(EchoActionStyle(primary: false))
                }
                Text("To add voices: iPhone Settings → Accessibility → Spoken Content → Voices → English. Download on Wi-Fi, then return here and refresh. Available names vary by iOS version.")
                    .font(.body).foregroundStyle(EchoStyle.textSecondary)
                Button("Refresh Voices & Capabilities") { audio.refreshCapabilities() }
                    .buttonStyle(EchoActionStyle(primary: false))
                LabeledContent("Chinese device recognition", value: audio.onDeviceChinese ? "Supported" : "Unavailable")
                LabeledContent("English device recognition", value: audio.onDeviceEnglish ? "Supported" : "Unavailable")
                Text("Capability is not a quality or offline test. If recognition cannot run on-device, use playback and type the note. No cloud transcription fallback.")
                    .font(.body).foregroundStyle(EchoStyle.textSecondary)
                AudioNotice()
            }.padding(.top, 16)
        } label: {
            SettingsCardLabel(title: "Microphone", subtitle: "Only after you tap Record.", icon: "mic")
        }.tint(EchoStyle.action).echoCard().accessibilityIdentifier("microphoneSettings")
    }

    private var microphoneStatus: String {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: "Allowed"
        case .denied: "Off in iPhone Settings"
        case .undetermined: "Not requested"
        @unknown default: "Check iPhone Settings"
        }
    }

    private var cloudCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCardLabel(title: "Cloud ideas", subtitle: api.configuration.enabled ? "On · review text before sending." : "Off · review text before sending.", icon: "checkmark.shield")
            Toggle("Enable cloud generation", isOn: $api.configuration.enabled).tint(EchoStyle.action)
                .accessibilityIdentifier("cloudGenerationToggle")
                .onChange(of: api.configuration.enabled) { _, enabled in
                    if !enabled { serviceTask?.cancel(); api.cancel() }
                }
            Text("Optional · Wi-Fi only. Turning this off does not affect local playback. No moments or recordings are sent automatically.")
                .font(.body).foregroundStyle(EchoStyle.textSecondary)
            DisclosureGroup("Model & API key") { modelConfiguration.padding(.top, 16) }.tint(EchoStyle.action)
        }.echoCard()
    }

    private var modelConfiguration: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Provider", selection: $api.configuration.provider) {
                ForEach(ModelProvider.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.menu).frame(minHeight: 56).disabled(api.isBusy)
                .onChange(of: api.configuration.provider) { _, provider in
                    api.configuration.modelID = provider.defaultModelID; key = ""; status = ""
                }
            ParentTextInput(title: "Model ID", text: $api.configuration.modelID, verbatim: true).disabled(api.isBusy)
            VStack(alignment: .leading, spacing: 8) {
                Text("DEDICATED API KEY").font(.caption.weight(.semibold)).foregroundStyle(EchoStyle.textSecondary)
                SecureField("Enter a provider key", text: $key).font(.body)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive().focused($keyFocused)
                    .padding(16).frame(maxWidth: .infinity, minHeight: 56)
                    .background(EchoStyle.surfaceAlt, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(keyFocused ? EchoStyle.focus : EchoStyle.controlBorder, lineWidth: keyFocused ? 3 : 1.5))
                    .accessibilityLabel("Dedicated API key")
            }
            Button("Save Key") {
                model.perform { try api.setAPIKey(key, provider: api.configuration.provider); key = ""; status = "Key saved on this iPhone." }
            }.buttonStyle(EchoActionStyle(primary: false)).disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || api.isBusy)
            Button("Remove Key", role: .destructive) {
                model.perform { try api.deleteAPIKey(for: api.configuration.provider); key = ""; status = "Key removed from this iPhone. Revoke it at the provider if needed." }
            }.foregroundStyle(EchoStyle.danger).font(.headline).frame(minHeight: 44).disabled(api.isBusy)
            Text(api.hasKey(for: api.configuration.provider) ? "A key is saved for this provider." : "No key saved for this provider.")
                .font(.body).foregroundStyle(EchoStyle.textSecondary)
            LabeledContent("Connection", value: api.wifiAvailable ? "Wi-Fi available" : "Wi-Fi required")
            LabeledContent("Requests today", value: "\(api.requestsToday) / 20")
            if !api.lastUsage.isEmpty { Text(api.lastUsage).font(.body) }
            Button(api.isBusy ? "Testing…" : "Test with a Sample") {
                serviceTask = Task { @MainActor in
                    do { status = try await api.testConnection() }
                    catch { status = error.localizedDescription }
                }
            }.buttonStyle(EchoActionStyle(primary: false)).disabled(api.isBusy || !api.wifiAvailable || !api.configuration.enabled)
            if api.isBusy {
                Button("Cancel Test") { serviceTask?.cancel(); api.cancel() }.buttonStyle(EchoActionStyle(primary: false))
            }
            if !status.isEmpty { Text(status).font(.body).foregroundStyle(EchoStyle.textSecondary) }
            Text("Tests send a harmless sample, not your moments. Keys stay in device Keychain. Set a spending limit at your provider; this app's counter is only a local limit.")
                .font(.body).foregroundStyle(EchoStyle.textSecondary)
        }
    }

    private var reminderCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCardLabel(title: "Session reminder", subtitle: "Adjustable, not a target.", icon: "clock")
            Picker("Remind us after", selection: $model.reminderMinutes) {
                Text("Off").tag(0)
                Text("3 minutes").tag(3)
                Text("5 minutes").tag(5)
                Text("10 minutes").tag(10)
            }.pickerStyle(.menu).frame(minHeight: 56).accessibilityIdentifier("sessionReminderPicker")
            Text("A gentle in-app reminder to return to real-life play. This is your family's preference, not a medical or health standard.")
                .font(.body).foregroundStyle(EchoStyle.textSecondary)
        }.echoCard()
    }

    private var recordingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink { ManageRecordingsView() } label: { Label("Manage Recordings", systemImage: "waveform") }
                .buttonStyle(EchoActionStyle(primary: false)).accessibilityIdentifier("manageRecordings")
            Text("\(store.snapshot.clips.count) saved recordings · kept only when you choose Save Recording.")
                .font(.body).foregroundStyle(EchoStyle.textSecondary)
        }
    }

    private var exportCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCardLabel(title: "Export Family Data", subtitle: "Keep a private copy somewhere you trust.", icon: "square.and.arrow.up")
            LabeledContent("Moments", value: "\(store.snapshot.moments.count)")
            LabeledContent("Expressions", value: "\(store.snapshot.expressions.count)")
            Toggle("Include saved recordings in export", isOn: $includeAudio).tint(EchoStyle.action)
            Button("Prepare Export") { model.perform { exportURL = try store.exportArchive(includeAudio: includeAudio) } }
                .buttonStyle(EchoActionStyle(primary: false))
            if let exportURL {
                ShareLink(item: exportURL) { Label("Save or Share Export", systemImage: "square.and.arrow.up") }
                    .buttonStyle(EchoActionStyle(primary: false))
            }
            Text("Exports contain private family content. Choose a trusted destination. Keys and temporary capture audio are never included.")
                .font(.body).foregroundStyle(EchoStyle.textSecondary)
            Divider().overlay(EchoStyle.border)
            Button("Restore into Empty Collection") { importing = true }.disabled(!store.snapshot.isEmpty)
                .buttonStyle(EchoActionStyle(primary: false))
            Text(store.snapshot.isEmpty ? "A validated Echo export can be restored here." : "Restore is available only when the collection is empty. Existing content is never replaced.")
                .font(.body).foregroundStyle(EchoStyle.textSecondary)
        }.echoCard()
    }

    private var deleteNotice: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Delete with care", systemImage: "exclamationmark.circle").font(.headline)
            Text("Removing a moment in Moments also removes its linked expressions, recordings and usage records. Removing an expression removes its recordings and usage records. Manage Recordings lets you delete only an individual recording.")
                .font(.body)
            Text("Deletion cannot be undone. Export anything you want to keep first.").font(.body)
        }.foregroundStyle(EchoStyle.danger).frame(maxWidth: .infinity, alignment: .leading)
            .echoCard(color: EchoStyle.dangerSurface)
    }

    private var samplesCard: some View {
        DisclosureGroup("Try a few words") {
            VStack(alignment: .leading, spacing: 16) {
                Text("Optional listening examples, not a course or a record of what your child has learned.").font(.body).foregroundStyle(EchoStyle.textSecondary)
                Button("Add 20 Sample Expressions") { addingSamples = true }.buttonStyle(EchoActionStyle(primary: false))
            }.padding(.top, 16)
        }.font(.headline).tint(EchoStyle.action).echoCard()
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Private by default", systemImage: "lock").font(.headline)
            Text("No account, ads, tracking, background listening or automatic cloud sync. Family captures are temporary. Practice recordings stay only when you save them. App data is excluded from automatic cloud backup; keep your own export before removing the app.")
            Text("A generated suggestion is not a fact about your child. No pronunciation scores, mastery claims or developmental assessment.")
        }.font(.body).foregroundStyle(EchoStyle.textSecondary).echoCard(color: EchoStyle.surfaceAlt)
    }
}

private struct SettingsCardLabel: View {
    let title: String
    let subtitle: String
    let icon: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.title3).frame(width: 24).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(.headline, design: .rounded))
                Text(subtitle).font(.body).foregroundStyle(EchoStyle.textSecondary)
            }
        }.foregroundStyle(EchoStyle.text).frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ManageRecordingsView: View {
    @EnvironmentObject var store: EchoStore
    @EnvironmentObject var audio: AudioController
    @State private var pendingDeletion: VoiceClip?
    @State private var playingClipID: UUID?
    @State private var resultMessage: String?
    @State private var deletionFailed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Saved by your family").font(.system(.title, design: .rounded, weight: .bold)).accessibilityAddTraits(.isHeader)
                Text("Listen again or delete a recording. Deleting audio keeps its expression.").font(.body).foregroundStyle(EchoStyle.textSecondary)
                AudioNotice()
                if let resultMessage {
                    Label(resultMessage, systemImage: deletionFailed ? "exclamationmark.circle" : "checkmark.circle")
                        .font(.body).foregroundStyle(deletionFailed ? EchoStyle.danger : EchoStyle.success)
                }
                if store.snapshot.clips.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("No saved recordings yet", systemImage: "waveform").font(.headline)
                        Text("Record together from a confirmed expression, then choose Save Recording to keep it.").font(.body).foregroundStyle(EchoStyle.textSecondary)
                    }.echoCard()
                } else {
                    ForEach(store.snapshot.clips) { clip in recordingCard(clip) }
                }
            }.foregroundStyle(EchoStyle.text).padding(24).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }.background(EchoStyle.background).navigationTitle("Manage Recordings").navigationBarTitleDisplayMode(.inline)
            .onDisappear { audio.stopPlayback() }
            .onChange(of: audio.phase) { _, phase in if phase != .playingRecord { playingClipID = nil } }
            .alert("Delete this recording?", isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }), presenting: pendingDeletion) { clip in
                Button("Delete Recording", role: .destructive) {
                    audio.stopPlayback()
                    do {
                        try store.deleteClip(id: clip.id); deletionFailed = false; resultMessage = "Recording deleted. Its expression is still saved."
                        UIAccessibility.post(notification: .announcement, argument: "Recording deleted.")
                    } catch { deletionFailed = true; resultMessage = error.localizedDescription }
                    pendingDeletion = nil
                }
                Button("Cancel", role: .cancel) { pendingDeletion = nil }
            } message: { _ in Text("Only this recording will be removed. Its expression and moment will stay. Deletion cannot be undone.") }
    }

    private func recordingCard(_ clip: VoiceClip) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(store.snapshot.expressions.first(where: { $0.id == clip.expressionID })?.text ?? "Saved expression")
                .font(.system(.headline, design: .rounded))
            Text(clip.createdAt, format: .dateTime.month().day().year().hour().minute())
                .font(.caption).foregroundStyle(EchoStyle.textSecondary)
            Button {
                if playingClipID == clip.id && audio.phase == .playingRecord { audio.stopPlayback(); playingClipID = nil }
                else {
                    do { audio.playRecording(url: try store.clipURL(for: clip)); playingClipID = audio.phase == .playingRecord ? clip.id : nil }
                    catch { audio.errorMessage = error.localizedDescription }
                }
            } label: {
                Label(playingClipID == clip.id && audio.phase == .playingRecord ? "Stop Playback" : "Play Recording",
                      systemImage: playingClipID == clip.id && audio.phase == .playingRecord ? "stop.fill" : "play.fill")
            }.buttonStyle(EchoActionStyle(primary: false)).accessibilityIdentifier("playRecording-\(clip.id.uuidString)")
            Button { pendingDeletion = clip } label: { Label("Delete Recording", systemImage: "trash") }
                .font(.headline).foregroundStyle(EchoStyle.danger).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .accessibilityIdentifier("deleteRecording-\(clip.id.uuidString)")
        }.frame(maxWidth: .infinity, alignment: .leading).echoCard()
    }
}

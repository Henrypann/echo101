import SwiftUI
import EchoCore

enum EchoStyle {
    static let background = Color("EchoBackground")
    static let surface = Color("EchoSurface")
    static let surfaceAlt = Color("EchoSurfaceAlt")
    static let text = Color("EchoText")
    static let textSecondary = Color("EchoTextSecondary")
    static let border = Color("EchoBorder")
    static let controlBorder = Color("EchoControlBorder")
    static let action = Color("EchoAction")
    static let onAction = Color("EchoOnAction")
    static let accent = Color("EchoAccent")
    static let onAccent = Color("EchoOnAccent")
    static let accentSoft = Color("EchoAccentSoft")
    static let accentText = Color("EchoAccentText")
    static let focus = Color("EchoFocus")
    static let success = Color("EchoSuccess")
    static let successSurface = Color("EchoSuccessSurface")
    static let warning = Color("EchoWarning")
    static let warningSurface = Color("EchoWarningSurface")
    static let danger = Color("EchoDanger")
    static let dangerSurface = Color("EchoDangerSurface")
    static let disabled = Color("EchoDisabled")
    static let onDisabled = Color("EchoOnDisabled")
    static let brandCoral = Color("EchoBrandCoral")
    static let brandIndigo = Color("EchoBrandIndigo")
    static let brandPeach = Color("EchoBrandPeach")
    static let brandLavender = Color("EchoBrandLavender")
    static let brandYellow = Color("EchoBrandYellow")
    static let brandMint = Color("EchoBrandMint")
    static let cream = background
    static let ink = text
    static let muted = textSecondary
    static let teal = success
    static let violet = focus
    static let coral = accentText

    static func sceneAsset(_ scene: String) -> String {
        switch scene {
        case "Food": "scene-food"
        case "Getting Ready", "Get ready": "scene-ready"
        case "Bedtime": "scene-bedtime"
        default: "scene-toys"
        }
    }
    static func sceneColor(_ scene: String) -> Color {
        switch scene {
        case "Food": brandYellow
        case "Getting Ready", "Get ready": brandMint
        case "Bedtime": brandLavender
        default: brandPeach
        }
    }
    static func sceneTitle(_ scene: String) -> String { scene == "Getting Ready" ? "Get ready" : scene }
}

struct EchoCard: ViewModifier {
    var color = EchoStyle.surface
    func body(content: Content) -> some View {
        content.padding(20)
            .background {
                RoundedRectangle(cornerRadius: 28, style: .continuous).fill(color)
                    .shadow(color: EchoStyle.border.opacity(0.55), radius: 0, x: 0, y: 5)
            }
    }
}
extension View {
    func echoCard(color: Color = EchoStyle.surface) -> some View { modifier(EchoCard(color: color)) }
}

struct EchoActionStyle: ButtonStyle {
    var primary = true
    var child = false
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(.headline, design: .rounded, weight: .bold))
            .multilineTextAlignment(.center)
            .foregroundStyle(isEnabled ? (primary ? EchoStyle.onAction : EchoStyle.text) : EchoStyle.onDisabled)
            .padding(.horizontal, 20).padding(.vertical, 16)
            .frame(maxWidth: .infinity, minHeight: child ? 64 : 56)
            .background(isEnabled ? (primary ? EchoStyle.action : EchoStyle.surface) : EchoStyle.disabled,
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(primary || !isEnabled ? Color.clear : EchoStyle.controlBorder, lineWidth: 1.5))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct EchoCoralStyle: ButtonStyle {
    var child = false
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(.headline, design: .rounded, weight: .bold))
            .multilineTextAlignment(.center)
            .foregroundStyle(isEnabled ? EchoStyle.onAccent : EchoStyle.onDisabled)
            .padding(.horizontal, 20).padding(.vertical, 16)
            .frame(maxWidth: .infinity, minHeight: child ? 64 : 56)
            .background(isEnabled ? EchoStyle.accent : EchoStyle.disabled,
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct EchoBrandHeader: View {
    var parent = false
    @EnvironmentObject private var model: AppModel
    @Environment(\.dynamicTypeSize) private var dynamicType
    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image("echo-logo").resizable().scaledToFit().frame(width: 160, height: 44).accessibilityLabel("Echo")
                    if parent && !dynamicType.isAccessibilitySize {
                        Text("/ parents").font(.caption.weight(.bold)).foregroundStyle(EchoStyle.text)
                    }
                }
                if parent && dynamicType.isAccessibilitySize {
                    Text("/ parents").font(.caption.weight(.bold)).foregroundStyle(EchoStyle.text)
                }
            }
            Spacer(minLength: 8)
            Button {
                if parent { model.leaveParentArea() }
                else { Task { await model.requestParentAccess() } }
            } label: {
                Group {
                    if model.isAuthenticatingParent { ProgressView() }
                    else { Image(systemName: parent ? "xmark" : "lock") }
                }.font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(EchoStyle.text).frame(width: 56, height: 56)
                    .background(EchoStyle.surface, in: RoundedRectangle(cornerRadius: 18))
            }.buttonStyle(.plain).disabled(model.isAuthenticatingParent)
                .accessibilityLabel(parent ? "Return to child area" : "Open parent area; adult verification required")
                .accessibilityIdentifier(parent ? "leaveParentArea" : "parentGate")
        }
    }
}

struct EchoMark: View {
    var body: some View {
        Image("echo-mark").resizable().scaledToFit().frame(width: 44, height: 44).accessibilityHidden(true)
    }
}
struct SceneBadge: View {
    let scene: String
    var body: some View {
        Text(EchoStyle.sceneTitle(scene)).font(.system(.caption, design: .rounded, weight: .bold))
            .foregroundStyle(EchoStyle.accentText).padding(.horizontal, 12).padding(.vertical, 6)
            .background(EchoStyle.accentSoft, in: Capsule())
    }
}
struct ExpressionRow: View {
    var expression: Expression
    var scene: String
    @Environment(\.dynamicTypeSize) private var dynamicType
    var body: some View {
        let layout = dynamicType.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
        layout {
            Image(EchoStyle.sceneAsset(scene)).resizable().scaledToFit().frame(width: 64, height: 56).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(expression.text).font(.system(.headline, design: .rounded, weight: .bold)).foregroundStyle(EchoStyle.text)
                if !expression.meaning.isEmpty { Text(expression.meaning).font(.subheadline).foregroundStyle(EchoStyle.textSecondary) }
                Text(expression.isConfirmed ? EchoStyle.sceneTitle(scene) : "Draft · Adult review")
                    .font(.caption).foregroundStyle(expression.isConfirmed ? EchoStyle.textSecondary : EchoStyle.accentText)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if expression.isFavorite { Image(systemName: "heart.fill").foregroundStyle(EchoStyle.accentText).accessibilityLabel("Favourite") }
        }.padding(.vertical, 8)
    }
}
struct AudioNotice: View {
    @EnvironmentObject var audio: AudioController
    var body: some View {
        if let message = audio.errorMessage {
            Label(message, systemImage: "info.circle").font(.callout).foregroundStyle(EchoStyle.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
struct RecordingPanel: View {
    @EnvironmentObject var audio: AudioController
    var mode: RecordingMode
    var locale = "zh-CN"
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if audio.isRecording {
                Label("Recording · \(Int(audio.elapsed))s", systemImage: "mic.circle.fill").foregroundStyle(EchoStyle.danger).font(.headline)
                Button { audio.stopRecording() } label: { Label("Stop Recording", systemImage: "stop.fill") }
                    .buttonStyle(EchoActionStyle(child: mode == .practice)).accessibilityIdentifier("stopRecording")
            } else if audio.phase == .transcribing {
                ProgressView("Processing on this iPhone…")
                Button("Cancel Processing") { audio.interrupt() }.buttonStyle(EchoActionStyle(primary: false))
            } else if let url = audio.temporaryRecordingURL {
                Button { audio.playRecording(url: url) } label: { Label("Listen to Our Voice", systemImage: "play.fill") }.buttonStyle(EchoActionStyle())
                Button("Discard Recording", role: .destructive) { audio.discardTemporaryRecording() }.buttonStyle(EchoActionStyle(primary: false))
            } else {
                Button { Task { await audio.startRecording(mode: mode, localeIdentifier: locale) } } label: {
                    Label(mode == .context ? "Record a Short Moment" : "Start Recording", systemImage: "mic")
                }.buttonStyle(EchoActionStyle(primary: false, child: mode == .practice)).accessibilityIdentifier("startRecording")
            }
            AudioNotice()
            Text(mode == .context ? "Up to 45 seconds. Recording starts only when you tap. On-device transcription only; temporary audio is removed when you finish or cancel." : "Up to 30 seconds. Recording starts only when you tap. Listen together; there are no scores. Only Save Recording keeps the audio.")
                .font(.callout).foregroundStyle(EchoStyle.textSecondary)
        }
    }
}

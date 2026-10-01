import SwiftUI

enum EchoStyle {
    static let background = Color.white
    static let text = Color.black
    static let action = Color(red: 0.12, green: 0.32, blue: 0.62)
    static let onAction = Color.white
    static let listening = Color.red
    static let quiet = Color(white: 0.35)
}

struct GrandparentButtonStyle: ButtonStyle {
    var filled = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 24, weight: .semibold))
            .multilineTextAlignment(.center)
            .foregroundStyle(filled ? EchoStyle.onAction : EchoStyle.text)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(filled ? EchoStyle.action : Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                if !filled {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(EchoStyle.text, lineWidth: 2)
                }
            }
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

struct RecordButton: View {
    var listening: Bool
    var title: String
    var action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathe = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 28, weight: .semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.white)
                .frame(width: 200, height: 200)
                .background(listening ? EchoStyle.listening : EchoStyle.action, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .scaleEffect(!listening && breathe && !reduceMotion ? 1.05 : 1)
        .animation(reduceMotion || listening ? nil : .easeInOut(duration: 2.4).repeatForever(autoreverses: true), value: breathe)
        .onAppear { breathe = true }
        .accessibilityIdentifier("recordButton")
    }
}

import SwiftUI
import UIKit
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
}

struct GrandparentButtonStyle: ButtonStyle {
    var filled = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(filled ? Color.white : EchoStyle.text)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(filled ? EchoStyle.action : Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(filled ? Color.clear : Color(white: 0.8), lineWidth: 1))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += row + spacing; row = 0 }
            x += size.width + spacing
            row = max(row, size.height)
        }
        return CGSize(width: width, height: y + row)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += row + spacing; row = 0 }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: size.width, height: size.height))
            x += size.width + spacing
            row = max(row, size.height)
        }
    }
}

struct TappableEnglish: View {
    var text: String
    var size: CGFloat
    var weight: Font.Weight = .bold
    var ipa: String? = nil
    @EnvironmentObject private var audio: AudioController
    var body: some View {
        let tokens = AudioController.wordTokens(text)
        FlowLayout(spacing: 8) {
            ForEach(Array(tokens.enumerated()), id: \.offset) { index, token in
                let highlighted = audio.activeSpeechText == text && audio.activeWordIndex == index
                Button {
                    audio.speakWord(token, ipa: tokens.count == 1 ? ipa : nil)
                } label: {
                    Text(token)
                        .font(.system(size: size, weight: highlighted ? .bold : weight))
                        .foregroundStyle(highlighted ? EchoStyle.accent : Color.black)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct EchoTabBar: View {
    @Binding var tab: Int
    private let items: [(String, String)] = [
        ("说一句", "mic.fill"),
        ("单词", "square.grid.2x2.fill"),
        ("今天", "calendar"),
        ("爸妈", "person.2.fill")
    ]
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                let selected = tab == index
                Button {
                    tab = index
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: item.1).font(.system(size: 28))
                        Text(item.0).font(.system(size: 20, weight: selected ? .bold : .semibold))
                    }
                    .foregroundStyle(selected ? EchoStyle.accent : EchoStyle.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.0)
                .accessibilityIdentifier(item.0)
                .accessibilityAddTraits(selected ? .isSelected : AccessibilityTraits())
            }
        }
        .frame(height: 84)
        .background(Color.white)
        .overlay(alignment: .top) { Rectangle().fill(Color(white: 0.88)).frame(height: 1) }
    }
}

struct HoldToEnterButton: View {
    var action: () -> Void
    var body: some View {
        HoldToEnterControl(action: action)
            .frame(width: 240, height: 240)
            .accessibilityElement(children: .contain)
    }
}

/// UIKit hold control. SwiftUI long-press resets when the progress ring redraws, so the ring lives here.
private struct HoldToEnterControl: UIViewRepresentable {
    var action: () -> Void
    func makeUIView(context: Context) -> HoldRingView {
        let view = HoldRingView()
        view.onComplete = action
        return view
    }
    func updateUIView(_ uiView: HoldRingView, context: Context) {
        uiView.onComplete = action
    }
}

final class HoldRingView: UIView {
    var onComplete: (() -> Void)?
    private let track = CAShapeLayer()
    private let ring = CAShapeLayer()
    private let label = UILabel()
    private var displayLink: CADisplayLink?
    private var startedAt: CFTimeInterval = 0
    private var completed = false
    private let holdDuration: CFTimeInterval = 3

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        accessibilityLabel = "按住 3 秒进入"
        accessibilityIdentifier = "parentGate"
        accessibilityTraits = .button
        backgroundColor = .white
        track.fillColor = UIColor.clear.cgColor
        track.strokeColor = (UIColor(named: "EchoTextSecondary") ?? .secondaryLabel).withAlphaComponent(0.25).cgColor
        track.lineWidth = 10
        ring.fillColor = UIColor.clear.cgColor
        ring.strokeColor = (UIColor(named: "EchoAccent") ?? .systemBlue).cgColor
        ring.lineWidth = 10
        ring.lineCap = .butt
        ring.strokeEnd = 0
        layer.addSublayer(track)
        layer.addSublayer(ring)
        label.text = "按住 3 秒进入"
        label.font = .systemFont(ofSize: 24, weight: .semibold)
        label.textColor = .black
        label.textAlignment = .center
        label.numberOfLines = 2
        label.isAccessibilityElement = false
        addSubview(label)
    }

    required init?(coder: NSCoder) { nil }

    deinit { displayLink?.invalidate() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let side = min(bounds.width, bounds.height)
        let line = track.lineWidth
        let radius = side / 2 - line / 2 - 1
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let path = UIBezierPath(arcCenter: center, radius: radius, startAngle: -CGFloat.pi / 2, endAngle: CGFloat.pi * 1.5, clockwise: true)
        track.path = path.cgPath
        ring.path = path.cgPath
        ring.frame = bounds
        track.frame = bounds
        label.frame = bounds.insetBy(dx: 36, dy: 36)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        guard !completed else { return }
        startedAt = CACurrentMediaTime()
        ring.strokeEnd = 0
        displayLink?.invalidate()
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        let elapsed = CACurrentMediaTime() - startedAt
        if !completed, startedAt > 0, elapsed >= holdDuration { finish() }
        else { cancelIfNeeded() }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        cancelIfNeeded()
    }

    private func cancelIfNeeded() {
        guard !completed else { return }
        displayLink?.invalidate()
        displayLink = nil
        ring.strokeEnd = 0
    }

    @objc private func tick() {
        let elapsed = CACurrentMediaTime() - startedAt
        ring.strokeEnd = min(1, CGFloat(elapsed / holdDuration))
        guard elapsed >= holdDuration else { return }
        finish()
    }

    private func finish() {
        guard !completed else { return }
        completed = true
        displayLink?.invalidate()
        displayLink = nil
        ring.strokeEnd = 1
        onComplete?()
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
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)
                .padding(12)
                .frame(width: 200, height: 200)
                .background(Circle().fill(listening ? EchoStyle.danger : EchoStyle.action))
                .scaleEffect(!listening && breathe && !reduceMotion ? 1.045 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("recordButton")
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { breathe = true }
        }
    }
}

struct SavedStar: View {
    @State private var visible = false
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "star.fill")
                .font(.system(size: 64))
                .foregroundStyle(EchoStyle.accent)
            Text("录好了")
                .font(.system(size: 28, weight: .semibold))
        }
        .frame(maxWidth: .infinity, minHeight: 64)
        .opacity(visible ? 1 : 0)
        .onAppear { withAnimation(.easeIn(duration: 0.2)) { visible = true } }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    var url: URL
    var onDone: () -> Void
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in onDone() }
        return controller
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

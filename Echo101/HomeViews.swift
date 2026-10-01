import SwiftUI
import EchoCore
import EchoAPI

struct GrandparentHome: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var store: EchoStore
    @EnvironmentObject private var audio: AudioController
    @EnvironmentObject private var api: ModelService
    @ScaledMetric(relativeTo: .largeTitle) private var englishSize: CGFloat = 34
    @ScaledMetric(relativeTo: .title) private var chineseSize: CGFloat = 28
    @ScaledMetric(relativeTo: .title3) private var smallSize: CGFloat = 20

    private var listening: Bool {
        if case .listening = model.step { return true }
        return audio.phase == .recording && audio.activeRecordingMode == .grandparent
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Spacer(minLength: 12)
            content
            Spacer(minLength: 12)
            if showsRecordButton {
                RecordButton(
                    listening: audio.phase == .recording && audio.activeRecordingMode == .grandparent,
                    title: api.isBusy ? "请稍等……" : (listening ? "正在听…… \(Int(audio.elapsed))" : "按一下，说中文")
                ) {
                    model.toggleListening()
                }
                .padding(.bottom, 36)
            }
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
        .foregroundStyle(Color.black)
    }

    private var showsRecordButton: Bool {
        switch model.step {
        case .waiting, .listening: return true
        case .result, .notice: return false
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text("Echo")
                .font(.system(size: max(20, smallSize), weight: .semibold))
            Spacer()
            Text(model.badgeCount > 0 ? "爸妈 \(model.badgeCount)" : "爸妈")
                .font(.system(size: max(20, smallSize), weight: .semibold))
                .foregroundStyle(EchoStyle.quiet)
                .frame(minWidth: 88, minHeight: 64)
                .contentShape(Rectangle())
                .onLongPressGesture(minimumDuration: 3) { model.enterParentArea() }
                .accessibilityIdentifier("parentEntry")
                .accessibilityLabel(model.badgeCount > 0 ? "爸妈，\(model.badgeCount) 件待处理，长按三秒" : "爸妈，长按三秒")
        }
        .padding(.top, 8)
    }

    @ViewBuilder private var content: some View {
        switch model.step {
        case .waiting:
            waiting
        case .listening:
            Text("正在听……")
                .font(.system(size: max(28, chineseSize), weight: .semibold))
                .frame(maxWidth: .infinity)
        case .result(let id):
            if let record = store.snapshot.records.first(where: { $0.id == id }) {
                result(record)
            } else {
                waiting
            }
        case .notice(let text, let kind):
            notice(text, kind: kind)
        }
    }

    private var waiting: some View {
        VStack(spacing: 16) {
            if let record = model.lastSpokenRecord {
                Button { model.replayLast() } label: {
                    VStack(spacing: 8) {
                        Text(record.chinese.isEmpty ? record.recognizedText : record.chinese)
                            .font(.system(size: max(28, chineseSize), weight: .regular))
                        Text(record.english)
                            .font(.system(size: max(34, englishSize), weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(Color.black)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("lastSentence")
            } else {
                Text("说一句眼前的事")
                    .font(.system(size: max(28, chineseSize), weight: .regular))
            }
        }
    }

    private func result(_ record: SpeechRecord) -> some View {
        VStack(spacing: 20) {
            Text(record.chinese.isEmpty ? " " : record.chinese)
                .font(.system(size: max(28, chineseSize), weight: .regular))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            Text(record.recognizedText)
                .font(.system(size: max(20, smallSize)))
                .foregroundStyle(EchoStyle.quiet)
                .multilineTextAlignment(.center)
            Text(record.english)
                .font(.system(size: max(34, englishSize), weight: .bold))
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("resultEnglish")
            if record.needsConfirmation {
                Text("待爸妈确认")
                    .font(.system(size: max(20, smallSize)))
                    .foregroundStyle(EchoStyle.quiet)
                    .accessibilityIdentifier("pendingMark")
            }
            if model.childSaved {
                Text("录好了")
                    .font(.system(size: max(28, chineseSize), weight: .semibold))
                    .accessibilityIdentifier("childSaved")
            }
            VStack(spacing: 12) {
                Button("播放英文") { model.playEnglish(for: record.id) }
                    .buttonStyle(GrandparentButtonStyle())
                    .accessibilityIdentifier("playEnglish")
                Button("孩子跟读") { Task { await model.childFollow(recordID: record.id) } }
                    .buttonStyle(GrandparentButtonStyle(filled: false))
                    .accessibilityIdentifier("childRepeat")
                Button("再说一遍") { model.sayAgain() }
                    .buttonStyle(GrandparentButtonStyle(filled: false))
                    .accessibilityIdentifier("sayAgain")
            }
        }
    }

    private func notice(_ text: String, kind: AppModel.NoticeKind) -> some View {
        VStack(spacing: 24) {
            Text(text)
                .font(.system(size: max(28, chineseSize), weight: .semibold))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("grandparentNotice")
            Button(kind == .again ? "再说一遍" : "好") {
                if kind == .again { model.sayAgain() } else { model.dismissNotice() }
            }
            .buttonStyle(GrandparentButtonStyle())
            .accessibilityIdentifier("noticeAction")
        }
    }
}

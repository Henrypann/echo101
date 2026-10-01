import SwiftUI
import EchoCore

// TODO: Character mascot skipped per design; do not generate art.

struct SpeakView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var store: EchoStore
    @EnvironmentObject private var audio: AudioController
    @ScaledMetric(relativeTo: .title) private var english: CGFloat = 34
    @ScaledMetric(relativeTo: .title2) private var chinese: CGFloat = 28
    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 8)
            content
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
    }

    @ViewBuilder private var content: some View {
        switch model.speakPhase {
        case .waiting:
            waiting
        case .listening:
            listening
        case .working:
            Text("正在想英文……")
                .font(.system(size: chinese, weight: .semibold))
                .foregroundStyle(Color.black)
        case .notice(let line):
            Text(line)
                .font(.system(size: chinese, weight: .semibold))
                .foregroundStyle(Color.black)
                .multilineTextAlignment(.center)
            Button("再说一遍") { model.sayAgain() }
                .buttonStyle(GrandparentButtonStyle())
        case .result(let id):
            if let record = model.record(id: id) {
                result(record)
            } else {
                waiting
            }
        }
    }

    private var waiting: some View {
        VStack(spacing: 28) {
            if let last = store.snapshot.records.first(where: { !$0.english.isEmpty }) {
                Button { model.playEnglish(for: last) } label: {
                    VStack(spacing: 8) {
                        Text(last.chineseMeaning.isEmpty ? last.recognizedText : last.chineseMeaning)
                            .font(.system(size: chinese, weight: .regular))
                        Text(last.english)
                            .font(.system(size: english, weight: .bold))
                    }
                    .foregroundStyle(Color.black)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
            RecordButton(listening: false, title: "按一下，说中文") {
                Task { await model.toggleRecording() }
            }
        }
    }

    private var listening: some View {
        VStack(spacing: 20) {
            Text("正在听……")
                .font(.system(size: chinese, weight: .semibold))
            Text("\(Int(audio.elapsed)) 秒")
                .font(.system(size: 24, weight: .semibold))
                .monospacedDigit()
            RecordButton(listening: true, title: "正在听……") {
                Task { await model.toggleRecording() }
            }
        }
        .foregroundStyle(Color.black)
    }

    private func result(_ record: SpokenRecord) -> some View {
        VStack(spacing: 16) {
            Text(record.chineseMeaning.isEmpty ? record.recognizedText : record.chineseMeaning)
                .font(.system(size: chinese))
                .foregroundStyle(Color.black)
                .multilineTextAlignment(.center)
            if !record.recognizedText.isEmpty, record.recognizedText != record.chineseMeaning {
                Text(record.recognizedText)
                    .font(.system(size: 20))
                    .foregroundStyle(EchoStyle.textSecondary)
                    .multilineTextAlignment(.center)
            }
            TappableEnglish(text: record.english, size: english)
            if record.waitsForParent {
                Text("待爸妈确认")
                    .font(.system(size: 20))
                    .foregroundStyle(EchoStyle.textSecondary)
            }
            if model.followPhase == .saved {
                SavedStar()
            } else if model.followPhase == .recording {
                Button("正在听孩子……") { model.stopFollow() }
                    .buttonStyle(GrandparentButtonStyle())
            } else {
                Button("播放英文") { model.playEnglish(for: record) }
                    .buttonStyle(GrandparentButtonStyle())
                Button("孩子跟读") { Task { await model.beginFollow(record: record) } }
                    .buttonStyle(GrandparentButtonStyle())
                Button("再说一遍") { model.sayAgain() }
                    .buttonStyle(GrandparentButtonStyle())
            }
        }
    }
}

struct TodayView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var store: EchoStore
    private var records: [SpokenRecord] {
        store.snapshot.records
            .filter { Calendar.current.isDateInToday($0.createdAt) }
            .sorted { $0.createdAt < $1.createdAt }
    }
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                Text("今天")
                    .font(.system(size: 34, weight: .bold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                if records.isEmpty {
                    Text("今天还没有说过")
                        .font(.system(size: 28, weight: .semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 12)
                }
                ForEach(records) { record in
                    VStack(alignment: .leading, spacing: 6) {
                        Button { model.playToday(record) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(record.chineseMeaning.isEmpty ? record.recognizedText : record.chineseMeaning)
                                    .font(.system(size: 24, weight: .semibold))
                                Text(record.english.isEmpty ? "爸妈晚上补英文" : record.english)
                                    .font(.system(size: 20))
                                if record.waitsForParent {
                                    Text("待爸妈确认")
                                        .font(.system(size: 20))
                                        .foregroundStyle(EchoStyle.textSecondary)
                                }
                            }
                            .foregroundStyle(Color.black)
                            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        if let child = record.childAudio {
                            Button("听孩子") { model.playChild(filename: child) }
                                .font(.system(size: 20, weight: .semibold))
                                .frame(minHeight: 44)
                        }
                    }
                    .padding(.horizontal, 16)
                    .background(Color.white)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(white: 0.85), lineWidth: 1))
                }
            }
            .padding(16)
        }
        .background(Color.white)
    }
}

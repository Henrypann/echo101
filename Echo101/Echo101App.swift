import SwiftUI
import EchoCore
import EchoAPI

@main
struct Echo101App: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            Group {
                if let store = model.store, let audio = model.audio {
                    RootShell()
                        .environmentObject(model)
                        .environmentObject(store)
                        .environmentObject(audio)
                        .environmentObject(model.api)
                } else {
                    Text("请让爸妈看看手机")
                        .font(.system(size: 28, weight: .semibold))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.white)
                }
            }
            .onChange(of: scenePhase) { _, phase in model.handleScenePhase(phase) }
        }
    }
}

struct RootShell: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var audio: AudioController
    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch model.tab {
                case 1: WordsRootView()
                case 2: TodayView()
                case 3: ParentGateView()
                default: SpeakView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            EchoTabBar(tab: Binding(
                get: { model.tab },
                set: { newValue in
                    model.lockParentIfNeeded(from: model.tab, to: newValue)
                    model.tab = newValue
                }))
        }
        .background(Color.white)
        .onChange(of: audio.recordingGeneration) { _, _ in
            Task {
                await model.recordingDidStop()
                await model.followDidStop()
            }
        }
    }
}

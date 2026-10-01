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
                    RootView()
                        .environmentObject(model)
                        .environmentObject(store)
                        .environmentObject(audio)
                        .environmentObject(model.api)
                } else {
                    VStack(spacing: 24) {
                        Text("资料暂时打不开")
                            .font(.system(size: 34, weight: .bold))
                        Text(model.parentStatus.isEmpty ? "原来的文件没有被覆盖。请完全退出后再打开。" : model.parentStatus)
                            .font(.system(size: 24))
                            .multilineTextAlignment(.center)
                    }
                    .padding(32)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white)
                    .foregroundStyle(Color.black)
                }
            }
            .preferredColorScheme(.light)
            .overlay {
                if scenePhase != .active, model.audio?.awaitingSystemPermission != true {
                    ZStack {
                        Color.white.ignoresSafeArea()
                        Text("Echo")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(Color.black)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Echo 暂不可用")
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background {
                    model.audio?.interrupt()
                    model.api.cancel()
                    model.flushAndLeaveParent()
                } else if phase == .inactive, model.audio?.awaitingSystemPermission != true {
                    model.audio?.interrupt()
                    model.api.cancel()
                }
            }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dynamicTypeSize) private var dynamicType

    var body: some View {
        Group {
            if model.isParentArea {
                ParentHome()
            } else {
                GrandparentHome()
            }
        }
        .environment(\.dynamicTypeSize, model.snapshotLargeText ? .accessibility3 : dynamicType)
        .background(Color.white)
        .foregroundStyle(Color.black)
    }
}

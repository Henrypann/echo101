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
                    RootView().environmentObject(model).environmentObject(store)
                        .environmentObject(audio).environmentObject(model.api)
                } else {
                    ContentUnavailableView("Your data could not be opened", systemImage: "externaldrive.badge.exclamationmark", description: Text(model.errorMessage ?? "No data was overwritten. Close Echo and try again."))
                }
            }
            .tint(EchoStyle.action)
            .overlay {
                if scenePhase != .active {
                    ZStack {
                        EchoStyle.background.ignoresSafeArea()
                        Image("echo-logo").resizable().scaledToFit().frame(width: 180)
                            .accessibilityLabel("Echo is inactive")
                    }.accessibilityElement(children: .ignore)
                        .accessibilityLabel("Echo is inactive")
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { model.audio?.interrupt(); model.api.cancel() }
                if phase == .background { model.leaveParentArea() }
                if phase == .active { model.startActivityReminder() }
            }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject private var store: EchoStore
    @Environment(\.dynamicTypeSize) private var dynamicType
    var body: some View {
        Group {
            if let page = model.snapshotPage, ["listen", "moment", "review"].contains(page) {
                NavigationStack { snapshotDestination(page) }
            } else if model.isParentMode {
                TabView(selection: $model.parentTab) {
                    NavigationStack { HomeView() }.tabItem { Label("Overview", systemImage: "house") }.tag(0)
                    NavigationStack { CollectionView() }.tabItem { Label("Moments", systemImage: "book") }.tag(1)
                    NavigationStack { SettingsView() }.tabItem { Label("Settings", systemImage: "sun.max") }.tag(2)
                }
            } else {
                TabView(selection: $model.childTab) {
                    NavigationStack { TodayView() }.tabItem { Label("Today", systemImage: "house") }.tag(0)
                    NavigationStack { ExploreView() }.tabItem { Label("Explore", systemImage: "square.grid.2x2") }.tag(1)
                    NavigationStack { MyWorldView() }.tabItem { Label("My World", systemImage: "heart") }.tag(2)
                }
            }
        }
        .id(model.isParentMode)
        .font(.body)
        .foregroundStyle(EchoStyle.text)
        .tint(EchoStyle.accentText)
        .toolbarBackground(EchoStyle.surface, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .environment(\.dynamicTypeSize, model.snapshotLargeText ? .accessibility3 : dynamicType)
        .preferredColorScheme(model.snapshotAppearance == "dark" ? .dark : (model.snapshotAppearance == "light" ? .light : nil))
        .task { model.captureScreenshotIfRequested(); model.startActivityReminder() }
        .onChange(of: model.isParentMode) { _, parent in if !parent { model.startActivityReminder() } }
        .sheet(isPresented: Binding(get: { model.reminderVisible }, set: { if !$0 { model.finishActivity() } })) {
            ActivityGoodbyeView()
        }
        .alert("Parent area is locked", isPresented: Binding(get: { model.parentGateError != nil }, set: { if !$0 { model.parentGateError = nil } })) {
            Button("OK", role: .cancel) { model.parentGateError = nil }
        } message: { Text(model.parentGateError ?? "") }
        .alert("Something needs attention", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    @ViewBuilder private func snapshotDestination(_ page: String) -> some View {
        if page == "moment" { MomentEditor() }
        else if page == "review", let draft = store.snapshot.expressions.first(where: { !$0.isConfirmed }) {
            ExpressionEditor(momentID: draft.momentID, existing: draft)
        } else if let expression = store.snapshot.confirmedExpressions.first {
            ExpressionDetail(expressionID: expression.id)
        } else { TodayView() }
    }
}

private struct ActivityGoodbyeView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image("mascot-goodbye").resizable().scaledToFit().frame(height: 220).accessibilityHidden(true)
                Text("A little time together").font(.system(.title, design: .rounded, weight: .bold)).multilineTextAlignment(.center)
                Text("Ready for a break? Take your little words into the world. You can come back whenever you like.")
                    .foregroundStyle(EchoStyle.textSecondary).multilineTextAlignment(.center)
                Button("Close Activity") { model.finishActivity() }.buttonStyle(EchoActionStyle(child: true))
                Text("A family reminder, not a target.").font(.callout).foregroundStyle(EchoStyle.textSecondary)
            }.padding(24).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }.background(EchoStyle.background).foregroundStyle(EchoStyle.text)
    }
}

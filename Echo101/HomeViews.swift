import SwiftUI
import EchoCore

private struct EchoPage<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) { content }
                .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 32)
                .frame(maxWidth: 640).frame(maxWidth: .infinity)
        }.defaultScrollAnchor(.top).background(EchoStyle.background).foregroundStyle(EchoStyle.text)
    }
}

@MainActor private func sceneFor(_ expression: Expression, in store: EchoStore) -> String {
    store.snapshot.moments.first { $0.id == expression.momentID }?.scene ?? "Everyday"
}

struct TodayView: View {
    @Environment(\.dynamicTypeSize) private var dynamicType
    @EnvironmentObject private var store: EchoStore
    @EnvironmentObject private var model: AppModel
    private var featured: Expression? { store.snapshot.confirmedExpressions.first }
    var body: some View {
        EchoPage {
            EchoBrandHeader()
            Text("Hello, little explorer!").font(.system(.title, design: .rounded, weight: .heavy))
            VStack(alignment: .leading, spacing: 12) {
                Text("LET’S LISTEN & PLAY").font(.caption.weight(.bold))
                    .foregroundStyle(EchoStyle.brandIndigo).padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.white, in: Capsule())
                Image("mascot-welcome").resizable().scaledToFit().frame(maxWidth: .infinity).frame(height: 150)
                    .accessibilityHidden(true)
            }.echoCard(color: EchoStyle.brandPeach)
            Text("Your world. Your words.").font(.system(.title2, design: .rounded, weight: .bold))
            if let expression = featured {
                let layout = dynamicType.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16)) : AnyLayout(HStackLayout(spacing: 20))
                layout {
                    VStack(alignment: .leading, spacing: 8) {
                        SceneBadge(scene: sceneFor(expression, in: store))
                        Text(expression.text).font(.system(.title3, design: .rounded, weight: .bold))
                            .fixedSize(horizontal: false, vertical: true)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Image(EchoStyle.sceneAsset(sceneFor(expression, in: store))).resizable().scaledToFit()
                        .frame(width: 100, height: 72).accessibilityHidden(true)
                }
                Text("Find something familiar. Let’s say it together.").foregroundStyle(EchoStyle.textSecondary)
                NavigationLink { ExpressionDetail(expressionID: expression.id) } label: {
                    Label("Let’s Play", systemImage: "play")
                }.buttonStyle(EchoCoralStyle(child: true)).accessibilityIdentifier("startActivity")
                Button { model.childTab = 2 } label: { Label("Practice Again", systemImage: "speaker.wave.2") }
                    .buttonStyle(EchoActionStyle(primary: false, child: true))
            } else {
                Text("A little moment is a lovely place to start.").font(.title3).foregroundStyle(EchoStyle.textSecondary)
                Text("Ask an adult to add your first words. Then we can listen together.").foregroundStyle(EchoStyle.textSecondary)
                Button { Task { await model.requestParentAccess() } } label: { Label("Ask an Adult", systemImage: "lock") }
                    .buttonStyle(EchoCoralStyle(child: true))
            }
        }.toolbar(.hidden, for: .navigationBar)
    }
}

struct ExploreView: View {
    @Environment(\.dynamicTypeSize) private var dynamicType
    private let scenes = ["Toys", "Food", "Getting Ready", "Bedtime"]
    var body: some View {
        EchoPage {
            EchoBrandHeader()
            Text("Where shall we play?").font(.system(.title, design: .rounded, weight: .heavy))
            Text("Little adventures from everyday life.").foregroundStyle(EchoStyle.textSecondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: dynamicType.isAccessibilitySize ? 1 : 2), spacing: 20) {
                ForEach(scenes, id: \.self) { scene in
                    NavigationLink { SceneExpressionsView(scene: scene) } label: {
                        VStack(alignment: .leading, spacing: 16) {
                            Image(EchoStyle.sceneAsset(scene)).resizable().scaledToFit()
                                .frame(maxWidth: .infinity).frame(height: 100).accessibilityHidden(true)
                            Text(EchoStyle.sceneTitle(scene)).font(.system(.title3, design: .rounded, weight: .bold))
                                .foregroundStyle(EchoStyle.brandIndigo).fixedSize(horizontal: false, vertical: true)
                        }.frame(maxWidth: .infinity, alignment: .leading).echoCard(color: EchoStyle.sceneColor(scene))
                    }.buttonStyle(.plain).accessibilityIdentifier("explore-\(scene)")
                }
            }
            NavigationLink { SceneExpressionsView(scene: "All saved words") } label: {
                Label("All Saved Words", systemImage: "square.stack")
            }.buttonStyle(EchoActionStyle(primary: false, child: true))
            VStack(alignment: .leading, spacing: 8) {
                Label("Pick what feels familiar", systemImage: "info.circle").font(.headline)
                Text("There’s no right order. Start with your day.").foregroundStyle(EchoStyle.textSecondary)
            }.echoCard(color: EchoStyle.surfaceAlt)
        }.toolbar(.hidden, for: .navigationBar)
    }
}

struct SceneExpressionsView: View {
    let scene: String
    @EnvironmentObject private var store: EchoStore
    @EnvironmentObject private var model: AppModel
    private var expressions: [Expression] {
        store.snapshot.confirmedExpressions.filter { scene == "All saved words" || sceneFor($0, in: store) == scene }
    }
    var body: some View {
        EchoPage {
            EchoBrandHeader()
            if scene != "All saved words" {
                Image(EchoStyle.sceneAsset(scene)).resizable().scaledToFit().frame(maxWidth: .infinity).frame(height: 180)
                    .echoCard(color: EchoStyle.sceneColor(scene)).accessibilityHidden(true)
            }
            if expressions.isEmpty {
                Text("Room for little words").font(.system(.title2, design: .rounded, weight: .bold))
                Text("Ask an adult to add a moment from this part of your day.").foregroundStyle(EchoStyle.textSecondary)
                Button { Task { await model.requestParentAccess() } } label: { Label("Ask an Adult", systemImage: "lock") }
                    .buttonStyle(EchoActionStyle(primary: false, child: true))
            }
            ForEach(expressions) { expression in
                NavigationLink { ExpressionDetail(expressionID: expression.id) } label: {
                    ExpressionRow(expression: expression, scene: sceneFor(expression, in: store)).echoCard()
                }.buttonStyle(.plain)
            }
        }.navigationTitle(EchoStyle.sceneTitle(scene)).navigationBarTitleDisplayMode(.inline)
    }
}

struct MyWorldView: View {
    @Environment(\.dynamicTypeSize) private var dynamicType
    @EnvironmentObject private var store: EchoStore
    private var familiar: [Expression] {
        store.snapshot.confirmedExpressions.filter { expression in
            expression.isFavorite || expression.lastUsedAt != nil || store.snapshot.clips.contains { $0.expressionID == expression.id }
        }
    }
    var body: some View {
        EchoPage {
            EchoBrandHeader()
            Text("My little world").font(.system(.title, design: .rounded, weight: .heavy))
            Text("Words from the things you love.").foregroundStyle(EchoStyle.textSecondary)
            HStack(spacing: 12) {
                Image("scene-toys").resizable().scaledToFit().frame(maxWidth: .infinity).accessibilityHidden(true)
                Image("mascot-encourage").resizable().scaledToFit().frame(maxWidth: .infinity).accessibilityHidden(true)
            }.frame(height: 170).echoCard(color: EchoStyle.brandLavender)
            Text("Let’s meet again").font(.system(.title2, design: .rounded, weight: .bold))
            if familiar.isEmpty {
                Text("Listen to a phrase or keep a favourite. It will be here for another day.").foregroundStyle(EchoStyle.textSecondary)
            }
            ForEach(familiar) { expression in
                NavigationLink { ExpressionDetail(expressionID: expression.id) } label: {
                    let layout = dynamicType.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16)) : AnyLayout(HStackLayout(spacing: 16))
                    layout {
                        Image(EchoStyle.sceneAsset(sceneFor(expression, in: store))).resizable().scaledToFit()
                            .frame(width: 64, height: 64).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(expression.text).font(.system(.title3, design: .rounded, weight: .bold)).foregroundStyle(EchoStyle.text)
                            Text(status(for: expression)).font(.caption.weight(.semibold)).foregroundStyle(EchoStyle.textSecondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        if expression.isFavorite { Image(systemName: "heart.fill").foregroundStyle(EchoStyle.accentText).accessibilityLabel("Favourite") }
                    }.echoCard()
                }.buttonStyle(.plain)
            }
            Text("Every little try belongs here.").foregroundStyle(EchoStyle.textSecondary)
        }.toolbar(.hidden, for: .navigationBar)
    }
    private func status(for expression: Expression) -> String {
        if store.snapshot.clips.contains(where: { $0.expressionID == expression.id }) { return "Voice saved" }
        if store.snapshot.events.contains(where: { $0.expressionID == expression.id && $0.kind == .play }) { return "Played example" }
        if store.snapshot.events.contains(where: { $0.expressionID == expression.id && $0.kind == .replay }) { return "Played our voice" }
        return "Favourite phrase"
    }
}

struct HomeView: View {
    @Environment(\.dynamicTypeSize) private var dynamicType
    @EnvironmentObject private var store: EchoStore
    @State private var adding = false
    @State private var capturing = false
    private var weekCount: Int {
        store.snapshot.moments.filter { Calendar.current.isDate($0.createdAt, equalTo: Date(), toGranularity: .weekOfYear) }.count
    }
    var body: some View {
        EchoPage {
            EchoBrandHeader(parent: true)
            Text("Small moments. Real connection.").font(.system(.title, design: .rounded, weight: .heavy))
            Text("A gentle look at your family’s practice.").foregroundStyle(EchoStyle.textSecondary)
            let layout = dynamicType.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16)) : AnyLayout(HStackLayout(spacing: 20))
            layout {
                VStack(alignment: .leading, spacing: 8) {
                    Text("THIS WEEK").font(.caption.weight(.bold)).foregroundStyle(EchoStyle.accentText)
                    Text("\(weekCount) \(weekCount == 1 ? "moment" : "moments")")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                    Text("Shared, not scored.").font(.subheadline).foregroundStyle(EchoStyle.textSecondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image("mascot-welcome").resizable().scaledToFit().frame(width: 88, height: 108).accessibilityHidden(true)
            }.echoCard(color: EchoStyle.accentSoft)
            if let expression = store.snapshot.confirmedExpressions.first {
                Text("Try this together").font(.system(.title3, design: .rounded, weight: .bold))
                NavigationLink { ExpressionDetail(expressionID: expression.id) } label: {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(expression.text).font(.system(.title3, design: .rounded, weight: .bold)).foregroundStyle(EchoStyle.text)
                        Text(expression.parentTip ?? "A familiar phrase for a little moment together.")
                            .foregroundStyle(EchoStyle.textSecondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).echoCard()
                }.buttonStyle(.plain)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Start with your day").font(.system(.title3, design: .rounded, weight: .bold))
                    Text("A toy car, a snack, or getting ready for bed. Save a moment, then add a word or a little sentence.")
                        .foregroundStyle(EchoStyle.textSecondary)
                }.echoCard()
            }
            Button { adding = true } label: { Label("Add a Moment", systemImage: "plus") }
                .buttonStyle(EchoCoralStyle()).accessibilityIdentifier("addMoment")
            Button { capturing = true } label: { Label("Capture a Moment", systemImage: "mic") }
                .buttonStyle(EchoActionStyle(primary: false)).accessibilityIdentifier("captureMoment")
            if !store.snapshot.moments.isEmpty {
                Text("Recent moments").font(.system(.title3, design: .rounded, weight: .bold))
                ForEach(Array(store.snapshot.moments.sorted { $0.createdAt > $1.createdAt }.prefix(4))) { moment in
                    NavigationLink { MomentDetail(momentID: moment.id) } label: { MomentSummary(moment: moment).echoCard() }
                        .buttonStyle(.plain)
                }
            }
            Text("Saved on this iPhone. Listening records are not measures of ability.").font(.callout).foregroundStyle(EchoStyle.textSecondary)
        }.toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $adding) { NavigationStack { MomentEditor() } }
            .sheet(isPresented: $capturing) { NavigationStack { MomentEditor(initialCapture: true) } }
    }
}

private struct MomentSummary: View {
    let moment: Moment
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { SceneBadge(scene: moment.scene); Spacer(); Image(systemName: "chevron.right").font(.caption.weight(.bold)) }
            Text(moment.note.isEmpty ? "A little moment" : moment.note).foregroundStyle(EchoStyle.text)
                .fixedSize(horizontal: false, vertical: true)
            Text(moment.createdAt, style: .date).font(.caption).foregroundStyle(EchoStyle.textSecondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CollectionView: View {
    @EnvironmentObject private var store: EchoStore
    @State private var search = ""
    @State private var scene = "All"
    @State private var adding = false
    private var moments: [Moment] {
        store.snapshot.moments.filter { moment in
            (scene == "All" || moment.scene == scene) && (search.isEmpty || moment.note.localizedCaseInsensitiveContains(search) || store.snapshot.expressions.contains { $0.momentID == moment.id && ($0.text.localizedCaseInsensitiveContains(search) || $0.meaning.localizedCaseInsensitiveContains(search)) })
        }.sorted { $0.createdAt > $1.createdAt }
    }
    var body: some View {
        EchoPage {
            EchoBrandHeader(parent: true)
            Text("Your family’s moments").font(.system(.title, design: .rounded, weight: .heavy))
            Text("Little parts of your day, ready to revisit.").foregroundStyle(EchoStyle.textSecondary)
            HStack {
                Text("Choose a scene").font(.headline)
                Spacer()
                Picker("Scene", selection: $scene) {
                    Text("All").tag("All")
                    ForEach(AppModel.scenes, id: \.self) { Text($0).tag($0) }
                }.pickerStyle(.menu)
            }
            if moments.isEmpty {
                Text(search.isEmpty && scene == "All" ? "Room for little discoveries" : "No matching moments")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                Text(search.isEmpty && scene == "All" ? "Add a moment to start your collection." : "Try another word or scene.")
                    .foregroundStyle(EchoStyle.textSecondary)
            }
            ForEach(moments) { moment in
                VStack(alignment: .leading, spacing: 16) {
                    NavigationLink { MomentDetail(momentID: moment.id) } label: { MomentSummary(moment: moment) }.buttonStyle(.plain)
                    ForEach(store.snapshot.expressions.filter { $0.momentID == moment.id }) { expression in
                        Divider()
                        NavigationLink { ExpressionDetail(expressionID: expression.id) } label: { ExpressionRow(expression: expression, scene: moment.scene) }
                            .buttonStyle(.plain)
                    }
                }.echoCard()
            }
            Button { adding = true } label: { Label("Add a Moment", systemImage: "plus") }.buttonStyle(EchoCoralStyle())
        }.navigationTitle("Moments").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "Find words or moments")
            .sheet(isPresented: $adding) { NavigationStack { MomentEditor() } }
    }
}

struct MomentDetail: View {
    var momentID: UUID
    @EnvironmentObject private var store: EchoStore
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var addingExpression = false
    @State private var generating = false
    @State private var deleting = false
    private var moment: Moment? { store.snapshot.moments.first { $0.id == momentID } }
    private var expressions: [Expression] { store.snapshot.expressions.filter { $0.momentID == momentID } }
    var body: some View {
        Group {
            if model.isParentMode, let moment {
                EchoPage {
                    EchoBrandHeader(parent: true)
                    MomentSummary(moment: moment).echoCard()
                    Button("Edit Moment") { editing = true }.buttonStyle(EchoActionStyle(primary: false))
                    Text("Words & little sentences").font(.system(.title2, design: .rounded, weight: .bold))
                    ForEach(expressions.filter(\.isConfirmed)) { expression in
                        NavigationLink { ExpressionDetail(expressionID: expression.id) } label: { ExpressionRow(expression: expression, scene: moment.scene).echoCard() }.buttonStyle(.plain)
                    }
                    Button { addingExpression = true } label: { Label("Add an Expression", systemImage: "plus") }
                        .buttonStyle(EchoCoralStyle()).accessibilityIdentifier("addExpression")
                    if expressions.contains(where: { !$0.isConfirmed }) {
                        Text("Drafts · Adult review").font(.system(.title3, design: .rounded, weight: .bold))
                        ForEach(expressions.filter { !$0.isConfirmed }) { expression in
                            NavigationLink { ExpressionDetail(expressionID: expression.id) } label: { ExpressionRow(expression: expression, scene: moment.scene).echoCard(color: EchoStyle.accentSoft) }.buttonStyle(.plain)
                        }
                    }
                    Button { generating = true } label: { Label("Find English Ideas", systemImage: "sparkles") }
                        .buttonStyle(EchoActionStyle(primary: false)).disabled(moment.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Text("Optional Wi-Fi generation. Review the text before sending; approve ideas before playing.").foregroundStyle(EchoStyle.textSecondary)
                    Button { deleting = true } label: { Label("Delete Moment", systemImage: "trash") }
                        .buttonStyle(EchoActionStyle(primary: false)).foregroundStyle(EchoStyle.danger)
                }
                .sheet(isPresented: $editing) { NavigationStack { MomentEditor(existing: moment) } }
                .sheet(isPresented: $addingExpression) { NavigationStack { ExpressionEditor(momentID: momentID) } }
                .sheet(isPresented: $generating) { NavigationStack { GenerateView(moment: moment) } }
            } else { ContentUnavailableView("Moment unavailable", systemImage: "lock") }
        }.navigationTitle("Moment").navigationBarTitleDisplayMode(.inline)
            .alert("Delete this moment?", isPresented: $deleting) {
                Button("Delete", role: .destructive) { model.perform { try store.deleteMoment(id: momentID); dismiss() } }
                Button("Cancel", role: .cancel) { }
            } message: {
                let ids = Set(expressions.map(\.id))
                Text("This removes \(expressions.count) expression(s), \(store.snapshot.clips.filter { ids.contains($0.expressionID) }.count) recording(s), and their usage records from this iPhone. Previous exports are not changed.")
            }
    }
}

struct ExpressionDetail: View {
    let expressionID: UUID
    @EnvironmentObject private var store: EchoStore
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var audio: AudioController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicType
    @State private var editing = false
    @State private var recording = false
    @State private var deleting = false
    @State private var clipToDelete: VoiceClip?
    private var expression: Expression? { store.snapshot.expressions.first { $0.id == expressionID } }
    private var clips: [VoiceClip] { store.snapshot.clips.filter { $0.expressionID == expressionID }.sorted { $0.createdAt > $1.createdAt } }
    var body: some View {
        Group {
            if let expression, expression.isConfirmed || model.isParentMode {
                EchoPage {
                    EchoBrandHeader(parent: model.isParentMode)
                    Text(expression.isConfirmed ? "Listen & Say" : "Check it together").font(.system(.title, design: .rounded, weight: .heavy))
                    if expression.isConfirmed {
                        SceneBadge(scene: sceneFor(expression, in: store))
                        Image(audio.phase == .speaking ? "mascot-demonstrate" : EchoStyle.sceneAsset(sceneFor(expression, in: store))).resizable().scaledToFit()
                            .frame(maxWidth: .infinity).frame(height: 160)
                            .echoCard(color: EchoStyle.sceneColor(sceneFor(expression, in: store))).accessibilityHidden(true)
                    } else {
                        Label("Draft · Adult review", systemImage: "pencil.and.outline")
                            .foregroundStyle(EchoStyle.accentText).echoCard(color: EchoStyle.accentSoft)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text(expression.text).font(.system(.title, design: .rounded, weight: .bold)).accessibilityIdentifier("expressionTitle")
                            .fixedSize(horizontal: false, vertical: true)
                        if !expression.meaning.isEmpty { Text(expression.meaning).font(.title3).foregroundStyle(EchoStyle.textSecondary) }
                    }
                    if expression.isConfirmed {
                        playbackControls(expression)
                        Button { audio.stopPlayback(); recording = true } label: { Label("Say It Together", systemImage: "mic") }
                            .buttonStyle(EchoCoralStyle(child: !model.isParentMode)).accessibilityIdentifier("recordTogether")
                        Text("Only records when you tap. You can skip.").font(.callout).foregroundStyle(EchoStyle.textSecondary)
                        if !model.isParentMode {
                            Button("Skip for Now") { audio.stopPlayback(); dismiss() }.buttonStyle(EchoActionStyle(primary: false, child: true))
                                .accessibilityIdentifier("skipActivity")
                            Button { model.perform { try store.toggleFavorite(id: expressionID) } } label: {
                                Label(expression.isFavorite ? "Kept in My World" : "Keep in My World", systemImage: expression.isFavorite ? "heart.fill" : "heart")
                            }.buttonStyle(EchoActionStyle(primary: false, child: true))
                        }
                    }
                    if model.isParentMode { parentActions(expression) }
                    if !clips.isEmpty { recordings }
                }
                .sheet(isPresented: $editing) { NavigationStack { ExpressionEditor(momentID: expression.momentID, existing: expression) } }
                .sheet(isPresented: $recording) { NavigationStack { PracticeView(expression: expression) } }
            } else { ContentUnavailableView("Expression unavailable", systemImage: "leaf") }
        }.navigationBarTitleDisplayMode(.inline)
            .onDisappear { audio.stopPlayback() }
            .alert("Delete this expression?", isPresented: $deleting) {
                Button("Delete", role: .destructive) { audio.stopPlayback(); model.perform { try store.deleteExpression(id: expressionID); dismiss() } }
                Button("Cancel", role: .cancel) { }
            } message: { Text("Its \(clips.count) recording(s) and usage records will also be removed. Previous exports are not changed.") }
            .alert("Delete this recording?", isPresented: Binding(get: { clipToDelete != nil }, set: { if !$0 { clipToDelete = nil } })) {
                Button("Delete", role: .destructive) {
                    audio.stopPlayback()
                    if let clip = clipToDelete { model.perform { try store.deleteClip(id: clip.id) } }
                    clipToDelete = nil
                }
                Button("Cancel", role: .cancel) { clipToDelete = nil }
            } message: { Text("The saved audio will be removed from this iPhone.") }
    }
    private func playbackControls(_ expression: Expression) -> some View {
        VStack(spacing: 12) {
            Button {
                if audio.phase == .speaking {
                    if audio.isSpeechPaused { audio.resumeSpeech() } else { audio.pauseSpeech() }
                } else { play(expression, mode: .normal) }
            } label: {
                Label(audio.phase == .speaking ? (audio.isSpeechPaused ? "Resume" : "Pause") : "Listen",
                      systemImage: audio.phase == .speaking ? (audio.isSpeechPaused ? "play.fill" : "pause.fill") : "speaker.wave.2")
            }.buttonStyle(EchoActionStyle(child: !model.isParentMode)).accessibilityIdentifier("playExpression")
                .accessibilityLabel(audio.phase == .speaking ? (audio.isSpeechPaused ? "Resume the example" : "Pause the example") : "Play the example: \(expression.text)")
            let layout = dynamicType.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
            layout {
                Button("Slow") { play(expression, mode: .slow) }.buttonStyle(EchoActionStyle(primary: false))
                    .accessibilityLabel("Play the example slowly")
                Button("Parts") { play(expression, mode: .parts) }.buttonStyle(EchoActionStyle(primary: false))
                    .disabled(expression.segments.isEmpty).accessibilityLabel("Play the example in parts")
            }
            if audio.phase == .speaking { Label(audio.isSpeechPaused ? "Example paused" : "Playing example", systemImage: "speaker.wave.2").font(.callout).foregroundStyle(EchoStyle.textSecondary) }
            if !expression.segments.isEmpty { Text(expression.segments.joined(separator: "  /  ")).font(.callout).foregroundStyle(EchoStyle.textSecondary) }
            AudioNotice()
        }
    }
    @ViewBuilder private func parentActions(_ expression: Expression) -> some View {
        Button(expression.isConfirmed ? "Edit Expression" : "Review & Confirm") { editing = true }
            .buttonStyle(EchoActionStyle(primary: false)).accessibilityIdentifier("editExpression")
        if expression.isConfirmed {
            Button { model.perform { try store.toggleFavorite(id: expressionID) } } label: {
                Label(expression.isFavorite ? "Remove from Favourites" : "Add to Favourites", systemImage: expression.isFavorite ? "heart.fill" : "heart")
            }.buttonStyle(EchoActionStyle(primary: false))
        }
        if let tip = expression.parentTip, !tip.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Label("Try it together", systemImage: "heart").font(.headline)
                Text(tip).foregroundStyle(EchoStyle.textSecondary)
            }.frame(maxWidth: .infinity, alignment: .leading).echoCard(color: EchoStyle.surfaceAlt)
        }
        if let moment = store.snapshot.moments.first(where: { $0.id == expression.momentID }) {
            VStack(alignment: .leading, spacing: 12) {
                Text("From our life").font(.headline)
                Text(moment.note.isEmpty ? moment.scene : moment.note)
                Text("Source: \(expression.source)").font(.callout).foregroundStyle(EchoStyle.textSecondary)
            }.frame(maxWidth: .infinity, alignment: .leading).echoCard()
        }
        Button { deleting = true } label: { Label("Delete Expression", systemImage: "trash") }
            .buttonStyle(EchoActionStyle(primary: false))
    }
    private var recordings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Our voices").font(.system(.title3, design: .rounded, weight: .bold))
            ForEach(clips) { clip in
                VStack(alignment: .leading, spacing: 12) {
                    Button {
                        model.perform {
                            let url = try store.clipURL(for: clip)
                            audio.playRecording(url: url)
                            if audio.phase == .playingRecord { try store.recordUsage(expressionID: expressionID, kind: .replay) }
                        }
                    } label: { Label("Listen to Our Voice", systemImage: "play.circle") }
                        .buttonStyle(EchoActionStyle(primary: false, child: !model.isParentMode))
                    Text(clip.createdAt, format: .dateTime.month().day().hour().minute()).font(.caption).foregroundStyle(EchoStyle.textSecondary)
                    if model.isParentMode {
                        Button(role: .destructive) { clipToDelete = clip } label: { Label("Delete Recording", systemImage: "trash") }
                            .padding(.vertical, 8).accessibilityLabel("Delete Recording")
                    }
                }.echoCard()
            }
        }
    }
    private func play(_ expression: Expression, mode: SpeechMode) {
        guard expression.isConfirmed else { return }
        model.perform {
            audio.speak(text: expression.speechText, segments: expression.segments, mode: mode)
            if audio.phase == .speaking { try store.recordUsage(expressionID: expression.id, kind: .play) }
        }
    }
}

struct PracticeView: View {
    let expression: Expression
    @EnvironmentObject private var store: EchoStore
    @EnvironmentObject private var audio: AudioController
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    var body: some View {
        EchoPage {
            Text("Say it together").font(.system(.title, design: .rounded, weight: .heavy))
            Image(audio.isRecording ? "mascot-listening" : (audio.temporaryRecordingURL == nil ? "mascot-waiting" : "mascot-encourage"))
                .resizable().scaledToFit().frame(maxWidth: .infinity).frame(height: 180).accessibilityHidden(true)
            Text(expression.text).font(.system(.title2, design: .rounded, weight: .bold))
            RecordingPanel(mode: .practice, locale: "en-US")
            if let url = audio.temporaryRecordingURL, !audio.isRecording {
                Button("Save Recording") {
                    do {
                        audio.stopPlayback()
                        _ = try store.addVoiceClip(expressionID: expression.id, temporaryURL: url)
                        audio.discardTemporaryRecording(); dismiss()
                    } catch { self.error = error.localizedDescription }
                }.buttonStyle(EchoCoralStyle(child: !model.isParentMode)).accessibilityIdentifier("saveRecording")
            }
            Button("Skip for Now") { audio.discardTemporaryRecording(); dismiss() }.buttonStyle(EchoActionStyle(primary: false, child: !model.isParentMode))
        }.navigationTitle("Our Voice").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .onDisappear { audio.discardTemporaryRecording() }
            .alert("Could not save recording", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
    }
}

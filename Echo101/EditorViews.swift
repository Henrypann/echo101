import SwiftUI
import EchoCore

enum WordsRoute: Hashable {
    case category(String)
    case word(String)
}

struct WordsRootView: View {
    @State private var path: [WordsRoute] = []
    var body: some View {
        NavigationStack(path: $path) {
            CategoryPage(path: $path)
                .navigationDestination(for: WordsRoute.self) { route in
                    switch route {
                    case .category(let id): WordListPage(categoryID: id, path: $path)
                    case .word(let id): WordDetailPage(wordID: id, path: $path)
                    }
                }
        }
    }
}

struct CategoryPage: View {
    @Binding var path: [WordsRoute]
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var store: EchoStore
    private var pinned: VocabularyCategory? { model.vocabulary.categories.first { $0.pinned } }
    private var regular: [VocabularyCategory] { model.vocabulary.categories.filter { !$0.pinned } }
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("单词")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 16)
                if let pinned {
                    Button { path.append(.category(pinned.id)) } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(pinned.chinese)
                                    .font(.system(size: 24, weight: .semibold))
                                    .foregroundStyle(Color.black)
                                Text(pinned.subtitle.isEmpty ? "景点和地名" : pinned.subtitle)
                                    .font(.system(size: 20))
                                    .foregroundStyle(EchoStyle.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "map")
                                .font(.system(size: 44))
                                .frame(width: 44, height: 44)
                                .foregroundStyle(EchoStyle.accent)
                        }
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
                        .background(EchoStyle.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .accessibilityIdentifier("category-hangzhou")
                }
                Text("常用单词")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(EchoStyle.textSecondary)
                    .padding(.horizontal, 16)
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(regular) { category in
                        Button { path.append(.category(category.id)) } label: {
                            categoryCard(category)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("category-\(category.id)")
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 12)
        }
        .background(Color.white)
        .navigationBarHidden(true)
    }

    private func categoryCard(_ category: VocabularyCategory) -> some View {
        let done = category.words.filter { store.repeatedWordIDs.contains($0.id) }.count
        let total = category.words.count
        let ratio = total == 0 ? 0 : CGFloat(done) / CGFloat(total)
        return VStack(alignment: .leading, spacing: 6) {
            Text(category.emoji.isEmpty ? "📘" : category.emoji)
                .font(.system(size: 44))
                .frame(height: 44, alignment: .leading)
            Text(category.chinese)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Color.black)
                .lineLimit(2)
            Text(category.english)
                .font(.system(size: 20))
                .foregroundStyle(EchoStyle.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            Text("\(done)/\(total)")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.black)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(white: 0.9))
                    Capsule().fill(EchoStyle.accent).frame(width: geo.size.width * ratio)
                }
            }
            .frame(height: 4)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 160, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(white: 0.82), lineWidth: 1))
    }
}

struct WordListPage: View {
    var categoryID: String
    @Binding var path: [WordsRoute]
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var store: EchoStore
    private var category: VocabularyCategory? { model.vocabulary.categories.first { $0.id == categoryID } }
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if let category {
                    Text(category.chinese)
                        .font(.system(size: 34, weight: .bold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 8)
                    ForEach(category.words) { word in
                        Button {
                            model.playWord(word)
                            path.append(.word(word.id))
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(word.english)
                                        .font(.system(size: 28, weight: .semibold))
                                    Text(word.chinese)
                                        .font(.system(size: 20))
                                        .foregroundStyle(EchoStyle.textSecondary)
                                }
                                Spacer()
                                if store.repeatedWordIDs.contains(word.id) {
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 22))
                                        .foregroundStyle(EchoStyle.accent)
                                }
                                Image(systemName: "play.fill")
                                    .font(.system(size: 44))
                                    .frame(width: 44, height: 44)
                            }
                            .foregroundStyle(Color.black)
                            .frame(maxWidth: .infinity, minHeight: 88)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("word-\(word.id)")
                        Divider()
                    }
                }
            }
            .padding(16)
        }
        .background(Color.white)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("返回") { if !path.isEmpty { path.removeLast() } }
                    .font(.system(size: 20, weight: .semibold))
            }
        }
    }
}

struct WordDetailPage: View {
    var wordID: String
    @Binding var path: [WordsRoute]
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var store: EchoStore
    private var located: (VocabularyCategory, VocabularyWord)? {
        for category in model.vocabulary.categories {
            if let word = category.words.first(where: { $0.id == wordID }) { return (category, word) }
        }
        return nil
    }
    var body: some View {
        ScrollView {
            if let (category, word) = located {
                VStack(spacing: 16) {
                    if !word.emoji.isEmpty {
                        Text(word.emoji).font(.system(size: 64))
                    }
                    if store.repeatedWordIDs.contains(word.id) {
                        Image(systemName: "star.fill").foregroundStyle(EchoStyle.accent).frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    Text(word.chinese)
                        .font(.system(size: 28))
                        .foregroundStyle(Color.black)
                    TappableEnglish(text: word.english, size: 34, ipa: word.ipa.isEmpty ? nil : word.ipa)
                    TappableEnglish(text: word.exampleEn, size: 24, weight: .regular)
                    Text(word.exampleZh)
                        .font(.system(size: 20))
                        .foregroundStyle(EchoStyle.textSecondary)
                        .multilineTextAlignment(.center)
                    actions(category: category, word: word)
                }
                .padding(20)
            }
        }
        .background(Color.white)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("返回") { if !path.isEmpty { path.removeLast() } }
                    .font(.system(size: 20, weight: .semibold))
            }
        }
    }

    @ViewBuilder private func actions(category: VocabularyCategory, word: VocabularyWord) -> some View {
        if model.followPhase == .saved {
            SavedStar()
        } else if model.followPhase == .recording {
            Button("正在听孩子……") { model.stopFollow() }
                .buttonStyle(GrandparentButtonStyle())
        } else {
            Button("播放") { model.playWordLesson(word) }
                .buttonStyle(GrandparentButtonStyle())
                .accessibilityIdentifier("playWord")
            Button("孩子跟读") { Task { await model.practiceWord(word) } }
                .buttonStyle(GrandparentButtonStyle())
            Button("下一个") { goNext(category: category, word: word) }
                .buttonStyle(GrandparentButtonStyle())
                .accessibilityIdentifier("nextWord")
        }
    }

    private func goNext(category: VocabularyCategory, word: VocabularyWord) {
        guard let index = category.words.firstIndex(where: { $0.id == word.id }) else { return }
        let next = category.words.index(after: index)
        guard next < category.words.endIndex else {
            if !path.isEmpty { path.removeLast() }
            return
        }
        if !path.isEmpty { path.removeLast() }
        path.append(.word(category.words[next].id))
    }
}

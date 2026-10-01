import SwiftUI
import UIKit
import ImageIO
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
                            VocabularyPicture(name: pinned.image, emoji: pinned.emoji.isEmpty ? "🗺️" : pinned.emoji, side: 72, fills: true, corner: 12)
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
            VocabularyPicture(name: category.image, emoji: category.emoji.isEmpty ? "📘" : category.emoji, side: 44, fills: false, corner: 8)
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
                            path.append(.word(word.id))
                            let spoken = word
                            Task { @MainActor in model.playWord(spoken) }
                        } label: {
                            HStack(spacing: 12) {
                                VocabularyPicture(name: word.image, emoji: word.emoji, side: 64, fills: word.credit != nil, corner: 12)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(word.english)
                                        .font(.system(size: 28, weight: .semibold))
                                    Text(word.chinese)
                                        .font(.system(size: 20))
                                        .foregroundStyle(EchoStyle.textSecondary)
                                }
                                Spacer(minLength: 8)
                                if store.repeatedWordIDs.contains(word.id) {
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 22))
                                        .foregroundStyle(EchoStyle.accent)
                                        .accessibilityHidden(true)
                                }
                                Image(systemName: "play.fill")
                                    .font(.system(size: 44))
                                    .frame(width: 44, height: 44)
                                    .accessibilityHidden(true)
                            }
                            .foregroundStyle(Color.black)
                            .frame(maxWidth: .infinity, minHeight: 88)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("word-\(word.id)")
                        .accessibilityAddTraits(.isButton)
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
                    if !word.image.isEmpty || !word.emoji.isEmpty {
                        VocabularyPicture(name: word.image, emoji: word.emoji, side: word.credit == nil ? 180 : nil, height: 180, fills: word.credit != nil, corner: 16)
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

/// Bundled vocabulary art. Decoding happens off the tap path so playback is not waiting on the picture.
struct VocabularyPicture: View {
    var name: String
    var emoji: String
    var side: CGFloat?
    var height: CGFloat?
    var fills: Bool
    var corner: CGFloat
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        let boxHeight = height ?? side ?? 64
        let boxWidth = side
        Color.clear
            .frame(width: boxWidth, height: boxHeight)
            .frame(maxWidth: fills && boxWidth == nil ? .infinity : nil)
            .frame(height: boxHeight)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: fills ? .fill : .fit)
                } else if failed && !emoji.isEmpty {
                    Text(emoji)
                        .font(.system(size: min(64, max(20, boxHeight))))
                } else if !name.isEmpty {
                    Color(white: 0.94)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .accessibilityHidden(true)
        .task(id: name) {
            let pixels = max(boxHeight, boxWidth ?? boxHeight) * 3
            let loaded = await VocabularyPictureLoader.image(named: name, maxPixel: pixels)
            image = loaded
            failed = loaded == nil
        }
    }
}

private struct LoadedPicture: @unchecked Sendable {
    let image: UIImage
}

@MainActor
private enum VocabularyPictureLoader {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 80
        return cache
    }()

    static func image(named name: String, maxPixel: CGFloat) async -> UIImage? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let key = "\(trimmed)@\(Int(maxPixel.rounded()))" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let pixels = max(48, maxPixel)
        let loaded = await Task.detached(priority: .userInitiated) { () -> LoadedPicture? in
            guard let url = VocabularyImages.resourceURL(named: trimmed) else { return nil }
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: Int(pixels.rounded()),
                kCGImageSourceShouldCacheImmediately: true
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            return LoadedPicture(image: UIImage(cgImage: cgImage))
        }.value
        guard let loaded else { return nil }
        cache.setObject(loaded.image, forKey: key)
        return loaded.image
    }
}

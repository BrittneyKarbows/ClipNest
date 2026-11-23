import SwiftUI
import AppKit
import UniformTypeIdentifiers

extension Color {
    private static func adaptive(_ light: NSColor, _ dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light })
    }
    static let ink = Color(nsColor: .labelColor)
    static let paper = adaptive(NSColor(srgbRed: 0.97, green: 0.96, blue: 0.93, alpha: 1), NSColor(srgbRed: 0.105, green: 0.11, blue: 0.125, alpha: 1))
    static let card = adaptive(.white, NSColor(srgbRed: 0.16, green: 0.17, blue: 0.19, alpha: 1))
    static let field = adaptive(NSColor.white.withAlphaComponent(0.75), NSColor.white.withAlphaComponent(0.07))
    static let chrome = adaptive(NSColor.white.withAlphaComponent(0.35), NSColor.white.withAlphaComponent(0.025))
    static let edge = adaptive(NSColor.white.withAlphaComponent(0.8), NSColor.white.withAlphaComponent(0.10))
    static let accent = adaptive(NSColor(srgbRed: 0.91, green: 0.40, blue: 0.13, alpha: 1), NSColor(srgbRed: 1, green: 0.60, blue: 0.32, alpha: 1))
}

struct PanelView: View {
    @ObservedObject var store: ClipStore
    @ObservedObject var state: PanelState
    @ObservedObject private var preferences = Preferences.shared
    let controller: AppController
    @FocusState private var searchFocused: Bool
    private var clips: [Clip] { state.visible(store) }
    var body: some View {
        VStack(spacing: 0) {
            header
            HStack(spacing: 5) {
                tab("全部记录", symbol: "clock.arrow.circlepath", filter: .history)
                tab("我的收藏", symbol: "star", filter: .starred)
                ForEach(store.boards) { board in
                    tab(board.name, symbol: "folder", filter: .board(board.id))
                        .contextMenu { Button("删除分类（保留内容）") { store.deleteBoard(board); state.filter = .history } }
                }
                Button(action: controller.newBoard) { Image(systemName: "plus").font(.system(size: 11, weight: .semibold)).frame(width: 28, height: 27) }.buttonStyle(.plain).help("新建分类")
                Spacer(minLength: 0)
                Menu {
                    Button("全部类型") { state.filter = .history }
                    ForEach(ClipKind.allCases, id: \.rawValue) { kind in Button(kind.label) { state.filter = .kind(kind) } }
                } label: { Label("类型", systemImage: "line.3.horizontal.decrease").font(.system(size: 11)).foregroundColor(.secondary) }.menuStyle(.borderlessButton).fixedSize()
                Text("\(clips.count) 条").font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary).padding(.leading, 8)
            }.padding(.horizontal, 24).padding(.bottom, 13)
            Rectangle().fill(Color.ink.opacity(0.07)).frame(height: 1)
            if clips.isEmpty { emptyState.frame(maxWidth: .infinity, maxHeight: .infinity) }
            else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 14) {
                            ForEach(Array(clips.enumerated()), id: \.element.id) { index, clip in
                                ClipCard(clip: clip, index: index, selected: state.selectedID == clip.id, doubleClickToPaste: preferences.doubleClickToPaste, select: { state.selectedID = clip.id; searchFocused = false }, paste: { controller.paste(clip) }, star: { store.toggleStar(clip) })
                                    .id(clip.id)
                                    .contextMenu {
                                        Button("粘贴到原应用") { controller.paste(clip) }
                                        Button("复制到剪贴板") { controller.paste(clip, copyOnly: true) }
                                        Button(clip.starred ? "取消收藏" : "加入收藏") { store.toggleStar(clip) }
                                        if !store.boards.isEmpty { Menu("收藏分类") { ForEach(store.boards) { board in Button((clip.boards.contains(board.id) ? "✓ " : "") + board.name) { store.toggleBoard(clip, board: board) } } } }
                                        Divider()
                                        Button("删除记录", role: .destructive) { store.delete(clip) }
                                    }
                            }
                        }.padding(.horizontal, 24).padding(.vertical, 16)
                    }
                    .onChange(of: state.selectedID) { id in if let id { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id, anchor: .center) } } }
                    .onChange(of: state.query) { _ in state.selectedID = clips.first?.id; if let id = clips.first?.id { proxy.scrollTo(id, anchor: .leading) } }
                    .onChange(of: state.filter) { _ in state.selectedID = clips.first?.id; if let id = clips.first?.id { proxy.scrollTo(id, anchor: .leading) } }
                }
            }
            footer
        }
        .foregroundColor(.ink).background(Color.paper)
        .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 19).strokeBorder(Color.edge, lineWidth: 1))
        .onChange(of: state.focusRequest) { _ in searchFocused = true }
        .onAppear { searchFocused = true; state.selectedID = clips.first?.id }
        .alert("存储遇到问题", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("好") { store.error = nil } } message: { Text(store.error ?? "") }
    }
    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSImage.clipNestIcon)
                .resizable().scaledToFit().frame(width: 36, height: 36)
            Text("剪藏").font(.system(size: 21, weight: .semibold))
            Text("随手复制，好好收藏").font(.system(size: 11)).foregroundColor(.secondary).padding(.leading, 4)
            Spacer()
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("搜索内容或来源应用…", text: $state.query).textFieldStyle(.plain).focused($searchFocused)
                if !state.query.isEmpty { Button { state.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundColor(.secondary) }.buttonStyle(.plain) }
                Text(preferences.shortcut.display).font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary)
            }.font(.system(size: 12)).padding(.horizontal, 11).frame(width: 280, height: 33).background(Color.field).clipShape(RoundedRectangle(cornerRadius: 9))
            Button { preferences.paused.toggle() } label: { Image(systemName: preferences.paused ? "play.circle" : "pause.circle").font(.system(size: 17)).frame(width: 27, height: 30) }.buttonStyle(.plain).help(preferences.paused ? "继续记录" : "暂停记录")
            Button(action: controller.showSettings) { Image(systemName: "gearshape").font(.system(size: 16)).frame(width: 27, height: 30) }.buttonStyle(.plain).help("设置 ⌘,")
        }.padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 16)
    }
    private func tab(_ title: String, symbol: String, filter: ClipFilter) -> some View {
        Button { state.filter = filter } label: {
            Label(title, systemImage: symbol).font(.system(size: 12, weight: state.filter == filter ? .semibold : .regular)).lineLimit(1)
                .padding(.horizontal, 11).frame(height: 28)
                .foregroundColor(state.filter == filter ? .accent : .ink.opacity(0.65))
                .background(state.filter == filter ? Color.accent.opacity(0.10) : .clear).clipShape(RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(.plain)
    }
    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: state.query.isEmpty ? "doc.on.clipboard" : "magnifyingglass").font(.system(size: 32, weight: .light)).foregroundColor(.accent.opacity(0.6))
            Text(state.query.isEmpty ? (state.filter == .history ? "你的下一次复制，从这里收藏" : "这里还没有收藏") : "没有找到相关内容").font(.system(size: 16, weight: .medium))
            Text(state.query.isEmpty ? "复制文字、链接、图片或文件后，按 \(preferences.shortcut.display) 随时找回。" : "试试其他关键词，或切换到全部记录。").font(.system(size: 12)).foregroundColor(.secondary)
        }
    }
    private var footer: some View {
        HStack(spacing: 7) {
            Circle().fill(preferences.paused ? Color.orange : Color(red: 0.38, green: 0.57, blue: 0.42)).frame(width: 5, height: 5)
            Text(state.message ?? (preferences.paused ? "记录已暂停" : "仅保存在这台 Mac")).lineLimit(2).help(state.message ?? "剪贴板历史仅保存在本机")
            if state.message != nil { Button { state.message = nil } label: { Image(systemName: "xmark").font(.system(size: 8)) }.buttonStyle(.plain) }
            Spacer()
            Text(state.message == nil ? "↓ 选择卡片    ← → 切换    ↩ 粘贴    ⇧↩ 复制    ⌘1–9 快速粘贴    esc 收起" : "⌘, 设置    esc 收起").lineLimit(1)
        }.font(.system(size: 10)).foregroundColor(.secondary).padding(.horizontal, 25).frame(height: 32)
        .background(Color.chrome)
    }
}

// Resolve locally using the source identity already stored with every clip.
// Reuse icons across cards instead of repeatedly querying Launch Services.
private final class SourceAppIconCache {
    final class Appearance {
        let image: NSImage
        let palette: IconPalette
        init(image: NSImage, hasApp: Bool) { self.image = image; palette = hasApp ? .extract(from: image) : .neutral }
    }
    static let shared = SourceAppIconCache()
    private let images = NSCache<NSString, Appearance>()
    private init() { images.countLimit = 128 }
    func appearance(for clip: Clip) -> Appearance {
        let key = (clip.bundleID.isEmpty ? "name:\(clip.source)" : "bundle:\(clip.bundleID)") as NSString
        if let appearance = images.object(forKey: key) { return appearance }
        let workspace = NSWorkspace.shared
        let running = workspace.runningApplications.first {
            clip.bundleID.isEmpty ? $0.localizedName == clip.source : $0.bundleIdentifier == clip.bundleID
        }
        let url = running?.bundleURL ?? (clip.bundleID.isEmpty ? nil : workspace.urlForApplication(withBundleIdentifier: clip.bundleID))
        let image = clip.bundleID == Bundle.main.bundleIdentifier ? NSImage.clipNestIcon : (url.map { workspace.icon(forFile: $0.path) } ?? workspace.icon(for: .application))
        let appearance = Appearance(image: image, hasApp: url != nil)
        images.setObject(appearance, forKey: key)
        return appearance
    }
}

struct ClipCard: View {
    let clip: Clip
    let index: Int
    let selected: Bool
    let doubleClickToPaste: Bool
    let select: () -> Void
    let paste: () -> Void
    let star: () -> Void
    var body: some View {
        let appearance = SourceAppIconCache.shared.appearance(for: clip)
        let tint = Color(nsColor: appearance.palette.background)
        let headerText = Color(nsColor: appearance.palette.foreground)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(clip.kindLabel, systemImage: clip.hasImagePreview ? "photo" : clip.kind.symbol).font(.system(size: 11, weight: .semibold))
                    Text(clip.updated, style: .relative).font(.system(size: 9)).foregroundColor(headerText.opacity(0.85)).lineLimit(1)
                }.foregroundColor(headerText).padding(.leading, 13)
                Spacer(minLength: 6)
                Image(nsImage: appearance.image)
                    .resizable().interpolation(.high).scaledToFit()
                    .frame(width: 50, height: 50).padding(2)
                    .accessibilityLabel("来源应用：\(clip.source)")
                    .help("来源应用：\(clip.source)")
            }.frame(height: 54).background(tint)
            Group {
                if clip.hasImagePreview, let data = clip.data, let image = NSImage(data: data) {
                    Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity).padding(9)
                } else if clip.kind == .link {
                    VStack(alignment: .leading, spacing: 11) {
                        Image(systemName: "arrow.up.right").font(.system(size: 25, weight: .light)).foregroundColor(tint)
                        Text(URL(string: clip.text)?.host ?? "链接").font(.system(size: 17, weight: .semibold)).lineLimit(2)
                        Text(clip.text).font(.system(size: 10)).foregroundColor(.secondary).lineLimit(3)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(14)
                } else {
                    Text(String(clip.title.prefix(1400))).font(.system(size: 12)).lineSpacing(5).lineLimit(7).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(14)
                }
            }.clipped()
            HStack(spacing: 5) {
                Text(clip.source).lineLimit(1)
                Spacer(minLength: 3)
                Button(action: paste) { Image(systemName: "arrow.turn.down.left").font(.system(size: 10, weight: .semibold)).foregroundColor(selected ? .accent : .ink.opacity(0.45)).frame(width: 22, height: 24) }.buttonStyle(.plain).help("粘贴到目标应用（回车）")
                Button(action: star) { Image(systemName: clip.starred ? "star.fill" : "star").font(.system(size: 11)).foregroundColor(clip.starred ? .accent : .ink.opacity(0.4)).frame(width: 20, height: 24) }.buttonStyle(.plain).help(clip.starred ? "取消收藏" : "收藏")
                if index < 9 { Text("⌘\(index + 1)").font(.system(size: 9, design: .monospaced)).padding(.horizontal, 4).padding(.vertical, 2).background(Color.ink.opacity(0.05)).cornerRadius(3) }
            }.font(.system(size: 9)).foregroundColor(.secondary).padding(.horizontal, 12).frame(height: 30)
        }
        .frame(width: 218, height: 213).background(Color.card)
        .clipShape(RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(selected ? Color.accent : Color.ink.opacity(0.09), lineWidth: selected ? 2 : 1))
        .shadow(color: .black.opacity(0.035), radius: 4, y: 2)
        .contentShape(RoundedRectangle(cornerRadius: 11))
        .onTapGesture(perform: select)
        .simultaneousGesture(TapGesture(count: 2).onEnded { if doubleClickToPaste { paste() } })
        .help(doubleClickToPaste ? "单击选择，双击粘贴；右键管理记录" : "单击选择，按回车或点击卡片底部箭头粘贴；右键管理记录")
        .accessibilityElement(children: .contain).accessibilityLabel("\(clip.kindLabel)，\(clip.source)，\(String(clip.title.prefix(80)))")
    }
}

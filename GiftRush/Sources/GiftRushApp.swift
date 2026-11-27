import SwiftUI
import Combine
import Lottie

@main
struct GiftRushApp: App {
    var body: some Scene {
        WindowGroup { GiftRushRootView() }
    }
}

struct Gift: Identifiable, Decodable, Hashable {
    let id: Int64
    let filename: String
    let stars: Int?
    let limited: Bool
    let soldOut: Bool
}

@MainActor
final class GiftStore: ObservableObject {
    @Published var gifts: [Gift] = []
    init() {
        guard let url = Bundle.main.url(forResource: "gifts", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let items = try? JSONDecoder().decode([Gift].self, from: data) else { return }
        gifts = items
    }
}

struct GiftRushRootView: View {
    @StateObject private var store = GiftStore()
    var body: some View {
        TabView {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("GIFT RUSH").font(.system(size: 34, weight: .black, design: .rounded))
                                .foregroundStyle(LinearGradient(colors: [.cyan, .purple], startPoint: .leading, endPoint: .trailing))
                            Text("Коллекция Telegram-подарков с оригинальными анимациями.")
                                .foregroundStyle(.secondary)
                            Label("\(store.gifts.count) подарков · TGS-анимации", systemImage: "sparkles")
                                .font(.caption.bold()).foregroundStyle(.cyan)
                        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.cyan.opacity(0.09), in: RoundedRectangle(cornerRadius: 22))
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 12)], spacing: 12) {
                            ForEach(store.gifts) { gift in
                                NavigationLink { GiftDetailView(gift: gift) } label: { GiftCard(gift: gift) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }.padding()
                }
                .background(Color(uiColor: .systemGroupedBackground))
                .navigationTitle("Подарки")
                .searchable(text: .constant(""), prompt: "Подарки")
            }.tabItem { Label("Каталог", systemImage: "gift.fill") }

            CatchGameView(gifts: store.gifts)
                .tabItem { Label("Игра", systemImage: "gamecontroller.fill") }
        }.tint(.cyan)
    }
}

struct GiftCard: View {
    let gift: Gift
    var body: some View {
        VStack(spacing: 8) {
            GiftAnimationView(filename: gift.filename).frame(height: 126)
                .padding(8).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
            Text("Gift #\(gift.id)").font(.caption.weight(.semibold)).lineLimit(1)
            HStack {
                Label("\(gift.stars ?? 0)", systemImage: "star.fill").foregroundStyle(.yellow)
                Spacer()
                if gift.limited { Text(gift.soldOut ? "Распродан" : "Limited").foregroundStyle(.orange) }
            }.font(.caption2)
        }.padding(10)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }
}

struct GiftDetailView: View {
    let gift: Gift
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                GiftAnimationView(filename: gift.filename).frame(height: 300)
                    .padding(18).background(.cyan.opacity(0.08), in: RoundedRectangle(cornerRadius: 26))
                Text("Telegram Gift").font(.largeTitle.bold())
                Text("ID: \(gift.id)").font(.footnote.monospaced()).foregroundStyle(.secondary)
                Label("\(gift.stars ?? 0) Stars", systemImage: "star.fill").foregroundStyle(.yellow)
                if gift.limited { Text(gift.soldOut ? "Лимитированный · распродан" : "Лимитированный подарок") }
            }.padding()
        }.background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Подарок").navigationBarTitleDisplayMode(.inline)
    }
}

struct GiftAnimationView: View {
    let filename: String
    var body: some View {
        Group {
            // Prefer the bundled PNG so every gift has a reliable visible icon.
            if let url = Bundle.main.url(forResource: filename, withExtension: "png", subdirectory: "Images"),
               let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else if let url = Bundle.main.url(forResource: filename, withExtension: "json", subdirectory: "Animations") {
                LottieView(animation: .filepath(url.path))
                    .playing(loopMode: .loop)
            } else {
                Image(systemName: "gift.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.cyan)
                    .padding(25)
            }
        }
    }
}

struct CatchGameView: View {
    let gifts: [Gift]
    @State private var score = 0
    @State private var seconds = 30
    @State private var running = false
    @State private var current: Gift?
    @State private var collected: [Gift] = []
    @State private var best = UserDefaults.standard.integer(forKey: "giftrush.best")
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                HStack {
                    metric("Очки", "\(score)")
                    metric("Время", "\(seconds)с")
                    metric("Рекорд", "\(best)")
                }
                Text("Поймай подарок").font(.largeTitle.bold())
                Text("Лови анимированные подарки за 30 секунд.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button { catchGift() } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 28).fill(.cyan.opacity(0.09))
                        if let current { GiftAnimationView(filename: current.filename).padding(24) }
                        else { Image(systemName: "gift.fill").font(.system(size: 90)).foregroundStyle(.cyan) }
                    }.frame(height: 260)
                }.buttonStyle(.plain).disabled(!running)
                Button(running ? "Игра идёт…" : "Начать / ещё раунд") { start() }
                    .buttonStyle(.borderedProminent).tint(.cyan).disabled(running || gifts.isEmpty)
                if !collected.isEmpty {
                    Text("Коллекция раунда: \(collected.count)").font(.caption).foregroundStyle(.secondary)
                    ScrollView(.horizontal) {
                        HStack { ForEach(collected) { gift in GiftAnimationView(filename: gift.filename).frame(width: 56, height: 56) } }
                    }.frame(height: 60)
                }
                Spacer()
            }.padding().navigationTitle("Gift Rush")
                .onReceive(timer) { _ in
                    guard running else { return }
                    seconds = max(0, seconds - 1)
                    if seconds == 0 {
                        running = false
                        if score > best { best = score; UserDefaults.standard.set(best, forKey: "giftrush.best") }
                    }
                }
        }
    }
    private func metric(_ name: String, _ value: String) -> some View {
        VStack { Text(name).font(.caption).foregroundStyle(.secondary); Text(value).font(.title2.bold().monospacedDigit()) }
            .frame(maxWidth: .infinity).padding(12)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
    private func start() {
        guard !gifts.isEmpty else { return }
        score = 0; seconds = 30; collected = []; current = gifts.randomElement(); running = true
    }
    private func catchGift() {
        guard running, let gift = current else { return }
        score += 1
        if !collected.contains(gift) { collected.insert(gift, at: 0) }
        current = gifts.randomElement()
    }
}

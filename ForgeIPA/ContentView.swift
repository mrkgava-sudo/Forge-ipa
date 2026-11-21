import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var model = DumperModel()
    @State private var showingImporter = false
    @State private var selectedTab = 0

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header
                        if selectedTab == 0 {
                            Button { showingImporter = true } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: "folder").font(.system(size: 21, weight: .medium))
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("Выбрать IPA").font(.headline)
                                        Text("Открыть файл из приложения «Файлы»").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                                }
                                .padding(16)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                            }
                            .buttonStyle(.plain)
                            .disabled(model.isWorking)

                            if model.isWorking {
                                HStack(spacing: 12) {
                                    ProgressView()
                                    Text(model.status.isEmpty ? "Подготовка файла…" : model.status).font(.subheadline).foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
                            } else if model.report == nil {
                                VStack(spacing: 12) {
                                    Image(systemName: "doc.zipper").font(.system(size: 34, weight: .light)).foregroundStyle(.tint)
                                    Text("Forge IPA").font(.title3.weight(.semibold))
                                    Text("Выберите IPA-файл, чтобы проверить структуру Unity и IL2CPP.")
                                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                                    Text("До 4 ГБ").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity).padding(.vertical, 38).padding(.horizontal, 22)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                            }

                            if let report = model.report { reportCard(report) }
                            if !model.logs.isEmpty {
                                VStack(alignment: .leading, spacing: 9) {
                                    Text("Журнал").font(.headline)
                                    ForEach(Array(model.logs.enumerated()), id: \.offset) { _, line in
                                        Text(line).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }.padding(16).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                            }
                        } else if selectedTab == 1 {
                            if let report = model.report { reportCard(report) }
                            else {
                                VStack(spacing: 10) {
                                    Image(systemName: "chart.bar.xaxis").font(.system(size: 30, weight: .light)).foregroundStyle(.secondary)
                                    Text("Нет результатов").font(.headline)
                                    Text("Сначала выберите IPA на вкладке «Главная».").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity).padding(.vertical, 36)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                Label("Forge IPA", systemImage: "hammer.fill").font(.title2.weight(.semibold))
                                Text("Локальный просмотр структуры IPA, Unity и IL2CPP. Файлы обрабатываются на устройстве.")
                                    .foregroundStyle(.secondary)
                                Label("Импорт файлов до 4 ГБ", systemImage: "doc")
                                Label("Проверка global-metadata.dat", systemImage: "magnifyingglass")
                                Label("Экспорт JSON-отчёта", systemImage: "square.and.arrow.up")
                            }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                        }
                    }.padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 24)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { tabBar }
            .toolbar(.hidden, for: .navigationBar)
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.data, .item], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    model.inspect(url)
                case .failure(let error):
                    model.addLog("Не удалось выбрать файл: \(error.localizedDescription)")
                }
            }
        }
        .tint(.purple)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "hammer.fill")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(.purple)
                .frame(width: 44, height: 44)
                .background(.purple.opacity(0.13), in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 2) {
                Text("Forge IPA").font(.title2.weight(.bold))
                Text("Unity · IL2CPP").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if model.isWorking { ProgressView() }
        }.padding(.vertical, 4)
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            tab("Главная", "house", 0)
            tab("Анализ", "chart.bar", 1)
            tab("О программе", "info.circle", 2)
        }
        .padding(.top, 10).padding(.bottom, 6)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private func tab(_ title: String, _ symbol: String, _ index: Int) -> some View {
        Button { selectedTab = index } label: {
            VStack(spacing: 4) {
                Image(systemName: selectedTab == index ? symbol + ".fill" : symbol)
                    .font(.system(size: 18, weight: .medium))
                Text(title).font(.caption2)
            }
            .foregroundStyle(selectedTab == index ? Color.purple : Color.secondary)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private func reportCard(_ report: DumpReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Результат анализа").font(.headline)
            row("Файл", report.fileName)
            row("Размер", ByteCountFormatter.string(fromByteCount: report.fileSize, countStyle: .file))
            row("Unity / IL2CPP", report.hasUnity ? "Обнаружены" : "Не обнаружены")
            row("Metadata", report.metadataPath ?? "Не найден")
            if let version = report.metadataVersion { row("Версия metadata", String(version)) }
            if !report.sections.isEmpty {
                Divider()
                Text("Секции metadata").font(.subheadline.weight(.semibold))
                ForEach(report.sections) { section in
                    row(section.name, "0x\(String(section.offset, radix: 16)) · \(section.count) bytes")
                }
            }
            Text("Смещения в отчёте относятся к файлу metadata, а не к runtime-адресам методов.")
                .font(.caption2).foregroundStyle(.secondary)
            ShareLink(item: report.exportURL) {
                Label("Экспортировать JSON", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity).padding(12)
                    .background(.purple.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
            }
        }.padding(16).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private func row(_ key: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(key).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value).multilineTextAlignment(.trailing).textSelection(.enabled)
        }.font(.caption)
    }
}

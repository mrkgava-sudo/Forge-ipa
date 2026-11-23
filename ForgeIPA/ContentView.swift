import SwiftUI
import UniformTypeIdentifiers
import UIKit

private enum ForgeStyle {
    static let background = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let surface2 = Color(uiColor: .tertiarySystemGroupedBackground)
    static let line = Color(uiColor: .separator)
    static let text = Color(uiColor: .label)
    static let muted = Color(uiColor: .secondaryLabel)
    static let accent = Color(uiColor: .systemBlue)
    static let cyan = Color(uiColor: .systemTeal)
    static let green = Color(uiColor: .systemGreen)
    static let orange = Color(uiColor: .systemOrange)
}

private extension View {
    @ViewBuilder
    func forgeGlass(cornerRadius: CGFloat = 18) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        #else
        self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        #endif
    }
}

struct ContentView: View {
    @StateObject private var model = DumperModel()
    @State private var selectedTab = 0
    @State private var showingImporter = false
    @State private var showSettings = false

    var body: some View {
        ZStack {
            ForgeStyle.background.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                Group {
                    switch selectedTab {
                    case 0: workspace
                    case 1: analysis
                    case 2: activity
                    default: settings
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                bottomBar
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(isPresented: $showSettings) { settingsSheet }
        .sheet(isPresented: $showingImporter) {
            ForgeDocumentPicker(isPresented: $showingImporter) { result in
                switch result {
                case .success(let url):
                    model.inspect(url)
                case .failure(let error):
                    model.addLog("Импорт: \\(error.localizedDescription)")
                }
            }
            .ignoresSafeArea()
        }
        .preferredColorScheme(nil)
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(ForgeStyle.accent.opacity(0.12))
                Image(systemName: "shippingbox.and.arrow.down.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(ForgeStyle.accent)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 1) {
                Text("Forge IPA")
                    .font(.system(size: 15.3, weight: .semibold))
                    .foregroundStyle(ForgeStyle.text)
                Text("UNITY ANALYSIS")
                    .font(.system(size: 8, weight: .heavy, design: .monospaced))
                    .tracking(1.1)
                    .foregroundStyle(ForgeStyle.muted)
            }
            Spacer()
            if model.isWorking {
                ProgressView().controlSize(.small)
            } else {
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(ForgeStyle.accent)
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel("Настройки")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 5)
        .forgeGlass(cornerRadius: 16)
        .padding(.horizontal, 10)
        .padding(.top, 4)
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            navItem("square.grid.2x2", "Проект", 0)
            navItem("terminal", "Анализ", 1)
            navItem("clock.arrow.circlepath", "Журнал", 2)
            navItem("gearshape", "Настройки", 3)
        }
        .padding(.horizontal, 7)
        .padding(.top, 7)
        .padding(.bottom, 4)
        .forgeGlass(cornerRadius: 20)
        .overlay(alignment: .top) {
            Rectangle().fill(ForgeStyle.line.opacity(0.45)).frame(height: 0.5)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 4)
    }

    private func navItem(_ icon: String, _ title: String, _ index: Int) -> some View {
        Button { selectedTab = index } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 15.3, weight: .regular))
                Text(title)
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(selectedTab == index ? ForgeStyle.accent : ForgeStyle.muted)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var workspace: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 17) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("WORKSPACE")
                        .font(.system(size: 9, weight: .heavy, design: .monospaced))
                        .tracking(1.2)
                        .foregroundStyle(ForgeStyle.muted)
                    Text("Рабочее пространство")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(ForgeStyle.text)
                    Text("Исследуй структуру Unity-приложения.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(ForgeStyle.muted)
                }
                .padding(.top, 12)

                HStack(spacing: 8) {
                    statusChip("Режим", value: "Локально", icon: "iphone")
                    statusChip("Движок", value: "Unity", icon: "cube.transparent")
                    statusChip("Данные", value: "Offline", icon: "lock.fill")
                }

                importCard

                if model.isWorking {
                    progressCard
                } else if let report = model.report {
                    projectSummary(report)
                } else {
                    emptyProject
                }

                HStack(spacing: 10) {
                    metricCard("METADATA", value: model.report?.metadataVersion.map(String.init) ?? "—", icon: "doc.text.magnifyingglass", tint: ForgeStyle.accent)
                    metricCard("OBJECTS", value: model.report.map { String($0.typeCount) } ?? "—", icon: "square.stack.3d.up", tint: ForgeStyle.cyan)
                }

                infoNote
            }
            .padding(.horizontal, 17)
            .padding(.bottom, 20)
        }
    }

    private var importCard: some View {
        Button { showingImporter = true } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("NEW ANALYSIS", systemImage: "plus")
                        .font(.system(size: 9, weight: .heavy, design: .monospaced))
                        .tracking(1)
                        .foregroundStyle(ForgeStyle.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(ForgeStyle.accent.opacity(0.11), in: Capsule())
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(ForgeStyle.text)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Импортировать IPA")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(ForgeStyle.text)
                    Text("Выбери Unity-приложение в приложении «Файлы»")
                        .font(.system(size: 10.5))
                        .foregroundStyle(ForgeStyle.muted)
                        .multilineTextAlignment(.leading)
                }
                HStack(spacing: 8) {
                    Image(systemName: "folder")
                    Text("Выбрать файл")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(0.8)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 15)
                .padding(.vertical, 10)
                .background(ForgeStyle.accent, in: Capsule())
            }
            .padding(17)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ForgeStyle.surface2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(ForgeStyle.accent.opacity(0.18), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(model.isWorking)

    }

    private var emptyProject: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "doc.zipper")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(ForgeStyle.accent)
                    .frame(width: 42, height: 42)
                    .background(ForgeStyle.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Нет открытого проекта")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ForgeStyle.text)
                    Text("Импортируй IPA, чтобы начать анализ.")
                        .font(.system(size: 10))
                        .foregroundStyle(ForgeStyle.muted)
                }
                Spacer()
            }
        }
        .padding(15)
        .forgeGlass(cornerRadius: 13)
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text("ВЫПОЛНЯЕТСЯ АНАЛИЗ")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .tracking(0.9)
                    .foregroundStyle(ForgeStyle.accent)
                Spacer()
                ProgressView().controlSize(.small)
            }
            Text(model.status.isEmpty ? "Подготовка файла…" : model.status)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ForgeStyle.text)
            ProgressView()
                .tint(ForgeStyle.accent)
        }
        .padding(15)
        .forgeGlass(cornerRadius: 13)
    }

    private func projectSummary(_ report: DumpReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionTitle("Последний проект")
                Spacer()
                Label("ГОТОВО", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 8, weight: .heavy, design: .monospaced))
                    .foregroundStyle(ForgeStyle.green)
            }
            HStack(spacing: 11) {
                Image(systemName: "app.dashed")
                    .font(.system(size: 19))
                    .foregroundStyle(ForgeStyle.accent)
                    .frame(width: 44, height: 44)
                    .background(ForgeStyle.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Text(report.fileName)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(ForgeStyle.text)
                        .lineLimit(2)
                    Text(ByteCountFormatter.string(fromByteCount: report.fileSize, countStyle: .file))
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(ForgeStyle.muted)
                }
                Spacer(minLength: 0)
            }
            Divider()
            summaryLine("Unity", value: report.hasUnity ? "Обнаружен" : "Не подтверждён")
            summaryLine("Metadata", value: report.metadataPath == nil ? "Не найден" : "Найден")
            summaryLine("Native binary", value: report.nativeBinaryPath ?? "Не найден")
            summaryLine("Типов", value: String(report.typeCount))
            summaryLine("Методов", value: String(report.methodCount))
            summaryLine("Полей", value: String(report.fieldCount))
            summaryLine("Смещения полей", value: "\(report.resolvedFieldOffsetCount) / \(report.fieldCount)")
            summaryLine("RVA методов", value: String(report.resolvedMethodRvaCount))
            Button { selectedTab = 1 } label: {
                HStack {
                    Text("Открыть результаты")
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ForgeStyle.accent)
                .padding(.top, 3)
            }
            .buttonStyle(.plain)
        }
        .padding(15)
        .forgeGlass(cornerRadius: 13)
    }

    private var analysis: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                pageHeading("Анализ", subtitle: "Структура IPA и найденные компоненты.")
                if let report = model.report {
                    VStack(alignment: .leading, spacing: 12) {
                        sectionTitle("Сводка IPA")
                        summaryLine("Файл", value: report.fileName)
                        summaryLine("Размер", value: ByteCountFormatter.string(fromByteCount: report.fileSize, countStyle: .file))
                        summaryLine("Unity", value: report.hasUnity ? "Обнаружен" : "Не подтверждён")
                        summaryLine("Metadata", value: report.metadataPath ?? "Не найден")
                        summaryLine("Native binary", value: report.nativeBinaryPath ?? "Не найден")
                        summaryLine("Версия metadata", value: report.metadataVersion.map(String.init) ?? "—")
                        summaryLine("Типов", value: String(report.typeCount))
                        summaryLine("Методов", value: String(report.methodCount))
                        summaryLine("Полей", value: String(report.fieldCount))
                        summaryLine("Смещения полей", value: "\(report.resolvedFieldOffsetCount) / \(report.fieldCount)")
                        summaryLine("RVA методов", value: String(report.resolvedMethodRvaCount))
                    }
                    .padding(15)
                    .forgeGlass(cornerRadius: 13)

                    VStack(alignment: .leading, spacing: 10) {
                        sectionTitle("Секции metadata")
                        if report.sections.isEmpty {
                            Text("Секции не распознаны. Возможно, версия metadata отличается от поддерживаемого формата.")
                                .font(.system(size: 11))
                                .foregroundStyle(ForgeStyle.muted)
                        } else {
                            ForEach(report.sections) { item in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name).font(.system(size: 10.5, weight: .medium)).foregroundStyle(ForgeStyle.text)
                                        Text("offset 0x\(String(item.offset, radix: 16))")
                                            .font(.system(size: 8.5, design: .monospaced))
                                            .foregroundStyle(ForgeStyle.muted)
                                    }
                                    Spacer()
                                    Text(ByteCountFormatter.string(fromByteCount: Int64(item.count), countStyle: .memory))
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundStyle(ForgeStyle.muted)
                                }
                                if item.id != report.sections.last?.id { Divider() }
                            }
                        }
                    }
                    .padding(15)
                    .forgeGlass(cornerRadius: 13)

                    if let dumpURL = report.dumpURL {
                        ShareLink(item: dumpURL) {
                            Label("Экспортировать dump.cs", systemImage: "doc.text")
                                .font(.system(size: 11, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(13)
                                .background(ForgeStyle.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    ShareLink(item: report.exportURL) {
                        Label("Экспортировать JSON-отчёт", systemImage: "square.and.arrow.up")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(13)
                            .background(ForgeStyle.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    }
                } else {
                    emptyState(icon: "waveform.path.ecg", title: "Результатов пока нет", detail: "Импортируй IPA на вкладке «Проект», чтобы начать.")
                }
                infoNote
            }
            .padding(.horizontal, 17)
            .padding(.bottom, 20)
        }
    }

    private var activity: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 15) {
                pageHeading("Журнал", subtitle: "События импорта и обработки файлов.")
                if model.logs.isEmpty {
                    emptyState(icon: "text.alignleft", title: "Журнал пуст", detail: "Здесь появятся сообщения о ходе анализа и ошибках.")
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(model.logs.enumerated()), id: \.offset) { index, line in
                            HStack(alignment: .top, spacing: 10) {
                                Circle()
                                    .fill(index == 0 ? ForgeStyle.accent : ForgeStyle.muted.opacity(0.5))
                                    .frame(width: 6, height: 6)
                                    .padding(.top, 5)
                                Text(line)
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(ForgeStyle.text)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.vertical, 10)
                            if index != model.logs.count - 1 { Divider() }
                        }
                    }
                    .padding(.horizontal, 14)
                    .forgeGlass(cornerRadius: 13)
                }
            }
            .padding(.horizontal, 17)
            .padding(.top, 12)
            .padding(.bottom, 20)
        }
    }

    private var settings: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 15) {
                pageHeading("Настройки", subtitle: "Параметры рабочего пространства.")
                VStack(spacing: 0) {
                    settingRow("Версия интерфейса", value: "FORGE / 2.0")
                    Divider().padding(.leading, 14)
                    settingRow("Обработка файлов", value: "На устройстве")
                    Divider().padding(.leading, 14)
                    settingRow("Поддержка", value: "Unity / IL2CPP")
                    Divider().padding(.leading, 14)
                    settingRow("Минимальная iOS", value: "iOS 16")
                }
                .padding(.horizontal, 14)
                .forgeGlass(cornerRadius: 13)
                VStack(alignment: .leading, spacing: 7) {
                    sectionTitle("О проекте")
                    Text("Forge IPA анализирует содержимое выбранного IPA локально. Отчёт metadata не является исходным кодом приложения и не содержит автоматически восстановленные методы, если они ещё не разобраны парсером.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(ForgeStyle.muted)
                }
                .padding(15)
                .forgeGlass(cornerRadius: 13)
            }
            .padding(.horizontal, 17)
            .padding(.top, 12)
            .padding(.bottom, 20)
        }
    }

    private var infoNote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(ForgeStyle.orange)
            Text("dump.cs строится из таблиц metadata. Типы полей и параметров, реальные смещения и RVA требуют отдельного разбора native IL2CPP registration.")
                .font(.system(size: 9.5))
                .foregroundStyle(ForgeStyle.muted)
        }
        .padding(.horizontal, 2)
    }

    private var settingsSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Настройки").font(.system(size: 20, weight: .bold))
                    Text("Параметры Forge IPA").font(.system(size: 11)).foregroundStyle(ForgeStyle.muted)
                }
                Spacer()
                Button("Готово") { showSettings = false }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ForgeStyle.accent)
            }
            settingRow("Обработка", value: "Локально")
            settingRow("Платформа", value: "iOS")
            settingRow("Фокус", value: "Unity IL2CPP")
            Spacer()
        }
        .padding(22)
        .background(ForgeStyle.background.ignoresSafeArea())
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func pageHeading(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 26, weight: .bold)).foregroundStyle(ForgeStyle.text)
            Text(subtitle).font(.system(size: 12)).foregroundStyle(ForgeStyle.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 12)
    }

    private func statusChip(_ title: String, value: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 9, weight: .bold))
            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased()).font(.system(size: 7, weight: .heavy, design: .monospaced)).tracking(0.6)
                Text(value).font(.system(size: 8, weight: .bold, design: .monospaced)).lineLimit(1)
            }
        }
        .foregroundStyle(ForgeStyle.text)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 9)
        .forgeGlass(cornerRadius: 11)
    }

    private func metricCard(_ title: String, value: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Image(systemName: icon).font(.system(size: 12, weight: .semibold)).foregroundStyle(tint)
                Spacer()
                Circle().fill(tint).frame(width: 5, height: 5)
            }
            Text(value).font(.system(size: 21, weight: .bold)).foregroundStyle(ForgeStyle.text)
            Text(title).font(.system(size: 8, weight: .heavy, design: .monospaced)).tracking(0.9).foregroundStyle(ForgeStyle.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .forgeGlass(cornerRadius: 12)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.system(size: 12, weight: .bold)).foregroundStyle(ForgeStyle.text)
    }

    private func summaryLine(_ title: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(title).foregroundStyle(ForgeStyle.muted)
            Spacer(minLength: 8)
            Text(value).foregroundStyle(ForgeStyle.text).multilineTextAlignment(.trailing).textSelection(.enabled)
        }
        .font(.system(size: 10.5))
    }

    private func settingRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(ForgeStyle.muted)
            Spacer()
            Text(value).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(ForgeStyle.text)
        }
        .padding(.vertical, 13)
    }

    private func emptyState(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 29, weight: .light)).foregroundStyle(ForgeStyle.accent)
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(ForgeStyle.text)
            Text(detail).font(.system(size: 10.5)).foregroundStyle(ForgeStyle.muted).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 18)
        .forgeGlass(cornerRadius: 14)
    }
}

private struct ForgeDocumentPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let completion: (Result<URL, Error>) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.data], asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: ForgeDocumentPicker
        var isPresented = false

        init(parent: ForgeDocumentPicker) { self.parent = parent }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            isPresented = false
            parent.isPresented = false
            guard let url = urls.first else {
                parent.completion(.failure(ImportError.noFileSelected))
                return
            }
            guard url.pathExtension.lowercased() == "ipa" else {
                parent.completion(.failure(ImportError.invalidFileType))
                return
            }
            parent.completion(.success(url))
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            isPresented = false
            parent.isPresented = false
        }
    }

    enum ImportError: LocalizedError {
        case noFileSelected
        case invalidFileType
        var errorDescription: String? {
            switch self {
            case .noFileSelected: return "Файл не был выбран."
            case .invalidFileType: return "Выбери файл с расширением .ipa."
            }
        }
    }
}

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var model = DumperModel()
    @State private var showingImporter = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.035, green: 0.025, blue: 0.07).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 18) {
                        header
                        Button { showingImporter = true } label: {
                            Label("Выбрать IPA", systemImage: "tray.and.arrow.down.fill")
                                .font(.headline).frame(maxWidth: .infinity).padding()
                                .background(LinearGradient(colors: [.purple, Color(red: 0.42, green: 0.12, blue: 0.9)], startPoint: .leading, endPoint: .trailing))
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        .disabled(model.isWorking)
                        HStack {
                            stat("Лимит IPA", "4 ГБ", "externaldrive")
                            stat("Обработка", "Локально", "iphone")
                            stat("Движок", "Unity", "cube")
                        }
                        .padding(.vertical, 4)
                        if model.isWorking {
                            ProgressView().tint(.purple)
                            Text(model.status).font(.subheadline).foregroundStyle(.white.opacity(0.8))
                        }
                        if let report = model.report {
                            reportCard(report)
                        }
                        if !model.logs.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("ЖУРНАЛ").font(.caption.bold()).foregroundStyle(.purple)
                                ForEach(Array(model.logs.enumerated()), id: \.offset) { _, line in
                                    Text(line).font(.system(.caption, design: .monospaced)).foregroundStyle(.white.opacity(0.72)).frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }.padding().background(.white.opacity(0.05)).clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    }.padding()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls): if let url = urls.first { model.inspect(url) }
                case .failure(let error): model.addLog("Ошибка выбора: \(error.localizedDescription)")
                }
            }
        }.preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "hammer.circle.fill").font(.system(size: 58)).foregroundStyle(.purple)
            Text("FORGE IPA").font(.system(size: 28, weight: .black, design: .rounded)).tracking(2)
            Text("UNITY • IL2CPP INSPECTOR").font(.caption2.weight(.bold)).tracking(2).foregroundStyle(.purple)
        }.padding(.top, 24).padding(.bottom, 12)
    }

    private func stat(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(.purple)
            Text(value).font(.footnote.bold())
            Text(title).font(.caption2).foregroundStyle(.white.opacity(0.55))
        }.frame(maxWidth: .infinity).padding(.vertical, 12).background(.white.opacity(0.05)).clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func reportCard(_ report: DumpReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("РЕЗУЛЬТАТ АНАЛИЗА").font(.caption.bold()).foregroundStyle(.purple)
            row("Файл", report.fileName)
            row("Размер", ByteCountFormatter.string(fromByteCount: report.fileSize, countStyle: .file))
            row("Unity / IL2CPP", report.hasUnity ? "Обнаружены признаки Unity" : "Не обнаружено")
            row("Metadata", report.metadataPath ?? "Не найден")
            if let version = report.metadataVersion { row("Metadata version", String(version)) }
            if !report.sections.isEmpty {
                Divider().overlay(.white.opacity(0.15))
                Text("Секции metadata").font(.subheadline.bold())
                ForEach(report.sections, id: \.name) { section in
                    row(section.name, "offset 0x\(String(section.offset, radix: 16)) • \(section.count) bytes")
                }
            }
            Text("Offsets в отчёте — смещения секций файла metadata, не runtime offsets адресов методов.").font(.caption2).foregroundStyle(.orange)
            ShareLink(item: report.exportURL) {
                Label("Экспорт JSON-отчёта", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity).padding(12).background(.purple.opacity(0.25)).clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }.padding().background(.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func row(_ key: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(key).foregroundStyle(.white.opacity(0.55))
            Spacer(minLength: 8)
            Text(value).multilineTextAlignment(.trailing).textSelection(.enabled)
        }.font(.caption)
    }
}

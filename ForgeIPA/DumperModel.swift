import Foundation
import ZIPFoundation

struct MetadataSection: Codable, Identifiable {
    var id: String { name }
    let name: String
    let offset: UInt32
    let count: UInt32
}

struct DumpReport: Encodable {
    let fileName: String
    let fileSize: Int64
    let hasUnity: Bool
    let metadataPath: String?
    let metadataVersion: UInt32?
    let sections: [MetadataSection]
    let analyzedAt: Date
    let exportURL: URL
    enum CodingKeys: String, CodingKey {
        case fileName, fileSize, hasUnity, metadataPath, metadataVersion, sections, analyzedAt
    }
}

@MainActor
final class DumperModel: ObservableObject {
    @Published var isWorking = false
    @Published var status = ""
    @Published var report: DumpReport?
    @Published var logs: [String] = []
    private let maxIPABytes: Int64 = 4 * 1024 * 1024 * 1024

    func addLog(_ value: String) {
        logs.insert(value, at: 0)
        if logs.count > 80 { logs.removeLast() }
    }

    func inspect(_ source: URL) {
        guard !isWorking else { return }
        isWorking = true
        report = nil
        logs.removeAll()
        status = "Получение доступа к файлу…"
        let hasScope = source.startAccessingSecurityScopedResource()
        Task.detached(priority: .userInitiated) { [weak self] in
            defer { if hasScope { source.stopAccessingSecurityScopedResource() } }
            do {
                let staged = FileManager.default.temporaryDirectory
                    .appendingPathComponent("ForgeIPA-Input-\(UUID().uuidString).ipa")
                let coordinator = NSFileCoordinator(filePresenter: nil)
                var coordinationError: NSError?
                var copyError: Error?
                coordinator.coordinate(readingItemAt: source, options: [], error: &coordinationError) { readableURL in
                    do { try FileManager.default.copyItem(at: readableURL, to: staged) }
                    catch { copyError = error }
                }
                if let coordinationError { throw coordinationError }
                if let copyError { throw copyError }
                await self?.addLog("Файл скопирован в локальное хранилище приложения.")
                await self?.runInspection(staged)
                try? FileManager.default.removeItem(at: staged)
            } catch {
                await self?.addLog("Не удалось прочитать файл. Если он в iCloud, сначала дождитесь загрузки в «Файлах». Детали: \(error.localizedDescription)")
                await self?.finishWithError()
            }
        }
    }

    private func finishWithError() {
        isWorking = false
        status = "Не удалось открыть файл"
    }

    private func runInspection(_ source: URL) async {
        defer { isWorking = false }
        do {
            let values = try source.resourceValues(forKeys: [.fileSizeKey])
            let size = Int64(values.fileSize ?? 0)
            guard size > 0, size <= maxIPABytes else {
                addLog("Файл пустой или превышает лимит 4 ГБ.")
                status = "Файл не подходит"
                return
            }
            status = "Подготовка локальной распаковки…"
            addLog("Открыт файл: \(source.lastPathComponent)")
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("ForgeIPA-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            guard let archive = Archive(url: source, accessMode: .read) else {
                addLog("Не удалось открыть ZIP/IPA архив.")
                status = "Повреждённый архив"
                return
            }
            var foundMetadata: URL?
            var hasUnity = false
            var processed = 0
            let rootPath = root.standardizedFileURL.path + "/"
            for entry in archive {
                let destination = root.appendingPathComponent(entry.path).standardizedFileURL
                guard destination.path.hasPrefix(rootPath) else {
                    addLog("Архив содержит недопустимый путь: \(entry.path)")
                    continue
                }
                if entry.type == .directory {
                    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                    continue
                }
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                _ = try archive.extract(entry, to: destination, skipCRC32: false)
                processed += 1
                let lower = entry.path.lowercased()
                if lower.contains("unityframework") || lower.contains("unityplayer") || lower.contains("data/globalgamemanagers") { hasUnity = true }
                if lower.hasSuffix("global-metadata.dat") { foundMetadata = destination }
                if processed % 100 == 0 { status = "Обработано объектов: \(processed)" }
            }
            addLog("Распаковка завершена. Объектов: \(processed)")
            var version: UInt32?
            var sections: [MetadataSection] = []
            if let metadata = foundMetadata {
                (version, sections) = try parseMetadata(metadata)
                addLog("Найден global-metadata.dat")
            } else { addLog("global-metadata.dat не найден") }
            let export = FileManager.default.temporaryDirectory.appendingPathComponent("ForgeIPA-Report-\(UUID().uuidString).json")
            let draft = DumpReport(fileName: source.lastPathComponent, fileSize: size, hasUnity: hasUnity, metadataPath: foundMetadata?.lastPathComponent, metadataVersion: version, sections: sections, analyzedAt: Date(), exportURL: export)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(draft).write(to: export, options: .atomic)
            report = draft
            status = "Анализ завершён"
            addLog("Отчёт JSON создан.")
        } catch {
            addLog("Ошибка анализа: \(error.localizedDescription)")
            status = "Анализ прерван"
        }
    }

    private func parseMetadata(_ url: URL) throws -> (UInt32?, [MetadataSection]) {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 8 * 1024) ?? Data()
        guard data.count >= 8 else { throw CocoaError(.fileReadCorruptFile) }
        func u32(_ offset: Int) -> UInt32 {
            UInt32(data[offset]) | (UInt32(data[offset + 1]) << 8) | (UInt32(data[offset + 2]) << 16) | (UInt32(data[offset + 3]) << 24)
        }
        guard u32(0) == 0xFAB11BAF else { throw CocoaError(.fileReadCorruptFile) }
        let version = u32(4)
        let names = ["StringLiteral", "StringLiteralData", "String", "Events", "Properties", "Methods", "ParameterDefaultValues", "FieldDefaultValues", "DefaultValues", "FieldMarshaledSizes", "Parameters", "Fields", "GenericParameters", "GenericParameterConstraints", "GenericContainers", "NestedTypes", "Interfaces", "VTables", "InterfaceOffsets", "TypeDefinitions", "Images", "Assemblies", "FieldRefs", "ReferencedAssemblies", "AttributeInfo", "AttributeTypes", "UnresolvedVirtualCallParameterTypes", "UnresolvedVirtualCallParameterRanges", "WindowsRuntimeTypeNames", "WindowsRuntimeStrings", "ExportedTypeDefinitions"]
        var result: [MetadataSection] = []
        for (index, name) in names.enumerated() {
            let position = 8 + index * 8
            guard position + 8 <= data.count else { break }
            let offset = u32(position)
            let count = u32(position + 4)
            if offset > 0 || count > 0 { result.append(MetadataSection(name: name, offset: offset, count: count)) }
        }
        return (version, result)
    }
}

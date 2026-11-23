import Foundation
import Combine
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
    let engineName: String
    let hasUnity: Bool
    let ue4MarkerCount: Int
    let metadataPath: String?
    let nativeBinaryPath: String?
    let metadataVersion: UInt32?
    let sections: [MetadataSection]
    let typeCount: Int
    let methodCount: Int
    let fieldCount: Int
    let resolvedFieldOffsetCount: Int
    let resolvedMethodRvaCount: Int
    let dumpURL: URL?
    let analyzedAt: Date
    let exportURL: URL

    enum CodingKeys: String, CodingKey {
        case fileName, fileSize, engineName, hasUnity, ue4MarkerCount, metadataPath, nativeBinaryPath, metadataVersion, sections
        case typeCount, methodCount, fieldCount, resolvedFieldOffsetCount, resolvedMethodRvaCount, analyzedAt
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
                await self?.addLog("Выбранный IPA скопирован в локальное хранилище.")
                await self?.runInspection(staged)
                try? FileManager.default.removeItem(at: staged)
            } catch {
                await self?.addLog("Не удалось прочитать выбранный файл: \(error.localizedDescription)")
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
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("ForgeIPA-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }

            let archive = try Archive(url: source, accessMode: .read)

            var foundMetadata: URL?
            var foundNativeBinary: URL?
            var foundUE4Binary: URL?
            var archivePaths: [String] = []
            var hasUnity = false
            var processed = 0
            let rootPath = root.standardizedFileURL.path + "/"

            for entry in archive {
                archivePaths.append(entry.path)
                let lower = entry.path.lowercased()
                if lower.contains("unityframework") || lower.contains("unityplayer") || lower.contains("data/globalgamemanagers") {
                    hasUnity = true
                }
                let isMetadata = lower.hasSuffix("global-metadata.dat")
                let isNativeBinary = lower.hasSuffix("/unityframework") ||
                    lower.hasSuffix("/unityplayer") ||
                    lower.hasSuffix("/libil2cpp") ||
                    lower.hasSuffix("/libil2cpp.dylib") ||
                    lower.hasSuffix("/il2cpp")
                let pathParts = entry.path.split(separator: "/")
                let appIndex = pathParts.firstIndex(where: { $0.lowercased().hasSuffix(".app") })
                let isMainAppExecutable = appIndex.map { index in
                    pathParts.count == index + 2 &&
                    URL(fileURLWithPath: entry.path).pathExtension.isEmpty &&
                    !pathParts.last!.lowercased().hasSuffix(".plist")
                } ?? false
                let namedUE4Binary = lower.contains("shadowtrackerextra") ||
                    lower.contains("ue4game") || lower.contains("libue4")
                let isUE4Candidate = isMainAppExecutable || namedUE4Binary
                guard isMetadata || isNativeBinary || isUE4Candidate else { continue }
                guard entry.type == .file else { continue }

                let destination = root.appendingPathComponent(entry.path).standardizedFileURL
                guard destination.path.hasPrefix(rootPath) else {
                    addLog("Пропущен недопустимый путь внутри архива: \(entry.path)")
                    continue
                }
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                _ = try archive.extract(entry, to: destination, skipCRC32: false)
                processed += 1
                if isMetadata { foundMetadata = destination }
                if isNativeBinary { foundNativeBinary = destination }
                if isUE4Candidate && !isNativeBinary && (foundUE4Binary == nil || namedUE4Binary) { foundUE4Binary = destination }
                status = isMetadata ? "Metadata извлечён" : (isNativeBinary ? "Найден Unity-бинарник" : "Найден исполняемый файл приложения")
            }

            addLog("Извлечено целевых файлов: \(processed)")
            if let native = foundNativeBinary {
                addLog("Найден нативный бинарник: \(native.lastPathComponent)")
                do {
                    let image = try MachOInspector.inspect(native)
                    addLog("Mach-O разобран: \(image.architecture), сегментов: \(image.segments.count), секций: \(image.sections.count).")
                    let dataSections = image.sections.filter {
                        $0.segment == "__DATA" || $0.segment == "__DATA_CONST" || $0.segment == "__TEXT"
                    }.prefix(10)
                    for section in dataSections {
                        addLog("Секция \(section.segment),\(section.name): VA 0x\(String(section.virtualAddress, radix: 16)), size 0x\(String(section.size, radix: 16)).")
                    }
                } catch {
                    addLog("Не удалось разобрать Mach-O: \(error.localizedDescription)")
                }
            } else {
                addLog("Нативный Unity-бинарник не найден по стандартным именам.")
            }

            var version: UInt32?
            var engineName = "Не определён"
            var ue4MarkerCount = 0
            var sections: [MetadataSection] = []
            var dumpURL: URL?
            var typeCount = 0
            var methodCount = 0
            var fieldCount = 0
            var resolvedFieldOffsetCount = 0
            var resolvedMethodRvaCount = 0

            if let metadata = foundMetadata {
                addLog("Найден global-metadata.dat")
                do {
                    let dumpFolder = FileManager.default.temporaryDirectory
                        .appendingPathComponent("ForgeIPA-Dump-\(UUID().uuidString)", isDirectory: true)
                    let generated = try IL2CPPMetadataDumper.generate(from: metadata, nativeBinaryURL: foundNativeBinary, outputDirectory: dumpFolder)
                    version = generated.version
                    sections = generated.sections
                    dumpURL = generated.dumpURL
                    typeCount = generated.typeCount
                    methodCount = generated.methodCount
                    fieldCount = generated.fieldCount
                    resolvedFieldOffsetCount = generated.resolvedFieldOffsetCount
                    resolvedMethodRvaCount = generated.resolvedMethodRvaCount
                    if resolvedFieldOffsetCount > 0 {
                        addLog("Разрешены реальные смещения полей: \(resolvedFieldOffsetCount).")
                    }
                    if resolvedMethodRvaCount > 0 {
                        addLog("Восстановлены адреса методов RVA: \(resolvedMethodRvaCount).")
                    }
                    addLog("Создан dump.cs: \(typeCount) типов, \(fieldCount) полей, \(methodCount) методов.")
                } catch {
                    addLog("Генератор dump.cs не смог разобрать эту версию metadata: \(error.localizedDescription)")
                    (version, sections) = try parseMetadataHeader(metadata)
                }
            } else if let ue4Binary = foundUE4Binary {
                addLog("Unity metadata не найдено. Проверяю исполняемый файл на признаки Unreal Engine.")
                do {
                    let ue4Folder = FileManager.default.temporaryDirectory
                        .appendingPathComponent("ForgeIPA-UE4-\(UUID().uuidString)", isDirectory: true)
                    let result = try UE4StaticAnalyzer.analyze(
                        binaryURL: ue4Binary,
                        ipaEntryPaths: archivePaths,
                        outputDirectory: ue4Folder
                    )
                    engineName = result.detected ? "Unreal Engine 4 (признаки найдены)" : "UE4 не подтверждён"
                    ue4MarkerCount = result.markers.reduce(0) { $0 + $1.fileOffsets.count }
                    dumpURL = result.reportURL
                    addLog("UE4 Mach-O разобран: \(result.architecture), секций: \(result.sections.count).")
                    addLog("Групп маркеров: \(result.markers.count), совпадений строк: \(ue4MarkerCount).")
                    addLog("Ресурсы Unreal: " + (result.packageInventory.isEmpty ? "не найдены" : result.packageInventory.map { "\($0.key): \($0.value)" }.sorted().joined(separator: ", ")))
                    addLog("Создан UE4 static analysis report. Это не runtime UObject dump.")
                } catch {
                    engineName = "Возможный UE4 — анализ не завершён"
                    addLog("UE4-анализатор: \(error.localizedDescription)")
                }
            } else {
                addLog("global-metadata.dat и подходящий UE4 executable не найдены")
            }

            if engineName == "Не определён" {
                engineName = hasUnity ? "Unity / IL2CPP" : "Не определён"
            }

            let export = FileManager.default.temporaryDirectory
                .appendingPathComponent("ForgeIPA-Report-\(UUID().uuidString).json")
            let draft = DumpReport(
                fileName: source.lastPathComponent,
                fileSize: size,
                engineName: engineName,
                hasUnity: hasUnity,
                ue4MarkerCount: ue4MarkerCount,
                metadataPath: foundMetadata?.lastPathComponent,
                nativeBinaryPath: (foundNativeBinary ?? foundUE4Binary)?.lastPathComponent,
                metadataVersion: version,
                sections: sections,
                typeCount: typeCount,
                methodCount: methodCount,
                fieldCount: fieldCount,
                resolvedFieldOffsetCount: resolvedFieldOffsetCount,
                resolvedMethodRvaCount: resolvedMethodRvaCount,
                dumpURL: dumpURL,
                analyzedAt: Date(),
                exportURL: export
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(draft).write(to: export, options: .atomic)
            report = draft
            status = dumpURL == nil ? "Анализ завершён" : (engineName.contains("Unreal") || engineName.contains("UE4") ? "UE4-отчёт создан" : "dump.cs создан")
            addLog(dumpURL == nil ? "Создан JSON-отчёт. Файл полного дампа не сформирован." : "Файлы анализа и JSON готовы к экспорту.")
        } catch {
            addLog("Ошибка анализа: \(error.localizedDescription)")
            status = "Анализ прерван"
        }
    }

    private func parseMetadataHeader(_ url: URL) throws -> (UInt32?, [MetadataSection]) {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 8 * 1024) ?? Data()
        guard data.count >= 8 else { throw CocoaError(.fileReadCorruptFile) }

        func u32(_ offset: Int) -> UInt32 {
            UInt32(data[offset]) | (UInt32(data[offset + 1]) << 8) |
            (UInt32(data[offset + 2]) << 16) | (UInt32(data[offset + 3]) << 24)
        }
        guard u32(0) == 0xFAB11BAF else { throw CocoaError(.fileReadCorruptFile) }
        let version = u32(4)
        let names = [
            "StringLiteral", "StringLiteralData", "String", "Events", "Properties", "Methods",
            "ParameterDefaultValues", "FieldDefaultValues", "DefaultValues", "FieldMarshaledSizes",
            "Parameters", "Fields", "GenericParameters", "GenericParameterConstraints", "GenericContainers",
            "NestedTypes", "Interfaces", "VTables", "InterfaceOffsets", "TypeDefinitions", "Images",
            "Assemblies", "FieldRefs", "ReferencedAssemblies", "AttributeInfo", "AttributeTypes",
            "UnresolvedVirtualCallParameterTypes", "UnresolvedVirtualCallParameterRanges",
            "WindowsRuntimeTypeNames", "WindowsRuntimeStrings", "ExportedTypeDefinitions"
        ]
        var result: [MetadataSection] = []
        for (index, name) in names.enumerated() {
            let position = 8 + index * 8
            guard position + 8 <= data.count else { break }
            let offset = u32(position)
            let size = u32(position + 4)
            if offset > 0 || size > 0 {
                result.append(MetadataSection(name: name, offset: offset, count: size))
            }
        }
        return (version, result)
    }
}

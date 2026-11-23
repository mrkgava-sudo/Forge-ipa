import Foundation

struct IL2CPPMetadataDumpResult {
    let version: UInt32
    let sections: [MetadataSection]
    let dumpURL: URL
    let typeCount: Int
    let methodCount: Int
    let fieldCount: Int
}

/// Metadata-side IL2CPP dumper. It reconstructs declarations that are actually
/// present in global-metadata.dat. Native type resolution, field offsets and
/// method RVAs require the matching Mach-O registration and are not fabricated.
enum IL2CPPMetadataDumper {
    private struct Section {
        let offset: Int
        let size: Int
    }

    private struct TypeDefinition {
        let name: String
        let namespace: String
        let parent: Int32
        let fieldStart: Int32
        let methodStart: Int32
        let methodCount: Int
        let fieldCount: Int
        let isValueType: Bool
        let isEnum: Bool
    }

    private struct MethodDefinition {
        let name: String
        let parameterStart: Int32
        let parameterCount: Int
        let flags: UInt16
    }

    private struct FieldDefinition {
        let name: String
    }

    static func generate(from metadataURL: URL, outputDirectory: URL) throws -> IL2CPPMetadataDumpResult {
        let data = try Data(contentsOf: metadataURL, options: [.mappedIfSafe])
        guard data.count >= 256 else { throw DumpError.invalidMetadata("Файл metadata слишком короткий.") }

        func u16(_ offset: Int) throws -> UInt16 {
            guard offset >= 0, offset + 2 <= data.count else { throw DumpError.invalidMetadata("Выход за границы metadata.") }
            return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
        }
        func u32(_ offset: Int) throws -> UInt32 {
            guard offset >= 0, offset + 4 <= data.count else { throw DumpError.invalidMetadata("Выход за границы metadata.") }
            return UInt32(data[offset]) | (UInt32(data[offset + 1]) << 8) | (UInt32(data[offset + 2]) << 16) | (UInt32(data[offset + 3]) << 24)
        }
        func i32(_ offset: Int) throws -> Int32 { Int32(bitPattern: try u32(offset)) }

        guard try u32(0) == 0xFAB11BAF else { throw DumpError.invalidMetadata("Сигнатура global-metadata.dat не совпадает.") }
        let version = try u32(4)
        guard (27...29).contains(version) else {
            throw DumpError.unsupportedVersion(version)
        }

        // GlobalMetadataHeader is a sequence of (offset, byte-size) pairs.
        // These indices are stable for metadata versions 27–29.
        var sections: [Section] = []
        for index in 0..<32 {
            let pairOffset = 8 + index * 8
            guard pairOffset + 8 <= data.count else { break }
            let rawOffset = try u32(pairOffset)
            let rawSize = try u32(pairOffset + 4)
            let offset = Int(rawOffset)
            let size = Int(rawSize)
            if size > 0 {
                guard offset >= 0, offset <= data.count, size <= data.count - offset else {
                    throw DumpError.invalidMetadata("Секция metadata #\(index) выходит за пределы файла.")
                }
            }
            sections.append(Section(offset: offset, size: size))
        }
        func section(_ index: Int) throws -> Section {
            guard index < sections.count else { throw DumpError.invalidMetadata("В заголовке отсутствует секция #\(index).") }
            return sections[index]
        }

        let stringSection = try section(2)
        func stringAt(_ index: Int32) -> String {
            guard index >= 0 else { return "" }
            let start = stringSection.offset + Int(index)
            guard start >= stringSection.offset, start < stringSection.offset + stringSection.size else { return "" }
            var end = start
            let limit = stringSection.offset + stringSection.size
            while end < limit, data[end] != 0 { end += 1 }
            return String(data: data[start..<end], encoding: .utf8) ?? ""
        }

        let typeSection = try section(19)
        let methodSection = try section(5)
        let fieldSection = try section(11)
        let parameterSection = try section(10)

        let typeStride = 88       // Il2CppTypeDefinition, metadata 27–29
        let methodStride = 32     // Il2CppMethodDefinition, metadata 27–29
        let fieldStride = 12      // Il2CppFieldDefinition, metadata 27–29
        let parameterStride = 12 // Il2CppParameterDefinition, metadata 27–29

        guard typeSection.size % typeStride == 0,
              methodSection.size % methodStride == 0,
              fieldSection.size % fieldStride == 0,
              parameterSection.size % parameterStride == 0 else {
            throw DumpError.invalidMetadata("Размеры таблиц не соответствуют структурам metadata 27–29.")
        }

        let typeCount = typeSection.size / typeStride
        let methodCount = methodSection.size / methodStride
        let fieldCount = fieldSection.size / fieldStride
        let parameterCount = parameterSection.size / parameterStride
        guard typeCount > 0, typeCount <= 2_000_000,
              methodCount <= 8_000_000, fieldCount <= 8_000_000 else {
            throw DumpError.invalidMetadata("Некорректное количество записей в metadata.")
        }

        var types: [TypeDefinition] = []
        types.reserveCapacity(typeCount)
        for index in 0..<typeCount {
            let base = typeSection.offset + index * typeStride
            let name = stringAt(try i32(base))
            let namespace = stringAt(try i32(base + 4))
            let parent = try i32(base + 16)
            let fieldStart = try i32(base + 32)
            let methodStart = try i32(base + 36)
            let methodCountForType = Int(try u16(base + 64))
            let fieldCountForType = Int(try u16(base + 68))
            let bitfield = try u32(base + 80)
            types.append(TypeDefinition(
                name: name.isEmpty ? "Type_\(index)" : name,
                namespace: namespace,
                parent: parent,
                fieldStart: fieldStart,
                methodStart: methodStart,
                methodCount: methodCountForType,
                fieldCount: fieldCountForType,
                isValueType: (bitfield & 1) != 0,
                isEnum: (bitfield & 2) != 0
            ))
        }

        var methods: [MethodDefinition] = []
        methods.reserveCapacity(methodCount)
        for index in 0..<methodCount {
            let base = methodSection.offset + index * methodStride
            methods.append(MethodDefinition(
                name: stringAt(try i32(base)),
                parameterStart: try i32(base + 12),
                parameterCount: Int(try u16(base + 30)),
                flags: try u16(base + 24)
            ))
        }

        var fields: [FieldDefinition] = []
        fields.reserveCapacity(fieldCount)
        for index in 0..<fieldCount {
            let base = fieldSection.offset + index * fieldStride
            fields.append(FieldDefinition(name: stringAt(try i32(base))))
        }

        func parameterName(_ index: Int) -> String {
            guard index >= 0, index < parameterCount else { return "arg\(index)" }
            let base = parameterSection.offset + index * parameterStride
            let raw = (try? i32(base)) ?? -1
            let value = stringAt(raw)
            return value.isEmpty ? "arg\(index)" : value
        }

        func safeIdentifier(_ source: String, fallback: String) -> String {
            let allowed = source.unicodeScalars.map { scalar -> Character in
                let value = scalar.value
                if (value >= 65 && value <= 90) || (value >= 97 && value <= 122) ||
                    (value >= 48 && value <= 57) || value == 95 { return Character(scalar) }
                return "_"
            }
            var result = String(allowed)
            if result.isEmpty { result = fallback }
            if result.first?.isNumber == true { result = "_" + result }
            let keywords: Set<String> = ["class","struct","enum","namespace","public","private","protected","internal","static","void","object","string","int","float","double","return","new","base","this","event","operator","params","ref","out","in","is","as","default","switch","case","if","else","for","while","do","try","catch","finally","throw","using","var","bool","byte","short","long","uint","ulong","decimal","char","interface","delegate","namespace"]
            if keywords.contains(result) { result = "@" + result }
            return result
        }

        var output = """
        // Forge IPA — reconstructed IL2CPP metadata declarations
        // Metadata version: \(version)
        // Generated from global-metadata.dat. Type signatures, field offsets and method RVAs
        // are intentionally not guessed; they require native IL2CPP registration parsing.
        // This file is a metadata declaration dump, not original C# source.

        using System;

        """

        for (typeIndex, type) in types.enumerated() {
            let className = safeIdentifier(type.name, fallback: "Type_\(typeIndex)")
            if !type.namespace.isEmpty {
                let namespaceName = type.namespace.split(separator: ".").map { safeIdentifier(String($0), fallback: "_") }.joined(separator: ".")
                output += "\nnamespace \(namespaceName)\n{\n"
            }
            let indent = type.namespace.isEmpty ? "" : "    "
            let kind = type.isEnum ? "enum" : (type.isValueType ? "struct" : "class")
            var inheritance = ""
            if !type.isValueType, !type.isEnum, type.parent >= 0, Int(type.parent) < types.count {
                let parent = types[Int(type.parent)]
                inheritance = " : " + (parent.namespace.isEmpty ? "" : parent.namespace + ".") + safeIdentifier(parent.name, fallback: "UnknownBase")
            }
            output += "\(indent)public \(kind) \(className)\(inheritance)\n\(indent){\n"

            if type.fieldStart >= 0, type.fieldCount > 0 {
                let start = Int(type.fieldStart)
                let end = min(start + type.fieldCount, fields.count)
                if start < end {
                    for fieldIndex in start..<end {
                        let fieldName = safeIdentifier(fields[fieldIndex].name, fallback: "field_\(fieldIndex)")
                        output += "\(indent)    // Type index unresolved; field offset requires native layout data.\n"
                        output += "\(indent)    public object \(fieldName);\n"
                    }
                }
            }

            if type.methodStart >= 0, type.methodCount > 0 {
                let start = Int(type.methodStart)
                let end = min(start + type.methodCount, methods.count)
                if start < end {
                    for methodIndex in start..<end {
                        let method = methods[methodIndex]
                        let rawName = method.name.isEmpty ? "Method_\(methodIndex)" : method.name
                        let isConstructor = rawName == ".ctor" || rawName == ".cctor"
                        let methodName = isConstructor ? className : safeIdentifier(rawName, fallback: "Method_\(methodIndex)")
                        let isStatic = (method.flags & 0x0010) != 0
                        let accessBits = method.flags & 0x0007
                        let access = accessBits == 6 ? "public" : (accessBits == 4 ? "protected" : (accessBits == 3 ? "internal" : "private"))
                        let parameterStart = Int(method.parameterStart)
                        var parameters: [String] = []
                        if method.parameterCount > 0, parameterStart >= 0 {
                            for parameter in 0..<method.parameterCount {
                                let absolute = parameterStart + parameter
                                let parameterNameSafe = safeIdentifier(parameterName(absolute), fallback: "arg\(parameter)")
                                parameters.append("object \(parameterNameSafe)")
                            }
                        }
                        let staticText = isStatic && !isConstructor ? " static" : ""
                        let returnType = isConstructor ? "" : "object "
                        output += "\(indent)    // Return/parameter types unresolved until native type registration is parsed.\n"
                        output += "\(indent)    \(access)\(staticText) \(returnType)\(methodName)(\(parameters.joined(separator: ", ")));\n"
                    }
                }
            }
            output += "\(indent)}\n"
            if !type.namespace.isEmpty { output += "}\n" }
        }

        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let dumpURL = outputDirectory.appendingPathComponent("dump.cs")
        try output.data(using: .utf8)?.write(to: dumpURL, options: .atomic)

        let names = ["StringLiteral", "StringLiteralData", "String", "Events", "Properties", "Methods", "ParameterDefaultValues", "FieldDefaultValues", "DefaultValues", "FieldMarshaledSizes", "Parameters", "Fields", "GenericParameters", "GenericParameterConstraints", "GenericContainers", "NestedTypes", "Interfaces", "VTables", "InterfaceOffsets", "TypeDefinitions", "Images", "Assemblies", "FieldRefs", "ReferencedAssemblies", "AttributeInfo", "AttributeTypes", "UnresolvedVirtualCallParameterTypes", "UnresolvedVirtualCallParameterRanges", "WindowsRuntimeTypeNames", "WindowsRuntimeStrings", "ExportedTypeDefinitions", "AttributeData", "AttributeDataRanges"]
        let reportSections = sections.enumerated().compactMap { index, section -> MetadataSection? in
            guard section.size > 0 else { return nil }
            return MetadataSection(name: index < names.count ? names[index] : "Section_\(index)", offset: UInt32(clamping: section.offset), count: UInt32(clamping: section.size))
        }
        return IL2CPPMetadataDumpResult(version: version, sections: reportSections, dumpURL: dumpURL, typeCount: typeCount, methodCount: methodCount, fieldCount: fieldCount)
    }

    enum DumpError: LocalizedError {
        case invalidMetadata(String)
        case unsupportedVersion(UInt32)
        var errorDescription: String? {
            switch self {
            case .invalidMetadata(let message): return message
            case .unsupportedVersion(let version): return "Версия metadata \(version) пока не поддерживается генератором dump.cs. Сейчас поддерживаются 27–29."
            }
        }
    }
}

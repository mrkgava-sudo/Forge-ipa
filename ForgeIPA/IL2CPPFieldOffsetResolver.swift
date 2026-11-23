import Foundation

struct IL2CPPFieldOffsetResult {
    let offsetsByFieldIndex: [Int: Int32]
    let registrationFound: Bool
    let typeNamesByTypeIndex: [Int: String]
    let methodRVAsByIndex: [Int: UInt64]
}

enum IL2CPPFieldOffsetResolver {
    static func resolve(metadataURL: URL, nativeBinaryURL: URL) throws -> IL2CPPFieldOffsetResult {
        let metadata = try Data(contentsOf: metadataURL, options: [.mappedIfSafe])
        let binary = try Data(contentsOf: nativeBinaryURL, options: [.mappedIfSafe])
        guard metadata.count >= 256, metadataU32(metadata, 0) == 0xFAB11BAF else {
            return IL2CPPFieldOffsetResult(offsetsByFieldIndex: [:], registrationFound: false, typeNamesByTypeIndex: [:], methodRVAsByIndex: [:])
        }
        let version = metadataU32(metadata, 4)
        guard version == 27 || version == 28 || version == 29 || version == 31 else {
            return IL2CPPFieldOffsetResult(offsetsByFieldIndex: [:], registrationFound: false, typeNamesByTypeIndex: [:])
        }
        let typeSection = metadataSection(metadata, index: 19)
        let fieldSection = metadataSection(metadata, index: 11)
        guard typeSection.size > 0, typeSection.size % 88 == 0, fieldSection.size % 12 == 0 else {
            return IL2CPPFieldOffsetResult(offsetsByFieldIndex: [:], registrationFound: false, typeNamesByTypeIndex: [:])
        }

        let typeCount = typeSection.size / 88
        let fieldCount = fieldSection.size / 12
        let image = try MachOInspector.inspect(nativeBinaryURL)
        let sections = image.sections.filter { $0.fileOffset > 0 && $0.size > 0 }
        let searchable = sections.filter {
            $0.segment == "__DATA" || $0.segment == "__DATA_CONST" ||
            ($0.segment == "__TEXT" && ($0.name == "__const" || $0.name == "__cstring"))
        }

        func pointer(_ offset: Int) -> UInt64 {
            guard offset >= 0, offset + 8 <= binary.count else { return 0 }
            let value = UInt64(binary[offset]) | (UInt64(binary[offset + 1]) << 8) |
                (UInt64(binary[offset + 2]) << 16) | (UInt64(binary[offset + 3]) << 24) |
                (UInt64(binary[offset + 4]) << 32) | (UInt64(binary[offset + 5]) << 40) |
                (UInt64(binary[offset + 6]) << 48) | (UInt64(binary[offset + 7]) << 56)
            return value & 0x0000FFFFFFFFFFFF
        }
        func fileOffset(for address: UInt64) -> Int? {
            for section in sections {
                guard address >= section.virtualAddress,
                      address - section.virtualAddress < section.size else { continue }
                let value = UInt64(section.fileOffset) + (address - section.virtualAddress)
                if value < UInt64(binary.count) { return Int(value) }
            }
            return nil
        }
        func pointerArrayLooksValid(_ address: UInt64, count: Int) -> Bool {
            guard let start = fileOffset(for: address), count > 0,
                  count <= 2_000_000, start + count * 8 <= binary.count else { return false }
            let samples = min(count, 12)
            var valid = 0
            for index in 0..<samples {
                let value = pointer(start + index * 8)
                if value == 0 || fileOffset(for: value) != nil { valid += 1 }
            }
            return valid >= max(1, samples * 3 / 4)
        }

        var registrationBase: UInt64?
        for section in searchable {
            let start = Int(section.fileOffset)
            let sectionLength = Int(min(section.size, UInt64(binary.count)))
            let end = min(binary.count, start + sectionLength)
            guard start >= 0, start + 32 <= end else { continue }
            var cursor = start
            while cursor + 32 <= end {
                if pointer(cursor) == UInt64(typeCount),
                   pointer(cursor + 16) == UInt64(typeCount) {
                    let sizesPointer = pointer(cursor + 24)
                    if pointerArrayLooksValid(sizesPointer, count: typeCount) {
                        let candidateAddress = section.virtualAddress + UInt64(cursor - start)
                        if candidateAddress >= 80 {
                            let base = candidateAddress - 80
                            if let baseOffset = fileOffset(for: base),
                               baseOffset + 96 <= binary.count {
                                let offsetsCount = pointer(baseOffset + 80)
                                let offsetsPointer = pointer(baseOffset + 88)
                                if offsetsCount >= UInt64(typeCount),
                                   pointerArrayLooksValid(offsetsPointer, count: typeCount) {
                                    registrationBase = base
                                    break
                                }
                            }
                        }
                    }
                }
                cursor += 8
            }
            if registrationBase != nil { break }
        }

        guard let registrationBase,
              let registrationOffset = fileOffset(for: registrationBase),
              registrationOffset + 96 <= binary.count else {
            return IL2CPPFieldOffsetResult(offsetsByFieldIndex: [:], registrationFound: false, typeNamesByTypeIndex: [:])
        }

        let offsetsPointer = pointer(registrationOffset + 88)
        guard let offsetsArray = fileOffset(for: offsetsPointer) else {
            return IL2CPPFieldOffsetResult(offsetsByFieldIndex: [:], registrationFound: false, typeNamesByTypeIndex: [:])
        }

        var byvalTypeIndices: [Int32] = []
        var fieldRanges: [(Int, Int, Int32, Bool)] = []
        byvalTypeIndices.reserveCapacity(typeCount)
        fieldRanges.reserveCapacity(typeCount)
        for index in 0..<typeCount {
            let base = typeSection.offset + index * 88
            let byvalTypeIndex = Int32(bitPattern: metadataU32(metadata, base + 8))
            let fieldStart = Int32(bitPattern: metadataU32(metadata, base + 32))
            let fieldNumber = Int(metadataU16(metadata, base + 68))
            let bitfield = metadataU32(metadata, base + 80)
            byvalTypeIndices.append(byvalTypeIndex)
            fieldRanges.append((Int(fieldStart), fieldNumber, byvalTypeIndex, (bitfield & 1) != 0))
        }

        var resolved: [Int: Int32] = [:]
        for (start, count, byvalIndex, isValueType) in fieldRanges {
            guard start >= 0, count > 0, byvalIndex >= 0,
                  Int(byvalIndex) < typeCount,
                  offsetsArray + (Int(byvalIndex) + 1) * 8 <= binary.count else { continue }
            let perTypePointer = pointer(offsetsArray + Int(byvalIndex) * 8)
            guard let perTypeOffsets = fileOffset(for: perTypePointer) else { continue }
            for localIndex in 0..<count {
                let globalIndex = start + localIndex
                guard globalIndex >= 0, globalIndex < fieldCount,
                      perTypeOffsets + localIndex * 4 + 4 <= binary.count else { continue }
                let raw = Int32(bitPattern: metadataU32(binary, perTypeOffsets + localIndex * 4))
                let adjusted = isValueType && raw > 0 ? raw - 16 : raw
                resolved[globalIndex] = adjusted
            }
        }
        var resolvedTypeNames: [Int: String] = [:]
        let typesCountRaw = pointer(registrationOffset + 48)
        let typesPointer = pointer(registrationOffset + 56)
        if typesCountRaw > 0, typesCountRaw <= 8_000_000,
           let typesArray = fileOffset(for: typesPointer),
           typesArray + Int(typesCountRaw) * 8 <= binary.count {
            let typesCount = Int(typesCountRaw)

            let stringSection = metadataSection(metadata, index: 2)
            let genericSection = metadataSection(metadata, index: 12)
            func metadataString(_ index: Int32) -> String {
                guard index >= 0 else { return "" }
                let start = stringSection.offset + Int(index)
                guard start >= stringSection.offset, start < stringSection.offset + stringSection.size else { return "" }
                var end = start
                let limit = stringSection.offset + stringSection.size
                while end < limit, metadata[end] != 0 { end += 1 }
                return String(data: metadata[start..<end], encoding: .utf8) ?? ""
            }
            var typeNames: [(String, String)] = []
            typeNames.reserveCapacity(typeCount)
            for index in 0..<typeCount {
                let base = typeSection.offset + index * 88
                typeNames.append((
                    metadataString(Int32(bitPattern: metadataU32(metadata, base))),
                    metadataString(Int32(bitPattern: metadataU32(metadata, base + 4)))
                ))
            }

            func genericParameterName(_ index: Int) -> String? {
                guard index >= 0, genericSection.size % 16 == 0,
                      index < genericSection.size / 16 else { return nil }
                let nameIndex = Int32(bitPattern: metadataU32(metadata, genericSection.offset + index * 16 + 4))
                let value = metadataString(nameIndex)
                return value.isEmpty ? nil : value
            }

            func resolvePointer(_ typePointer: UInt64, depth: Int) -> String? {
                guard depth < 8, let typeOffset = fileOffset(for: typePointer),
                      typeOffset + 12 <= binary.count else { return nil }
                let dataValue = pointer(typeOffset)
                let bits = metadataU32(binary, typeOffset + 8)
                let code = Int((bits >> 16) & 0xff)
                switch code {
                case 0x01: return "void"
                case 0x02: return "bool"
                case 0x03: return "char"
                case 0x04: return "sbyte"
                case 0x05: return "byte"
                case 0x06: return "short"
                case 0x07: return "ushort"
                case 0x08: return "int"
                case 0x09: return "uint"
                case 0x0a: return "long"
                case 0x0b: return "ulong"
                case 0x0c: return "float"
                case 0x0d: return "double"
                case 0x0e: return "string"
                case 0x18: return "IntPtr"
                case 0x19: return "UIntPtr"
                case 0x1c: return "object"
                case 0x11, 0x12:
                    let index = Int(Int64(bitPattern: dataValue))
                    guard index >= 0, index < typeNames.count else { return nil }
                    let item = typeNames[index]
                    let rawName = item.0.split(separator: "`", maxSplits: 1).first.map(String.init) ?? item.0
                    return item.1.isEmpty ? rawName : item.1 + "." + rawName
                case 0x13, 0x1e:
                    return genericParameterName(Int(Int64(bitPattern: dataValue)))
                case 0x0f, 0x10, 0x1d:
                    guard let nested = resolvePointer(dataValue, depth: depth + 1) else { return nil }
                    if code == 0x0f { return nested + "*" }
                    if code == 0x10 { return nested + "&" }
                    return nested + "[]"
                case 0x14:
                    guard let arrayOffset = fileOffset(for: dataValue),
                          arrayOffset + 9 <= binary.count else { return nil }
                    let elementPointer = pointer(arrayOffset)
                    guard let element = resolvePointer(elementPointer, depth: depth + 1) else { return nil }
                    let rank = max(1, Int(binary[arrayOffset + 8]))
                    return element + "[" + String(repeating: ",", count: max(0, rank - 1)) + "]"
                case 0x15:
                    guard let genericClassOffset = fileOffset(for: dataValue),
                          genericClassOffset + 8 <= binary.count else { return nil }
                    return resolvePointer(pointer(genericClassOffset), depth: depth + 1)
                default:
                    return nil
                }
            }

            for index in 0..<typesCount {
                let typePointer = pointer(typesArray + index * 8)
                if let name = resolvePointer(typePointer, depth: 0), !name.isEmpty {
                    resolvedTypeNames[index] = name
                }
            }
        }

        var methodRVAs: [Int: UInt64] = [:]
        let imageSection = metadataSection(metadata, index: 20)
        let methodSection = metadataSection(metadata, index: 5)
        let imageStride = 40
        let methodStride: Int
        if version == 31 {
            let divides40 = methodSection.size > 0 && methodSection.size % 40 == 0
            let divides36 = methodSection.size > 0 && methodSection.size % 36 == 0
            methodStride = divides40 && !divides36 ? 40 : 36
        } else {
            methodStride = 32
        }
        if imageSection.size > 0, imageSection.size % imageStride == 0,
           methodSection.size > 0, methodSection.size % methodStride == 0,
           image.imageBase > 0 {
            let imageCount = imageSection.size / imageStride
            let imageNames = (0..<imageCount).map { index -> (String, Int, Int) in
                let base = imageSection.offset + index * imageStride
                let nameIndex = Int32(bitPattern: metadataU32(metadata, base))
                let typeStart = Int(Int32(bitPattern: metadataU32(metadata, base + 8)))
                let typeSize = Int(metadataU32(metadata, base + 12))
                return (metadataStringForIndex(metadata, nameIndex), typeStart, typeSize)
            }

            func cString(_ address: UInt64) -> String? {
                guard let start = fileOffset(for: address), start < binary.count else { return nil }
                var end = start
                let limit = min(binary.count, start + 512)
                while end < limit, binary[end] != 0 { end += 1 }
                guard end > start else { return nil }
                return String(data: binary[start..<end], encoding: .utf8)
            }
            func references(to target: UInt64) -> [UInt64] {
                var result: [UInt64] = []
                for section in searchable {
                    let start = Int(section.fileOffset)
                    let end = min(binary.count, start + Int(min(section.size, UInt64(binary.count))))
                    guard start >= 0, start + 8 <= end else { continue }
                    var cursor = start
                    while cursor + 8 <= end {
                        if pointer(cursor) == target {
                            result.append(section.virtualAddress + UInt64(cursor - start))
                            if result.count >= 128 { return result }
                        }
                        cursor += 8
                    }
                }
                return result
            }

            let needle = Data("mscorlib.dll\0".utf8)
            var stringAddress: UInt64?
            for section in searchable where section.name == "__cstring" {
                let start = Int(section.fileOffset)
                let end = min(binary.count, start + Int(min(section.size, UInt64(binary.count))))
                guard start >= 0, start < end else { continue }
                if let range = binary.range(of: needle, options: [], in: start..<end) {
                    stringAddress = section.virtualAddress + UInt64(range.lowerBound - start)
                    break
                }
            }

            if let stringAddress {
                let firstReferences = references(to: stringAddress)
                registrationSearch: for first in firstReferences {
                    for second in references(to: first) {
                        for imageIndex in stride(from: imageCount - 1, through: 0, by: -1) {
                            let delta = UInt64(imageIndex) * 8
                            guard second >= delta else { continue }
                            for third in references(to: second - delta) {
                                guard third >= 8, let countOffset = fileOffset(for: third - 8),
                                      pointer(countOffset) == UInt64(imageCount) else { continue }
                                let registration = third - UInt64(version >= 29 ? 14 : 13) * 8
                                guard let registrationOffset = fileOffset(for: registration) else { continue }
                                let moduleLayouts = version >= 29 ? [104, 120, 96, 112] : [104, 96]
                                var moduleArrayOffset: Int?
                                var moduleCount = 0
                                for countOffsetInStruct in moduleLayouts {
                                    guard registrationOffset + countOffsetInStruct + 16 <= binary.count else { continue }
                                    let count = pointer(registrationOffset + countOffsetInStruct)
                                    let arrayPointer = pointer(registrationOffset + countOffsetInStruct + 8)
                                    if count == UInt64(imageCount), pointerArrayLooksValid(arrayPointer, count: imageCount),
                                       let arrayOffset = fileOffset(for: arrayPointer) {
                                        moduleArrayOffset = arrayOffset
                                        moduleCount = imageCount
                                        break
                                    }
                                }
                                guard let moduleArrayOffset, moduleCount == imageCount else { continue }

                                var modules: [String: (Int, Int)] = [:]
                                for moduleIndex in 0..<moduleCount {
                                    let modulePointer = pointer(moduleArrayOffset + moduleIndex * 8)
                                    guard let moduleOffset = fileOffset(for: modulePointer),
                                          moduleOffset + 24 <= binary.count,
                                          let moduleName = cString(pointer(moduleOffset)),
                                          !moduleName.isEmpty else { continue }
                                    let count = Int(min(pointer(moduleOffset + 8), 2_000_000))
                                    let methodsPointer = pointer(moduleOffset + 16)
                                    guard let methodsOffset = fileOffset(for: methodsPointer),
                                          methodsOffset + count * 8 <= binary.count else { continue }
                                    modules[moduleName] = (methodsOffset, count)
                                }

                                for methodIndex in 0..<(methodSection.size / methodStride) {
                                    let methodBase = methodSection.offset + methodIndex * methodStride
                                    let declaringType = Int(Int32(bitPattern: metadataU32(metadata, methodBase + 4)))
                                    let tokenOffset = version == 31 ? (methodStride == 40 ? 28 : 24) : 20
                                    let token = metadataU32(metadata, methodBase + tokenOffset)
                                    let rid = Int(token & 0x00FFFFFF)
                                    guard rid > 0 else { continue }
                                    guard let owningImage = imageNames.first(where: {
                                        declaringType >= $0.1 && declaringType < $0.1 + $0.2
                                    }), let module = modules[owningImage.0] else { continue }
                                    let pointerIndex = rid - 1
                                    guard pointerIndex < module.1 else { continue }
                                    let methodPointer = pointer(module.0 + pointerIndex * 8)
                                    if methodPointer >= image.imageBase {
                                        methodRVAs[methodIndex] = methodPointer - image.imageBase
                                    }
                                }
                                break registrationSearch
                            }
                        }
                    }
                }
            }
        }

        return IL2CPPFieldOffsetResult(offsetsByFieldIndex: resolved, registrationFound: true, typeNamesByTypeIndex: resolvedTypeNames, methodRVAsByIndex: methodRVAs)
    }

    private static func metadataStringForIndex(_ data: Data, _ index: Int32) -> String {
        let strings = metadataSection(data, index: 2)
        guard index >= 0 else { return "" }
        let start = strings.offset + Int(index)
        guard start >= strings.offset, start < strings.offset + strings.size else { return "" }
        var end = start
        let limit = strings.offset + strings.size
        while end < limit, data[end] != 0 { end += 1 }
        return String(data: data[start..<end], encoding: .utf8) ?? ""
    }

    private static func metadataU16(_ data: Data, _ offset: Int) -> UInt16 {
        guard offset >= 0, offset + 2 <= data.count else { return 0 }
        return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func metadataU32(_ data: Data, _ offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= data.count else { return 0 }
        return UInt32(data[offset]) | (UInt32(data[offset + 1]) << 8) |
            (UInt32(data[offset + 2]) << 16) | (UInt32(data[offset + 3]) << 24)
    }

    private static func metadataSection(_ data: Data, index: Int) -> (offset: Int, size: Int) {
        let base = 8 + index * 8
        return (Int(metadataU32(data, base)), Int(metadataU32(data, base + 4)))
    }
}

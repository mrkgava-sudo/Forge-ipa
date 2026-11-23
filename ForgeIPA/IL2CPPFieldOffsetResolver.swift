import Foundation

struct IL2CPPFieldOffsetResult {
    let offsetsByFieldIndex: [Int: Int32]
    let registrationFound: Bool
}

enum IL2CPPFieldOffsetResolver {
    static func resolve(metadataURL: URL, nativeBinaryURL: URL) throws -> IL2CPPFieldOffsetResult {
        let metadata = try Data(contentsOf: metadataURL, options: [.mappedIfSafe])
        let binary = try Data(contentsOf: nativeBinaryURL, options: [.mappedIfSafe])
        guard metadata.count >= 256, metadataU32(metadata, 0) == 0xFAB11BAF else {
            return IL2CPPFieldOffsetResult(offsetsByFieldIndex: [:], registrationFound: false)
        }
        let version = metadataU32(metadata, 4)
        guard version == 27 || version == 28 || version == 29 || version == 31 else {
            return IL2CPPFieldOffsetResult(offsetsByFieldIndex: [:], registrationFound: false)
        }
        let typeSection = metadataSection(metadata, index: 19)
        let fieldSection = metadataSection(metadata, index: 11)
        guard typeSection.size > 0, typeSection.size % 88 == 0, fieldSection.size % 12 == 0 else {
            return IL2CPPFieldOffsetResult(offsetsByFieldIndex: [:], registrationFound: false)
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
            return IL2CPPFieldOffsetResult(offsetsByFieldIndex: [:], registrationFound: false)
        }

        let offsetsPointer = pointer(registrationOffset + 88)
        guard let offsetsArray = fileOffset(for: offsetsPointer) else {
            return IL2CPPFieldOffsetResult(offsetsByFieldIndex: [:], registrationFound: false)
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
        return IL2CPPFieldOffsetResult(offsetsByFieldIndex: resolved, registrationFound: true)
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

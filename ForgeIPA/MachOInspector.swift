import Foundation

struct MachOSectionInfo {
    let segment: String
    let name: String
    let virtualAddress: UInt64
    let size: UInt64
    let fileOffset: UInt32
}

struct MachOInfo {
    let architecture: String
    let fileType: UInt32
    let segments: [String]
    let sections: [MachOSectionInfo]
}

enum MachOInspector {
    enum InspectionError: LocalizedError {
        case invalidImage
        case unsupportedArchitecture

        var errorDescription: String? {
            switch self {
            case .invalidImage: return "Файл не является корректным Mach-O образом."
            case .unsupportedArchitecture: return "В универсальном бинарнике не найден поддерживаемый ARM64-срез."
            }
        }
    }

    static func inspect(_ url: URL) throws -> MachOInfo {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard data.count >= 32 else { throw InspectionError.invalidImage }

        func u32le(_ offset: Int) -> UInt32 {
            guard offset >= 0, offset + 4 <= data.count else { return 0 }
            return UInt32(data[offset]) | (UInt32(data[offset + 1]) << 8) |
                (UInt32(data[offset + 2]) << 16) | (UInt32(data[offset + 3]) << 24)
        }
        func u64le(_ offset: Int) -> UInt64 {
            UInt64(u32le(offset)) | (UInt64(u32le(offset + 4)) << 32)
        }
        func u32be(_ offset: Int) -> UInt32 {
            guard offset >= 0, offset + 4 <= data.count else { return 0 }
            return (UInt32(data[offset]) << 24) | (UInt32(data[offset + 1]) << 16) |
                (UInt32(data[offset + 2]) << 8) | UInt32(data[offset + 3])
        }
        func u64be(_ offset: Int) -> UInt64 {
            (UInt64(u32be(offset)) << 32) | UInt64(u32be(offset + 4))
        }
        func fixedString(_ offset: Int, _ length: Int) -> String {
            guard offset >= 0, length > 0, offset + length <= data.count else { return "" }
            let bytes = data[offset..<(offset + length)]
            let end = bytes.firstIndex(of: 0) ?? bytes.endIndex
            return String(decoding: bytes[..<end], as: UTF8.self)
        }

        var sliceOffset = 0
        var sliceSize = data.count
        var architecture = "unknown"
        let magic = u32be(0)

        if magic == 0xcafebabe || magic == 0xcafebabf {
            let is64 = magic == 0xcafebabf
            let count = Int(u32be(4))
            guard count > 0, count <= 64 else { throw InspectionError.invalidImage }
            var selected: (Int, Int, String)?
            var first: (Int, Int, String)?
            for index in 0..<count {
                let base = 8 + index * (is64 ? 32 : 20)
                guard base + (is64 ? 32 : 20) <= data.count else { throw InspectionError.invalidImage }
                let cpu = u32be(base)
                let offset = is64 ? Int(u64be(base + 8)) : Int(u32be(base + 8))
                let size = is64 ? Int(u64be(base + 16)) : Int(u32be(base + 12))
                let name = cpu == 0x0100000c ? "arm64" : String(format: "cpu-0x%08x", cpu)
                guard offset >= 0, size > 0, offset <= data.count, size <= data.count - offset else { throw InspectionError.invalidImage }
                if first == nil { first = (offset, size, name) }
                if cpu == 0x0100000c { selected = (offset, size, name); break }
            }
            guard let chosen = selected ?? first else { throw InspectionError.unsupportedArchitecture }
            if selected == nil && chosen.2.hasPrefix("cpu-") { throw InspectionError.unsupportedArchitecture }
            sliceOffset = chosen.0
            sliceSize = chosen.1
            architecture = chosen.2
        }

        let imageMagic = u32le(sliceOffset)
        guard imageMagic == 0xfeedfacf else { throw InspectionError.invalidImage }
        let cpuType = u32le(sliceOffset + 4)
        if architecture == "unknown" {
            architecture = cpuType == 0x0100000c ? "arm64" : String(format: "cpu-0x%08x", cpuType)
        }
        let fileType = u32le(sliceOffset + 12)
        let commandCount = Int(u32le(sliceOffset + 16))
        let commandBytes = Int(u32le(sliceOffset + 20))
        guard commandCount >= 0, commandCount <= 100_000,
              commandBytes >= 0, sliceOffset + 32 + commandBytes <= sliceOffset + sliceSize else {
            throw InspectionError.invalidImage
        }

        var segments: [String] = []
        var sections: [MachOSectionInfo] = []
        var cursor = sliceOffset + 32
        for _ in 0..<commandCount {
            guard cursor + 8 <= data.count else { throw InspectionError.invalidImage }
            let command = u32le(cursor)
            let commandSize = Int(u32le(cursor + 4))
            guard commandSize >= 8, cursor + commandSize <= sliceOffset + sliceSize else { throw InspectionError.invalidImage }

            if command == 0x19, commandSize >= 72 {
                let segmentName = fixedString(cursor + 8, 16)
                let sectionCount = Int(u32le(cursor + 64))
                guard sectionCount >= 0, sectionCount <= 100_000,
                      72 + sectionCount * 80 <= commandSize else { throw InspectionError.invalidImage }
                segments.append(segmentName)
                for sectionIndex in 0..<sectionCount {
                    let base = cursor + 72 + sectionIndex * 80
                    sections.append(MachOSectionInfo(
                        segment: fixedString(base + 16, 16),
                        name: fixedString(base, 16),
                        virtualAddress: u64le(base + 32),
                        size: u64le(base + 40),
                        fileOffset: u32le(base + 48)
                    ))
                }
            }
            cursor += commandSize
        }

        return MachOInfo(architecture: architecture, fileType: fileType, segments: segments, sections: sections)
    }
}

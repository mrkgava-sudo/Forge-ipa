import Foundation

struct UE4MarkerHit {
    let name: String
    let fileOffsets: [Int]
}

struct UE4AnalysisResult {
    let reportURL: URL
    let detected: Bool
    let architecture: String
    let imageBase: UInt64
    let sections: [MachOSectionInfo]
    let markers: [UE4MarkerHit]
    let packageInventory: [String: Int]
    let binaryName: String
}

/// Static, offline inspection of a packaged Unreal Engine iOS executable.
/// File offsets in this report refer to bytes in the Mach-O file, not runtime
/// addresses or UObject offsets. No offsets are guessed.
enum UE4StaticAnalyzer {
    private static let markerGroups: [(String, [String])] = [
        ("Engine identity", ["Unreal Engine", "UnrealEngine", "UE4Game", "UE4"]),
        ("Object system", ["GUObjectArray", "FUObjectArray", "UObject", "UClass", "UStruct", "UFunction"]),
        ("Name system", ["FNamePool", "NamePoolData", "GNames", "FNameEntry"]),
        ("Reflection", ["FProperty", "UProperty", "FField", "FFieldClass", "FStructProperty", "FObjectProperty"]),
        ("Runtime globals", ["GWorld", "GEngine", "ProcessEvent", "StaticFindObject", "StaticLoadObject"]),
        ("Engine modules", ["/Script/CoreUObject", "/Script/Engine", "CoreUObject", "Engine/Transient"])
    ]

    static func analyze(binaryURL: URL, ipaEntryPaths: [String], outputDirectory: URL) throws -> UE4AnalysisResult {
        let data = try Data(contentsOf: binaryURL, options: [.mappedIfSafe])
        let image = try MachOInspector.inspect(binaryURL)
        var hits: [UE4MarkerHit] = []
        var detected = false

        for (group, values) in markerGroups {
            var groupOffsets: [Int] = []
            for marker in values {
                let needle = Data(marker.utf8)
                var cursor = data.startIndex
                var found = 0
                while cursor < data.endIndex, found < 12,
                      let range = data.range(of: needle, options: [], in: cursor..<data.endIndex) {
                    groupOffsets.append(range.lowerBound)
                    cursor = range.upperBound
                    found += 1
                }
                if found > 0 { detected = true }
            }
            if !groupOffsets.isEmpty {
                hits.append(UE4MarkerHit(name: group, fileOffsets: Array(groupOffsets.prefix(40)).sorted()))
            }
        }

        let inventory = inventoryForIPAEntries(ipaEntryPaths)
        let resourceEvidence = (inventory[".pak"] ?? 0) + (inventory[".ucas"] ?? 0) +
            (inventory[".utoc"] ?? 0) + (inventory[".uasset"] ?? 0) + (inventory[".uexp"] ?? 0)
        if resourceEvidence > 0 && (binaryURL.lastPathComponent.localizedCaseInsensitiveContains("ue4") ||
            binaryURL.lastPathComponent.localizedCaseInsensitiveContains("shadowtracker")) {
            detected = true
        }

        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let output = outputDirectory.appendingPathComponent("ue4-analysis.txt")
        var lines: [String] = [
            "FORGE IPA — UNREAL ENGINE STATIC ANALYSIS",
            "==========================================",
            "",
            "Executable: \(binaryURL.lastPathComponent)",
            "Architecture: \(image.architecture)",
            "Mach-O file type: 0x\(String(image.fileType, radix: 16))",
            "Image base (Mach-O preferred VM address): 0x\(String(image.imageBase, radix: 16))",
            "UE4 evidence: \(detected ? "markers/resources found" : "not confirmed")",
            "",
            "IMPORTANT:",
            "Offsets listed below are file offsets of matching strings in this Mach-O file.",
            "They are NOT UObject offsets, runtime pointers, GNames/GUObjectArray addresses,",
            "or ready-to-use game offsets. No runtime addresses are inferred.",
            "",
            "REFLECTION / ENGINE MARKERS"
        ]

        if hits.isEmpty {
            lines.append("No known marker strings were found. Stripped or encrypted builds may hide these strings.")
        } else {
            for hit in hits {
                lines.append("")
                lines.append("[\(hit.name)]")
                for offset in hit.fileOffsets {
                    lines.append("file+0x\(String(offset, radix: 16))")
                }
            }
        }

        lines += ["", "MACH-O SECTIONS"]
        for section in image.sections {
            lines.append("\(section.segment),\(section.name) vm=0x\(String(section.virtualAddress, radix: 16)) size=0x\(String(section.size, radix: 16)) file=0x\(String(section.fileOffset, radix: 16))")
        }

        lines += ["", "PACKAGED UNREAL RESOURCE INVENTORY"]
        if inventory.isEmpty {
            lines.append("No common Unreal cooked-resource extensions found in IPA paths.")
        } else {
            for key in inventory.keys.sorted() {
                lines.append("\(key): \(inventory[key] ?? 0)")
            }
        }

        lines += [
            "",
            "LIMITATIONS",
            "- This is static inspection of the IPA; it does not execute the game.",
            "- A full live UObject dump requires reliable version-specific runtime structures",
            "  and cannot be reconstructed from arbitrary strings or guessed signatures.",
            "- Stripped symbols, encrypted assets, custom engine forks and arm64e fixups",
            "  can prevent further recovery.",
            "- No GWorld, GNames, GUObjectArray, class offsets or function addresses are fabricated."
        ]
        try lines.joined(separator: "\n").write(to: output, atomically: true, encoding: .utf8)

        return UE4AnalysisResult(
            reportURL: output,
            detected: detected,
            architecture: image.architecture,
            imageBase: image.imageBase,
            sections: image.sections,
            markers: hits,
            packageInventory: inventory,
            binaryName: binaryURL.lastPathComponent
        )
    }

    private static func inventoryForIPAEntries(_ paths: [String]) -> [String: Int] {
        let supported: Set<String> = [".pak", ".ucas", ".utoc", ".uasset", ".uexp", ".ubulk", ".ini", ".usmap"]
        var counts: [String: Int] = [:]
        for path in paths {
            let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
            let key = ext.isEmpty ? "" : "." + ext
            if supported.contains(key) { counts[key, default: 0] += 1 }
        }
        return counts
    }
}

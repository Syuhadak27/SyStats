import Foundation

/// Read-only, heuristic parser for ACPI tables.
///
/// AML files are compiled bytecode. We parse the standard 36-byte ACPI table
/// header exactly, then perform a clearly-labelled ASCII token scan for device
/// and method names (AML NamePaths store 4-character ASCII segments, so this
/// is useful for auditing even without a full AML interpreter). DSL source
/// files are parsed with a lightweight regex for declarations. No file is ever
/// modified or patched.
enum ACPIParser {
    struct TableHeader {
        var signature: String
        var length: Int
        var revision: UInt8
        var oemID: String
        var oemTableID: String
    }

    private static let tokenMap: [(String, ACPICategory)] = [
        ("BATX", .battery), ("BATC", .battery), ("BAT0", .battery), ("BAT1", .battery),
        ("_BIF", .battery), ("_BST", .battery), ("_BIX", .battery), ("BIF", .battery),
        ("BST", .battery), ("BCLM", .battery), ("CHLC", .battery), ("BATP", .battery),
        ("PNP0C09", .embeddedController), ("EC0", .embeddedController), ("EC", .embeddedController),
        ("EREG", .embeddedController), ("OperationRegion", .embeddedController),
        ("THERM", .thermal), ("THERMAL", .thermal), ("TEMP", .thermal), ("THRM", .thermal),
        ("TZ00", .thermal), ("_TMP", .thermal), ("DTS", .thermal),
        ("FAN", .fan), ("F0Ac", .fan), ("F1Ac", .fan), ("FNum", .fan), ("_FAN", .fan),
        ("VSMC", .smc), ("YSMC", .smc), ("SMC", .smc), ("SMCB", .smc),
        ("DTGP", .power), ("PTWK", .power), ("XDSM", .power), ("PLUG", .power),
        ("HRTF", .power), ("PMCR", .power), ("DYTC", .power), ("VDEV", .power),
    ]

    static func parseHeader(_ data: Data) -> TableHeader? {
        guard data.count >= 36 else { return nil }
        let bytes = [UInt8](data.prefix(36))
        let signature = ascii(bytes, 0, 4)
        guard !signature.isEmpty else { return nil }
        let length = Int(bytes[4]) | (Int(bytes[5]) << 8) | (Int(bytes[6]) << 16) | (Int(bytes[7]) << 24)
        return TableHeader(
            signature: signature,
            length: length,
            revision: bytes[8],
            oemID: ascii(bytes, 10, 6),
            oemTableID: ascii(bytes, 16, 8)
        )
    }

    static func findings(inAML data: Data, fileName: String) -> [ACPIFinding] {
        let text = String(bytes: data, encoding: .ascii) ?? ""
        return findings(inText: text, fileName: fileName, origin: .amlStringScan)
    }

    static func findings(inDSL text: String, fileName: String) -> [ACPIFinding] {
        var result = findings(inText: text, fileName: fileName, origin: .dslSource)

        let pattern = #"\b(Device|Method|Alias|Name|OperationRegion|Field)\s*\(([^\s,)]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return result }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: range)
        for match in matches.prefix(250) {
            guard match.numberOfRanges >= 3,
                  let kindRange = Range(match.range(at: 1), in: text),
                  let nameRange = Range(match.range(at: 2), in: text) else { continue }
            let kind = String(text[kindRange])
            let name = String(text[nameRange])
            let category = category(for: name)
            result.append(ACPIFinding(
                category: category,
                name: "\(kind): \(name)",
                detail: "Declared in DSL source",
                sourceFile: fileName,
                origin: .dslSource
            ))
        }
        return deduplicated(result)
    }

    private static func findings(inText text: String, fileName: String, origin: ACPIFindingOrigin) -> [ACPIFinding] {
        var result: [ACPIFinding] = []
        for (token, category) in tokenMap where text.contains(token) {
            result.append(ACPIFinding(
                category: category,
                name: token,
                detail: "Matched ACPI/EC token in compiled table or source",
                sourceFile: fileName,
                origin: origin
            ))
        }
        return deduplicated(result)
    }

    private static func category(for name: String) -> ACPICategory {
        for (token, category) in tokenMap where name.localizedCaseInsensitiveContains(token) {
            return category
        }
        return .other
    }

    private static func deduplicated(_ findings: [ACPIFinding]) -> [ACPIFinding] {
        var seen = Set<String>()
        return findings.filter { seen.insert("\($0.name)|\($0.origin.rawValue)|\($0.sourceFile)").inserted }
    }

    private static func ascii(_ bytes: [UInt8], _ offset: Int, _ length: Int) -> String {
        guard offset + length <= bytes.count else { return "" }
        let slice = bytes[offset..<(offset + length)]
        let value = String(bytes: slice, encoding: .ascii) ?? ""
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

import Foundation

// iOS 16-compatible, deliberately narrow Mach-O chained-import editor.
// Does not bypass code signing, decrypt FairPlay, or modify system libraries.
struct ImportRecord: Identifiable, Hashable {
    let symbol: String
    let ordinal: Int
    let weak: Bool
    let offset: Int
    let format: UInt32
    var id: String { "\(offset):\(symbol)" }
}

struct PatchReceipt {
    let name: String
    let offset: Int
    let before: UInt8
    let after: UInt8
}

enum MachOError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        if case .invalid(let message) = self { return message }
        return "Unsupported executable"
    }
}

struct MachOPatcher {
    private(set) var data: Data
    let imports: [ImportRecord]

    init(url: URL) throws {
        let bytes = try Data(contentsOf: url, options: [.mappedIfSafe])
        imports = try Self.scan(bytes)
        data = bytes
    }

    init(data: Data) throws {
        imports = try Self.scan(data)
        self.data = data
    }

    mutating func makeWeak(symbol: String) throws -> PatchReceipt {
        let matches = imports.filter { $0.symbol == symbol && !$0.weak }
        guard matches.count == 1, let record = matches.first else {
            throw MachOError.invalid("Expected exactly one non-weak import for \(symbol); found \(matches.count). No changes made.")
        }
        let position = record.offset + (record.format == 3 ? 2 : 1)
        let prior = data[position]
        guard (prior & 1) == 0 else { throw MachOError.invalid("Symbol already optional") }
        data[position] = prior | 1
        return PatchReceipt(name: symbol, offset: position, before: prior, after: data[position])
    }

    func write(to url: URL) throws { try data.write(to: url, options: .atomic) }

    private static func u32(_ d: Data, _ p: Int) throws -> UInt32 {
        guard p >= 0, p <= d.count - 4 else { throw MachOError.invalid("Mach-O contains an out-of-range offset") }
        return (0..<4).reduce(UInt32(0)) { $0 | (UInt32(d[p + $1]) << (8 * $1)) }
    }
    private static func u64(_ d: Data, _ p: Int) throws -> UInt64 {
        guard p >= 0, p <= d.count - 8 else { throw MachOError.invalid("Mach-O contains an out-of-range offset") }
        return (0..<8).reduce(UInt64(0)) { $0 | (UInt64(d[p + $1]) << (8 * $1)) }
    }
    private static func checked(_ off: UInt64, _ length: UInt64, _ size: Int) throws -> Int {
        guard off <= UInt64(size), length <= UInt64(size) - off else {
            throw MachOError.invalid("Mach-O fixups exceed the executable size")
        }
        return Int(off)
    }
    private static func scan(_ data: Data) throws -> [ImportRecord] {
        guard data.count >= 32, try u32(data, 0) == 0xfeedfacf else {
            throw MachOError.invalid("Only thin, little-endian 64-bit Mach-O executables are supported")
        }
        let cpu = try u32(data, 4)
        guard cpu == 0x0100000c else { throw MachOError.invalid("Only ARM64 executables are supported") }
        let commandCount = Int(try u32(data, 16))
        let commandSize = Int(try u32(data, 20))
        guard commandCount >= 0, commandCount < 10000, commandSize <= data.count - 32 else {
            throw MachOError.invalid("Invalid load commands")
        }
        var cursor = 32
        let commandsEnd = 32 + commandSize
        var fixupOff: Int?
        var fixupSize: Int = 0
        for _ in 0..<commandCount {
            guard cursor + 8 <= commandsEnd else { throw MachOError.invalid("Truncated load command") }
            let cmd = try u32(data, cursor)
            let size = Int(try u32(data, cursor + 4))
            guard size >= 8, cursor + size <= commandsEnd else {
                throw MachOError.invalid("Invalid load command size")
            }
            if cmd == 0x80000034 { // LC_DYLD_CHAINED_FIXUPS
                guard size >= 16 else { throw MachOError.invalid("Truncated fixup load command") }
                fixupOff = Int(try u32(data, cursor + 8))
                fixupSize = Int(try u32(data, cursor + 12))
            }
            if cmd == 0x21 || cmd == 0x2c { // LC_ENCRYPTION_INFO[_64]
                guard size >= 20 else { throw MachOError.invalid("Truncated encryption load command") }
                if try u32(data, cursor + 16) != 0 {
                    throw MachOError.invalid("Encrypted App Store executable. Import a decrypted IPA instead.")
                }
            }
            cursor += size
        }
        guard let start = fixupOff, fixupSize >= 28 else {
            throw MachOError.invalid("No supported dyld chained-import table")
        }
        _ = try checked(UInt64(start), UInt64(fixupSize), data.count)
        let version = try u32(data, start)
        guard version == 0 else { throw MachOError.invalid("Unsupported chained-fixups version") }
        let importsOffset = Int(try u32(data, start + 8))
        let symbolOffset = Int(try u32(data, start + 12))
        let count = Int(try u32(data, start + 16))
        let format = try u32(data, start + 20)
        guard (1...3).contains(format), count < 100000 else {
            throw MachOError.invalid("Unsupported chained-import format/count")
        }
        let entrySize: Int = (format == 1 ? 4 : format == 2 ? 8 : 16)
        guard importsOffset >= 28, symbolOffset >= 28,
              importsOffset <= fixupSize, symbolOffset <= fixupSize,
              count <= (fixupSize - importsOffset) / entrySize else {
            throw MachOError.invalid("Invalid fixup import table")
        }
        var found: [ImportRecord] = []
        for i in 0..<count {
            let entry = start + importsOffset + i * entrySize
            let bits = format == 3 ? try u64(data, entry) : UInt64(try u32(data, entry))
            let ordinal = format == 3 ? Int(bits & 0xffff) : Int(bits & 0xff)
            let isWeak = format == 3 ? (bits & (1 << 16)) != 0 : (bits & (1 << 8)) != 0
            let nameOffset = format == 3 ? (bits >> 32) : (bits >> 9)
            let name = try checked(UInt64(start) + UInt64(symbolOffset) + nameOffset, 1, data.count)
            guard name < start + fixupSize else { throw MachOError.invalid("Symbol name outside fixup data") }
            var end = name
            let maxEnd = min(start + fixupSize, name + 4096)
            while end < maxEnd && data[end] != 0 { end += 1 }
            guard end < maxEnd, let string = String(data: data[name..<end], encoding: .utf8) else {
                throw MachOError.invalid("Invalid import symbol string")
            }
            found.append(ImportRecord(symbol: string, ordinal: ordinal, weak: isWeak, offset: entry, format: format))
        }
        return found
    }
}

struct CrashReportParser {
    static func missingSymbol(in text: String) -> String? {
        let pattern = #"Symbol not found:\s*([_A-Za-z0-9.$]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
}


import Foundation
@main
struct TestKFC {
    static func main() throws {
        guard CommandLine.arguments.count == 3 else {
            print("usage: validate-kfc ORIGINAL_EXE PATCHED_EXE")
            return
        }
        let input = URL(fileURLWithPath: CommandLine.arguments[1])
        let output = URL(fileURLWithPath: CommandLine.arguments[2])
        var editor = try MachOPatcher(url: input)
        let hits = editor.imports.filter { $0.symbol == "_NSUserActivityTypeLiveActivity" }
        precondition(hits.count == 1 && !hits[0].weak, "Missing KFC test fixture import")
        let patch = try editor.makeWeak(symbol: "_NSUserActivityTypeLiveActivity")
        try editor.write(to: output)
        let got = try MachOPatcher(url: output)
        precondition(got.imports.first(where: { $0.symbol == patch.name })?.weak == true)
        let before = try Data(contentsOf: input)
        let after = try Data(contentsOf: output)
        let changes = zip(before, after).filter { $0 != $1 }.count
        precondition(changes == 1, "Expected one changed byte, saw \(changes)")
        print("PASS • format \(hits[0].format) • changed byte 0x\(String(patch.offset,radix:16)) • \(before.count) bytes • exactly 1 byte changed")
    }
}


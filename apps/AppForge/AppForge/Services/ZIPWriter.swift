import Foundation

/// Small dependency-free ZIP store writer (method 0); adequate for Swift source export.
enum ZIPWriter {
    private static func le16(_ value: UInt16) -> Data {
        Data([UInt8(value & 255), UInt8((value >> 8) & 255)])
    }
    private static func le32(_ value: UInt32) -> Data {
        Data((0..<4).map { UInt8((value >> ($0 * 8)) & 255) })
    }
    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = crc & 1 == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1
            }
        }
        return crc ^ 0xFFFF_FFFF
    }
    static func export(_ project: ForgeProject) throws -> URL {
        var output = Data()
        var directory = Data()
        guard project.files.count < 65_535 else { throw ForgeError.message("Too many files for ZIP") }
        for file in project.files {
            let name = Data(file.path.utf8)
            let bytes = Data(file.content.utf8)
            guard name.count <= 65_535, bytes.count <= Int(UInt32.max), output.count <= Int(UInt32.max) else {
                throw ForgeError.message("File too large for ZIP writer")
            }
            let offset = UInt32(output.count), size = UInt32(bytes.count), crc = crc32(bytes)
            var local = Data()
            local.append(le32(0x04034B50))
            local.append(le16(20)); local.append(le16(0)); local.append(le16(0))
            local.append(le16(0)); local.append(le16(0))
            local.append(le32(crc)); local.append(le32(size)); local.append(le32(size))
            local.append(le16(UInt16(name.count))); local.append(le16(0)); local.append(name)
            output.append(local); output.append(bytes)
            directory.append(le32(0x02014B50))
            directory.append(le16(20)); directory.append(le16(20))
            directory.append(le16(0)); directory.append(le16(0))
            directory.append(le16(0)); directory.append(le16(0))
            directory.append(le32(crc)); directory.append(le32(size)); directory.append(le32(size))
            directory.append(le16(UInt16(name.count))); directory.append(le16(0)); directory.append(le16(0))
            directory.append(le16(0)); directory.append(le16(0)); directory.append(le32(0))
            directory.append(le32(offset)); directory.append(name)
        }
        guard output.count + directory.count < Int(UInt32.max) else { throw ForgeError.message("ZIP too large") }
        let offset = UInt32(output.count), length = UInt32(directory.count)
        output.append(directory)
        output.append(le32(0x06054B50)); output.append(le16(0)); output.append(le16(0))
        output.append(le16(UInt16(project.files.count))); output.append(le16(UInt16(project.files.count)))
        output.append(le32(length)); output.append(le32(offset)); output.append(le16(0))
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("\(project.appName)-\(UUID().uuidString).zip")
        try output.write(to: destination, options: .atomic)
        return destination
    }
}

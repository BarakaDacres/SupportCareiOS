import Foundation

/// Minimal ZIP writer that stores files without compression. Used for batch invoice export
/// (one vector PDF per invoice, per AGENTS.md). PDFs are already compressed, so storing them
/// costs little, and it avoids a third-party dependency.
public struct ZipWriter {
    public struct Entry { public var name: String; public var data: Data }

    public static func archive(_ entries: [Entry], date: Date = Date()) -> Data {
        var out = Data()
        var central = Data()
        let (dosTime, dosDate) = dosDateTime(date)
        var usedNames = Set<String>()

        for entry in entries {
            let name = uniqueName(entry.name, used: &usedNames)
            let nameData = Data(name.utf8)
            let crc = CRC32.checksum(entry.data)
            let size = UInt32(entry.data.count)
            let offset = UInt32(out.count)

            // Local file header
            out.append(le32: 0x0403_4b50)
            out.append(le16: 20)          // version needed
            out.append(le16: 0x0800)      // UTF-8 names
            out.append(le16: 0)           // stored
            out.append(le16: dosTime); out.append(le16: dosDate)
            out.append(le32: crc); out.append(le32: size); out.append(le32: size)
            out.append(le16: UInt16(nameData.count)); out.append(le16: 0)
            out.append(nameData)
            out.append(entry.data)

            // Central directory record
            central.append(le32: 0x0201_4b50)
            central.append(le16: 20); central.append(le16: 20)
            central.append(le16: 0x0800); central.append(le16: 0)
            central.append(le16: dosTime); central.append(le16: dosDate)
            central.append(le32: crc); central.append(le32: size); central.append(le32: size)
            central.append(le16: UInt16(nameData.count))
            central.append(le16: 0); central.append(le16: 0); central.append(le16: 0); central.append(le16: 0)
            central.append(le32: 0)
            central.append(le32: offset)
            central.append(nameData)
        }

        let cdOffset = UInt32(out.count)
        out.append(central)
        out.append(le32: 0x0605_4b50)
        out.append(le16: 0); out.append(le16: 0)
        out.append(le16: UInt16(entries.count)); out.append(le16: UInt16(entries.count))
        out.append(le32: UInt32(central.count)); out.append(le32: cdOffset)
        out.append(le16: 0)
        return out
    }

    static func uniqueName(_ name: String, used: inout Set<String>) -> String {
        var candidate = name
        var i = 2
        while used.contains(candidate) {
            let ext = (name as NSString).pathExtension
            let base = (name as NSString).deletingPathExtension
            candidate = ext.isEmpty ? "\(base) (\(i))" : "\(base) (\(i)).\(ext)"
            i += 1
        }
        used.insert(candidate)
        return candidate
    }

    static func dosDateTime(_ date: Date) -> (UInt16, UInt16) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let time = UInt16((c.hour ?? 0) << 11 | (c.minute ?? 0) << 5 | (c.second ?? 0) / 2)
        let day = UInt16(max(0, (c.year ?? 1980) - 1980) << 9 | (c.month ?? 1) << 5 | (c.day ?? 1))
        return (time, day)
    }
}

enum CRC32 {
    static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for b in data { crc = table[Int((crc ^ UInt32(b)) & 0xFF)] ^ (crc >> 8) }
        return crc ^ 0xFFFF_FFFF
    }
}

extension Data {
    mutating func append(le16 v: UInt16) { Swift.withUnsafeBytes(of: v.littleEndian) { append(contentsOf: $0) } }
    mutating func append(le32 v: UInt32) { Swift.withUnsafeBytes(of: v.littleEndian) { append(contentsOf: $0) } }
}

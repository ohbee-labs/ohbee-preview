import Foundation

struct IconChunk {
    let type: String
    let path: String
}

func bigEndianBytes(_ value: UInt32) -> Data {
    var encoded = value.bigEndian
    return Data(bytes: &encoded, count: MemoryLayout<UInt32>.size)
}

func fourCC(_ value: String) -> Data {
    precondition(value.utf8.count == 4)
    return Data(value.utf8)
}

guard CommandLine.arguments.count == 3 else {
    fputs("usage: MakeICNS <iconset-directory> <output.icns>\n", stderr)
    exit(2)
}

let directory = CommandLine.arguments[1]
let output = CommandLine.arguments[2]
let chunks = [
    IconChunk(type: "icp4", path: "icon_16x16.png"),
    IconChunk(type: "icp5", path: "icon_32x32.png"),
    IconChunk(type: "icp6", path: "icon_32x32@2x.png"),
    IconChunk(type: "ic07", path: "icon_128x128.png"),
    IconChunk(type: "ic08", path: "icon_256x256.png"),
    IconChunk(type: "ic09", path: "icon_512x512.png"),
    IconChunk(type: "ic10", path: "icon_512x512@2x.png")
]

let payloads: [(String, Data)] = try chunks.map { chunk in
    let url = URL(fileURLWithPath: directory).appendingPathComponent(chunk.path)
    return (chunk.type, try Data(contentsOf: url))
}

let totalLength = 8 + payloads.reduce(0) { $0 + 8 + $1.1.count }
guard totalLength <= UInt32.max else {
    fputs("ICNS payload is too large\n", stderr)
    exit(3)
}

var result = Data()
result.append(fourCC("icns"))
result.append(bigEndianBytes(UInt32(totalLength)))

for (type, payload) in payloads {
    result.append(fourCC(type))
    result.append(bigEndianBytes(UInt32(payload.count + 8)))
    result.append(payload)
}

try result.write(to: URL(fileURLWithPath: output), options: .atomic)

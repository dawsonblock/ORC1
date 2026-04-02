import re

path = "Sources/OracleOS/Events/FileEventStore.swift"
with open(path, "r") as f:
    content = f.read()

new_append = """    public func append(contentsOf newEnvelopes: [EventEnvelope]) throws {
        var payload = Data()
        for env in newEnvelopes {
            payload.append(try encoder.encode(env))
            payload.append(contentsOf: [0x0A])
        }
        
        let handle = try FileHandle(forWritingTo: logURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        handle.write(payload)
        try handle.synchronize()
        fsync(handle.fileDescriptor)
    }"""

content = re.sub(r'    public func append\(contentsOf newEnvelopes: \[EventEnvelope\]\) throws \{.*?(?=    private static func)', new_append + '\n\n', content, flags=re.DOTALL)

with open(path, "w") as f:
    f.write(content)

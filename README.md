# swift-zlib

Pure Swift DEFLATE, zlib, and gzip compression. Requires Swift 6.4 and macOS 27+.

```swift
import Zlib

let input = Array("Hello, gzip!".utf8)
let compressed = try ZLib.deflate(input: input.span, format: .gzip)
let decoded = try ZLib.inflate(
  input: compressed.span, format: .gzip, maximumOutputSize: 1_048_576)
```

- Formats: `.rawDeflate` (default), `.zlib`, `.gzip`.
- Strategies: `.automatic` (default), `.stored`, `.fixed`, `.dynamic`.
- Streaming: [`Deflater`](Sources/Zlib/Deflate/Deflater.swift) and [`Inflater`](Sources/Zlib/Inflate/Inflater.swift).
- Checksums: `Adler32` and `CRC32`.
- Example: [read a Git loose object](Examples/GitObjects).

```sh
swift test
swift run -c release ZlibBenchmarks
```

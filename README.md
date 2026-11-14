# swift-zlib

Pure Swift DEFLATE, zlib, and gzip compression.

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

Reuse a streaming compressor for independent messages with `deflater.reset()`.
Reset preserves the format, strategy, and allocated input/output buffer capacities,
and discards the previous stream's buffered input, pending output, history, and
checksums. It also recovers a compressor after an error. Reset itself allocates
no storage; block encoding can still allocate working storage and grow buffers.

```sh
swift test
swift run --package-path Benchmarks -c release ZlibBenchmarks --update-readme
```


## [Benchmarks against C zlib and methodology](Benchmarks/README.md).

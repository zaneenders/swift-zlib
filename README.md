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
checksums. It also recovers a compressor after an error.

`Deflater` allocates all working storage at initialization. In optimized builds,
successful `process` calls and `reset()` reuse it without heap allocation,
including `.needsOutput` backpressure and reuse after an abandoned stream.
Debug builds can allocate Swift runtime metadata on first use; throwing errors
can allocate Swift error storage in either configuration. Caller output storage
is separate; the one-shot `ZLib.deflate` and decoding APIs still allocate.

Storage is bounded independently of stream length. Each encoder reserves 98,303
input/history bytes and 132,094 output bytes, enough for a worst-case encoded
block plus framing. Compressed strategies also retain 768 KiB of match tables;
automatic and dynamic encoding reserve 65,535 tokens and all Huffman scratch.
Measured startup heap requests on Linux x86_64 with Swift 6.4.2 are approximately
225 KiB for `.stored`, 993 KiB for `.fixed`, and 2.53 MiB for `.automatic`/`.dynamic`,
excluding caller output buffers and allocator overhead.

```sh
swift test
Tests/AllocationProbe/check-allocations.sh  # Full release suite and allocation checks; Linux/glibc or macOS.
swift run --package-path Benchmarks -c release ZlibBenchmarks --update-readme
```


## [Benchmarks against C zlib and methodology](Benchmarks/README.md).

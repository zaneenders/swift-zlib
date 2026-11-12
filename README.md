# swift-zlib

Raw DEFLATE, zlib, and gzip compression and decompression written in pure Swift.
Requires Swift 6.4 and macOS 27 or later.

## Gzip

```swift
import Zlib

let input = Array("Hello, gzip!".utf8)
let compressed = try ZLib.deflate(
  input: input.span, format: .gzip, strategy: .dynamic)
let decoded = try ZLib.inflate(
  input: compressed.span, format: .gzip, maximumOutputSize: 1_048_576)
```

Compression supports `.stored`, `.fixed`, and `.dynamic` block strategies.
Gzip encoding produces one member with a reproducible header: no timestamp,
filename, or comment. Decoding accepts optional header fields and concatenated
members, validates header checksums when present and each member's CRC32 and
uncompressed size, and rejects truncation and trailing garbage. The output limit
applies to the combined size of all members.

Omitting `format` selects `.rawDeflate`, preserving the original API. Raw DEFLATE
has no container checksum and stops at the final block, ignoring trailing bytes
in the one-shot API.

## Zlib and Git objects

Use `format: .zlib` with the same compression and decompression APIs for an
RFC 1950 stream. Decoding validates the header, advertised window size, and
Adler-32 checksum. The one-shot decoder rejects trailing bytes; the incremental
decoder stops exactly after one stream and leaves trailing input unconsumed.
Preset dictionaries are currently rejected with `InflateError.unsupportedDictionary`.

Git loose objects use zlib framing. The standalone Swift package in
[Examples/GitObjects](Examples/GitObjects) demonstrates reading a loose-object
file and parsing its type, size, and binary contents:

```sh
swift run --package-path Examples/GitObjects git-object /path/to/repo/.git/objects/ab/cdef...
```

The example does not parse Git packfiles or verify object IDs.

## Incremental compression

`Deflater(format:strategy:)` accepts chunks through
`process(input:output:flush:)` and reports `inputConsumed`, `outputProduced`, and
a status. It supports all three formats and strategies, buffers input in blocks
of up to 65,535 bytes, and retains a 32 KiB compression history across blocks.
Only one encoded block waits for output capacity, so storage stays bounded as
the stream grows.

- `.none` accepts input and returns `.needsInput` when it needs another chunk.
  A partial block may stay buffered.
- `.sync` emits everything supplied so far and returns `.flushed`. A decoder
  can read that prefix immediately, and compression can continue with its history.
- `.finish` ends the stream, writes its checksum trailer, and returns `.finished`.

Any operation can return `.needsOutput`. Advance by `inputConsumed` and retry
with fresh output capacity. For a pending `.sync` or `.finish`, pass the same
flush value and exactly the unconsumed input suffix, even when it is empty.
Once that request completes, a sync-flushed stream can accept another chunk;
a finished stream cannot. Discard the compressor after an error.

```swift
let chunks = [Array("Hello, ".utf8), Array("streaming gzip!".utf8)]
var deflater = Deflater(format: .gzip, strategy: .dynamic)
var compressed: [UInt8] = []

for (index, chunk) in chunks.enumerated() {
  let flush: Deflater.Flush = index == chunks.count - 1 ? .finish : .none
  var offset = 0
  var status = Deflater.Status.needsOutput
  while status == .needsOutput {
    let bytes = try [UInt8](capacity: 4096) { output in
      let progress = try deflater.process(
        input: chunk.span.extracting(offset...), output: &output, flush: flush)
      offset += progress.inputConsumed
      status = progress.status
    }
    // A file or network writer can consume these bytes directly.
    compressed += bytes
  }
}
```

For an empty input source, call `.finish` with an empty span. Streaming and
one-shot compression may choose different block boundaries and compressed bytes.

## Incremental decompression

Create `Inflater(format: .gzip, maximumOutputSize: ...)` and call
`process(input:output:isFinalInput:)` with borrowed input and an `OutputSpan<UInt8>`.
Each call reports `inputConsumed`, `outputProduced`, and a status:

- `.needsInput`: supply more input; all supplied input was accepted.
- `.needsOutput`: supply writable output capacity and resubmit unconsumed input.
- `.finished`: decoding and all applicable checksum checks succeeded.

Set `isFinalInput: true` when no more input will arrive. Gzip waits for this signal
after a complete member because another member may follow. Header and trailer
parsing can continue even when output is full. Output is provisional until its
member's trailer is validated. After an error, discard the decoder.

## Checksums

`Adler32` and `CRC32` provide `checksum(input:)` for one-shot use, or `init()`,
`update(input:)`, and `value` for incremental use. They accept `Span<UInt8>` and
do not retain input storage.

## Validation

Run `swift test` for unit, streaming, and C zlib interoperability tests. Run
`swift run -c release ZlibBenchmarks` for the raw DEFLATE benchmarks.

# Git loose-object example

This standalone Swift package demonstrates reading Git loose-object files with
`swift-zlib`. It requires Swift 6.4 and macOS 27 or later, and uses the library
from the repository two directories above it.

From the repository root:

```sh
swift run --package-path Examples/GitObjects git-object --contents \
  .git/objects/47/ffad28222bfae57b23678042fd4ebd017aa581
```

The default output reports the object type and payload size. To write only the
binary payload to standard output:

```sh
swift run --package-path Examples/GitObjects git-object --contents /path/to/loose-object > contents.bin
```

The executable accepts a file path, not an object ID or Git revision. It exits
with a nonzero status and writes errors to standard error.

## Using the helper

[`LooseGitObject.swift`](Sources/GitObjectExample/LooseGitObject.swift) contains
the helper separately from the command-line entry point, so it can be copied
into an application that imports Foundation and Zlib:

```swift
let object = try readLooseGitObject(
  at: URL(fileURLWithPath: "/path/to/loose-object"),
  maximumDecodedSize: 16 * 1024 * 1024
)
print(object.type.rawValue)
let contents: Data = object.payload
```

Git stores loose objects as a zlib stream containing
`<type> <decimal-byte-size>\0<payload>`. The helper validates the zlib checksum,
rejects trailing compressed data, parses the canonical header, and checks the
declared size against the binary payload. See Git's
[object storage documentation](https://git-scm.com/book/en/v2/Git-Internals-Git-Objects#_object_storage).

The default decoded size limit is 64 MiB, including the header. The helper reads
the entire compressed file into memory and returns an owned payload copy. The
limit bounds decompressed bytes, not total process memory or compressed file size.

This example handles loose objects only. It does not read packfiles, resolve
revisions, verify SHA object IDs, or interpret tree, commit, and tag payloads.
Payloads remain binary; `--contents` does not pretty-print tree entries.

## Tests

```sh
swift test --package-path Examples/GitObjects
```

Tests use isolated temporary files and cover all four object types, binary and
empty payloads, malformed headers, size mismatches, trailing data, checksums,
and decoded size limits.

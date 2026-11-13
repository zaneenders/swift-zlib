# Swift vs C zlib

Swift `.automatic` vs system C zlib 1.2.12, level 6 (default strategy).
Speedup = C throughput / Swift throughput; above 1× favors C.

| Payload | C encode speedup | C decode speedup |
| --- | ---: | ---: |
| repeated | 1.36× | 10.71× |
| text | 1.37× | 15.12× |
| all-bytes | 1.42× | 22.92× |
| random | 1.91× | 477.69× |

Release build; median of 3 samples × 1000 calls.
Setup and allocations are timed; both decoders read identical raw DEFLATE bytes.

Apple M5 · macOS 27.0.1 · Swift 6.4.2.
Library: [`efeb826`](https://github.com/zaneenders/swift-zlib/commit/efeb826bb75adcc5ff8dbe6518947f5816f76d63).
Measured 2026-11-13T03:18:55Z.

Rerun from the repository root:

```sh
swift run --package-path Benchmarks -c release ZlibBenchmarks --update-readme
```

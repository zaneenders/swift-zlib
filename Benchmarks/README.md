# Swift vs C zlib

Swift `.automatic` vs system C zlib 1.2.12, level 6 (default strategy).
Both encoders receive identical input; decoded output is verified byte-for-byte against it.
Both decoders read the same C-generated DEFLATE bytes. Compressed encoder output may differ.

## 64 KiB

1000 calls per sample.

| Payload | Input | C encode vs Swift | C decode vs Swift |
| --- | --- | ---: | ---: |
| repeated | Repeated `Z` | 1.08× faster | 1.98× slower |
| text | Repeated text line | 1.09× faster | 1.08× faster |
| all-bytes | Cycling bytes 0–255 | 1.08× faster | 2.21× faster |
| random | Pseudorandom bytes | 1.25× faster | 1.63× faster |

## 64 MiB

1 call per sample.

| Payload | Input | C encode vs Swift | C decode vs Swift |
| --- | --- | ---: | ---: |
| repeated | Repeated `Z` | 1.27× slower | 1.46× slower |
| text | Repeated text line | 1.29× slower | 1.28× faster |
| all-bytes | Cycling bytes 0–255 | 1.34× slower | 3.19× faster |
| random | Pseudorandom bytes | 1.09× slower | 1.42× faster |

## 128 MiB

1 call per sample.

| Payload | Input | C encode vs Swift | C decode vs Swift |
| --- | --- | ---: | ---: |
| repeated | Repeated `Z` | 1.34× slower | 1.55× slower |
| text | Repeated text line | 1.33× slower | 1.28× faster |
| all-bytes | Cycling bytes 0–255 | 1.35× slower | 3.16× faster |
| random | Pseudorandom bytes | 1.08× slower | 1.41× faster |

Release build; median of 3 samples.
Setup and allocations are timed.

Apple M5 · macOS 27.0.1 · Swift 6.4.2.
Library: [`4113580`](https://github.com/zaneenders/swift-zlib/commit/411358088858d9c21a24ddd5ce730422908c9c6a) (modified sources).
Measured 2026-11-13T03:57:26Z.

Regenerate from the repository root:

```sh
swift run --package-path Benchmarks -c release ZlibBenchmarks --update-readme
```

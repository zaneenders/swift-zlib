# Swift vs C zlib — Silesia

All 12 original files from the [Silesia compression corpus](https://sun.aei.polsl.pl/~sdeor/index.php?page=silesia),
totaling 211,938,580 bytes. Each file is a separate raw DEFLATE stream, without repetition or padding.
System C zlib 1.2.12.
Both encoders receive identical input; decoded output is verified byte-for-byte against it.
Both decoders read the same C-generated DEFLATE bytes. Compressed encoder output may differ.

## Swift `.automatic` vs C level 6, Z_DEFAULT_STRATEGY

Compressed sizes are bytes, with percentage of input in parentheses (smaller is better).

| File | Input bytes | Calls/sample | Swift compressed | C compressed |
| --- | ---: | ---: | ---: | ---: |
| dickens | 10192446 | 6 | 3965304 (38.9%) | 3871628 (38.0%) |
| mozilla | 51220480 | 1 | 19321895 (37.7%) | 19089118 (37.3%) |
| mr | 9970564 | 6 | 3616952 (36.3%) | 3675935 (36.9%) |
| nci | 33553445 | 1 | 3445474 (10.3%) | 3200182 (9.5%) |
| ooffice | 6152192 | 10 | 3128335 (50.8%) | 3097288 (50.3%) |
| osdb | 10085684 | 6 | 3786766 (37.5%) | 3695164 (36.6%) |
| reymont | 6627202 | 9 | 1928151 (29.1%) | 1860865 (28.1%) |
| samba | 21606400 | 3 | 5540520 (25.6%) | 5451399 (25.2%) |
| sao | 7251944 | 9 | 5408259 (74.6%) | 5331793 (73.5%) |
| webster | 41458703 | 1 | 12564655 (30.3%) | 12213941 (29.5%) |
| xml | 5345280 | 12 | 711609 (13.3%) | 687991 (12.9%) |
| x-ray | 8474240 | 7 | 5957224 (70.3%) | 6045111 (71.3%) |
| **Total** | **211938580** | — | **69375144 (32.7%)** | **68220415 (32.2%)** |

Throughput is MiB/s of uncompressed input (higher is better).
Comparison columns name the faster implementation and its speedup.

| File | Swift encode | C encode | Faster encoder | Swift decode | C decode | Faster decoder |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| dickens | 35.50 | 33.77 | Swift 1.05× faster | 90.66 | 1157.64 | C 12.77× faster |
| mozilla | 66.88 | 45.58 | Swift 1.47× faster | 94.19 | 1034.58 | C 10.98× faster |
| mr | 51.58 | 36.68 | Swift 1.41× faster | 102.27 | 1134.12 | C 11.09× faster |
| nci | 133.98 | 146.11 | C 1.09× faster | 365.73 | 3636.36 | C 9.94× faster |
| ooffice | 46.85 | 36.08 | Swift 1.30× faster | 66.75 | 733.16 | C 10.98× faster |
| osdb | 87.29 | 69.29 | Swift 1.26× faster | 103.61 | 1260.55 | C 12.17× faster |
| reymont | 37.94 | 32.73 | Swift 1.16× faster | 118.46 | 1495.75 | C 12.63× faster |
| samba | 80.97 | 78.21 | Swift 1.04× faster | 140.36 | 1602.06 | C 11.41× faster |
| sao | 42.93 | 33.83 | Swift 1.27× faster | 50.86 | 685.90 | C 13.48× faster |
| webster | 52.74 | 53.27 | C 1.01× faster | 112.39 | 1323.85 | C 11.78× faster |
| xml | 107.56 | 112.70 | C 1.05× faster | 261.01 | 2851.14 | C 10.92× faster |
| x-ray | 47.49 | 44.80 | Swift 1.06× faster | 54.25 | 593.43 | C 10.94× faster |

Release build; median of 3 samples.
Calls per sample scale down from 1000 per 64 KiB, with a minimum of one call per file.
Codec setup, allocations, and teardown are timed. Downloading, file I/O, SHA-256 verification,
and correctness checks are outside the timed regions. Swift and C alternate which runs first.

Apple M5 · macOS 27.0.1 · Swift 6.4.2.
Library: [`ad3d04e`](https://github.com/zaneenders/swift-zlib/commit/ad3d04ec7b80c19beb959fa7cfbcaf2ee72efe0a).
Measured 2026-11-13T04:30:11Z.

Regenerate from the repository root (first run downloads about 65 MiB and caches the corpus in `Benchmarks/.build/silesia`):

```sh
swift run --package-path Benchmarks -c release ZlibBenchmarks --update-readme
```

Use `--corpus /path/to/silesia` for an existing uncompressed corpus; the same size and SHA-256 checks apply.
The default strategy is `automatic`; `--strategy all` also measures `stored`, `fixed`, and `dynamic`.
Omit `--update-readme` for CSV including exact compressed sizes, throughput, and comparison ratios.
For a quick correctness and timing pass, use `--iterations 1 --samples 1`.

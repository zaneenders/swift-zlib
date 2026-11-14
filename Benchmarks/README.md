# Swift vs C zlib — Silesia

All 12 original files from the [Silesia compression corpus](https://sun.aei.polsl.pl/~sdeor/index.php?page=silesia),
totaling 211,938,580 bytes. Each file is a separate raw DEFLATE stream, without repetition or padding.
System C zlib 1.2.12.
The recorded Swift search behavior is now named `.balanced`. The current CLI
supports `--effort fast|balanced|thorough|all`; effort and block strategy are
independent, and changing Swift effort does not change the C baseline's level.
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
| dickens | 35.15 | 33.25 | Swift 1.06× faster | 214.71 | 1154.62 | C 5.38× faster |
| mozilla | 66.53 | 45.15 | Swift 1.47× faster | 259.03 | 1024.89 | C 3.96× faster |
| mr | 50.99 | 36.31 | Swift 1.40× faster | 254.58 | 1126.78 | C 4.43× faster |
| nci | 133.49 | 144.99 | C 1.09× faster | 874.01 | 3648.85 | C 4.17× faster |
| ooffice | 46.56 | 35.82 | Swift 1.30× faster | 178.84 | 730.79 | C 4.09× faster |
| osdb | 87.80 | 69.20 | Swift 1.27× faster | 294.43 | 1259.53 | C 4.28× faster |
| reymont | 37.78 | 32.46 | Swift 1.16× faster | 286.04 | 1488.91 | C 5.21× faster |
| samba | 80.60 | 77.95 | Swift 1.03× faster | 373.51 | 1598.68 | C 4.28× faster |
| sao | 43.01 | 33.73 | Swift 1.27× faster | 172.46 | 685.69 | C 3.98× faster |
| webster | 52.58 | 53.24 | C 1.01× faster | 268.03 | 1322.85 | C 4.94× faster |
| xml | 107.08 | 112.46 | C 1.05× faster | 632.07 | 2858.72 | C 4.52× faster |
| x-ray | 47.98 | 44.96 | Swift 1.07× faster | 143.63 | 594.36 | C 4.14× faster |

Release build; median of 3 samples.
Calls per sample scale down from 1000 per 64 KiB, with a minimum of one call per file.
Codec setup, allocations, and teardown are timed. Downloading, file I/O, SHA-256 verification,
and correctness checks are outside the timed regions. Swift and C alternate which runs first.

Apple M5 · macOS 27.0.1 · Swift 6.4.2.
Library: [`0db4431`](https://github.com/zaneenders/swift-zlib/commit/0db44313eacc8150c23296e27dadc183cf5dcef5).
Measured 2026-11-13T05:16:04Z.

Regenerate from the repository root (first run downloads about 65 MiB and caches the corpus in `Benchmarks/.build/silesia`):

```sh
swift run --package-path Benchmarks -c release ZlibBenchmarks --update-readme
```

Use `--corpus /path/to/silesia` for an existing uncompressed corpus; the same size and SHA-256 checks apply.
The default strategy is `automatic`; `--strategy all` also measures `stored`, `fixed`, and `dynamic`.
Use `--effort all` to compare all Swift search settings, or select one with
`--effort fast`, `--effort balanced`, or `--effort thorough`. CSV includes an
`effort` column; Markdown groups results by strategy and effort. Reports include
the actual OS and CPU. Corpus validation uses the system `sha256sum` command
when CryptoKit is unavailable.
Omit `--update-readme` for CSV including exact compressed sizes, throughput, and comparison ratios.
For a quick correctness and timing pass, use `--iterations 1 --samples 1`.

On Linux, expose the system zlib headers through a Clang module map:

```sh
mkdir -p Benchmarks/.build/zlib-module
cat > Benchmarks/.build/zlib-module/module.modulemap <<'MAP'
module zlib [system] {
  header "/usr/include/zlib.h"
  link "z"
  export *
}
MAP
swift run --package-path Benchmarks -c release \
  -Xcc -fmodule-map-file="$PWD/Benchmarks/.build/zlib-module/module.modulemap" \
  ZlibBenchmarks --effort all --iterations 1 --samples 3
```

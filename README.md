# swift-zlib

zlib written in pure Swift

## Remaining work

- [ ] Add byte alignment to `BitReader`.
- [ ] Decode block headers and stored (uncompressed) blocks, validating their lengths.
- [ ] Decode fixed Huffman blocks into literals, lengths, and distances.
- [ ] Build and decode dynamic Huffman tables.
- [ ] Connect the components in an `Inflater` that resumes across input and output chunks.
- [ ] Add zlib header validation, dictionary-required errors, and Adler-32 verification.
- [ ] Compare against C zlib; test malformed input, truncation, chunk boundaries, and output limits.

Next milestone: decode a stored DEFLATE block end to end. Compression and gzip support can follow later.

Run tests with `swift test`. See [PLAN.md](PLAN.md) for the detailed roadmap.

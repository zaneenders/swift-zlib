/// Decompression operations for raw DEFLATE streams.
public enum ZLib: ~Sendable {
  /// Decompresses a raw DEFLATE stream containing stored or fixed Huffman blocks.
  /// Dynamic Huffman blocks are not supported yet.
  /// Returns a mutable array whose storage belongs to the caller.
  public static func inflate(input: borrowing Span<UInt8>) throws(BitReaderError) -> UniqueArray<UInt8> {
    var reader = BitReader(input.bytes)
    var output = UniqueArray<UInt8>(capacity: input.count)
    var history = HistoryWindow()

    inflateLoop: while true {
      let header = try reader.parseheader()
      switch header.bType {
      case .stored:
        let (length, _) = try reader.parseLenNLen()
        var block = PendingStoredBlock(length: length)
        output.reserveCapacity(output.count + Int(length))
        try output.edit { (span: inout OutputSpan<UInt8>) throws(BitReaderError) in
          _ = try block.emit(from: &reader, into: &span, history: &history)
        }
      case .fixedHuffman:
        fixedHuffmanLoop: while true {
          let code = try reader.readFixedLiteralLengthSymbol()
          switch code {
          case 0...255:
            let byte = UInt8(code)
            output.append(byte)
            history.appendLiteral(byte)
          case 256:
            break fixedHuffmanLoop
          case 257...285:
            let length = try reader.readMatchLength(symbol: code)
            let distance = try reader.readFixedMatchDistance()
            var match = PendingMatch(distance: Int(distance), length: Int(length))
            do {
              output.reserveCapacity(output.count + Int(length))
              try output.edit { (span: inout OutputSpan<UInt8>) throws(HistoryWindowError) in
                _ = try match.emit(into: &span, history: &history)
              }
            } catch {
              throw .invalid
            }
          default:
            throw .forbiddenSymbol
          }
        }
      default:
        throw .unsupportedBlockType
      }

      if header.isLastByte {
        return output
      }
    }
  }
}

/// Decompression operations for raw DEFLATE streams.
public enum ZLib: ~Sendable {
  /// Decompresses a raw DEFLATE stream containing stored or fixed Huffman blocks.
  /// Dynamic Huffman blocks are not supported yet.
  /// Returns a mutable array whose storage belongs to the caller.
  public static func inflate(input: borrowing Span<UInt8>) throws(BitReaderError) -> UniqueArray<UInt8> {
    var reader = BitReader(input.bytes)
    var output = UniqueArray<UInt8>(capacity: input.count)

    inflateLoop: while true {
      let header = try reader.parseheader()
      switch header.bType {
      case .stored:
        let (length, _) = try reader.parseLenNLen()
        for _ in 0..<Int(length) {
          output.append(UInt8(try reader.readBits(8)))
        }
      case .fixedHuffman:
        fixedHuffmanLoop: while true {
          let code = try reader.readFixedLiteralLengthSymbol()
          switch code {
          case 0...255:
            output.append(UInt8(code))
          case 256:
            break fixedHuffmanLoop
          case 257...285:
            let length = try reader.readMatchLength(symbol: code)
            let distance = try reader.readFixedMatchDistance()
            do {
              try output.appendMatch(distance: Int(distance), length: Int(length))
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

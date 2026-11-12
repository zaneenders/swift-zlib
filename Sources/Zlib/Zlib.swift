/// Compression and decompression operations for raw DEFLATE streams.
public enum ZLib: ~Sendable {
  /// Decompresses a raw DEFLATE stream containing stored, fixed, or dynamic Huffman blocks.
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
      case .dynamicHuffman:
        let tables = try reader.readDynamicHuffmanTables()
        dynamicHuffmanLoop: while true {
          let code = try tables.literalLength.readSymbol(from: &reader)
          switch code {
          case 0...255:
            output.append(UInt8(code))
          case 256:
            break dynamicHuffmanLoop
          case 257...285:
            let length = try reader.readMatchLength(symbol: code)
            let distanceSymbol = try tables.distance.readSymbol(from: &reader)
            let distance = try reader.readMatchDistance(symbol: distanceSymbol)
            do {
              try output.appendMatch(distance: Int(distance), length: Int(length))
            } catch {
              throw .invalid
            }
          default:
            throw .forbiddenSymbol
          }
        }
      case .invalid:
        throw .unsupportedBlockType
      }

      if header.isLastByte {
        return output
      }
    }
  }

  public enum Strategy: Sendable {
    case stored
    case fixed
    case dynamic
  }

  /// Compresses a raw DEFLATE stream using stored blocks or literal-only Huffman coding.
  public static func deflate(input: borrowing Span<UInt8>, strategy: Strategy) throws(BitWriterError) -> UniqueArray<
    UInt8
  > {
    switch strategy {
    case .stored:
      return try _deflateStored(input: input)
    case .fixed:
      return try _deflateFixed(input: input)
    case .dynamic:
      return try _deflateDynamic(input: input)
    }
  }

  private static func _deflateStored(input: borrowing Span<UInt8>) throws(BitWriterError) -> UniqueArray<UInt8> {
    var writer = BitWriter(minimumCapacity: input.count)
    var offset = 0
    repeat {
      let blockLength = min(input.count - offset, Int(UInt16.max))
      let end = offset + blockLength
      let isFinal = end == input.count
      writer.writeBits(isFinal ? 0b001 : 0b000, count: 3)
      writer.alignToByte()
      let length: UInt16 = UInt16(blockLength)
      writer.writeUInt16LittleEndian(length)
      writer.writeUInt16LittleEndian(~length)
      do {
        let section = input.bytes.extracting(offset..<end)
        for byte in section {
          writer.writeBits(byte, count: 8)
        }
      }
      offset += blockLength
    } while offset < input.count
    return writer.finish()
  }

  private static func _deflateFixed(input: borrowing Span<UInt8>) throws(BitWriterError) -> UniqueArray<UInt8> {
    var writer = BitWriter(minimumCapacity: input.count)
    writer.writeBits(0b011, count: 3)
    for byte in input {
      try writer.writeFixedLiteralLengthSymbol(UInt32(byte))
    }
    try writer.writeFixedLiteralLengthSymbol(UInt32(256))
    return writer.finish()
  }

  private static func _deflateDynamic(input: borrowing Span<UInt8>) throws(BitWriterError) -> UniqueArray<UInt8> {
    var counts = [Int](repeating: 0, count: 257)
    for byte in input {
      counts[Int(byte)] += 1
    }
    counts[256] = 1

    let lengths = huffmanCodeLengths(frequencies: counts, maxBits: 15)
    let codes = canonicalHuffmanCodes(lengths: lengths)
    var writer = BitWriter(minimumCapacity: input.count)

    writer.writeBits(0b101, count: 3)  // Final block, dynamic Huffman coding.
    // A one-bit distance code describes an unused distance alphabet for literals.
    writer.writeDynamicHuffmanHeader(literalLengths: lengths, distanceLengths: [1])
    for byte in input {
      let symbol = Int(byte)
      writer.writeHuffmanCode(codes[symbol]!, bitCount: lengths[symbol])
    }
    writer.writeHuffmanCode(codes[256]!, bitCount: lengths[256])
    return writer.finish()
  }
}

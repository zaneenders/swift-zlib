struct BitWriter: ~Copyable {
  private var output: UniqueArray<UInt8>
  private var currentByte: UInt8 = 0
  private var bitOffset = 0

  init(minimumCapacity: Int) {
    self.output = UniqueArray<UInt8>(minimumCapacity: minimumCapacity)
  }

  mutating func writeBit(_ bit: UInt8) throws(BitWriterError) {
    guard bit == 0 || bit == 1 else {
      throw BitWriterError.invalidBit
    }
    writeBits(bit, count: 1)
  }

  /// Writes the low `bitCount` bits of a code, most significant bit first.
  mutating func writeHuffmanCode(_ code: UInt16, bitCount: Int) {
    precondition((0...UInt16.bitWidth).contains(bitCount), "Invalid Huffman code bit count")

    for index in (0..<bitCount).reversed() {
      let bit = UInt8((code >> index) & 1)
      writeBits(bit, count: 1)
    }
  }

  mutating func writeFixedLiteralLengthSymbol(_ symbol: UInt32) throws(BitWriterError) {
    let code: UInt32
    let bitCount: UInt8

    switch symbol {
    case 0...143:
      bitCount = 8
      code = 0b00110000 + symbol
    case 144...255:
      bitCount = 9
      code = 0b110010000 + (symbol - 144)
    case 256...279:
      bitCount = 7
      code = symbol - 256
    case 280...285:
      bitCount = 8
      code = 0b11000000 + (symbol - 280)
    default:
      throw BitWriterError.reserved
    }

    writeHuffmanCode(UInt16(code), bitCount: Int(bitCount))
  }

  mutating func writeBits(_ bits: UInt8, count: Int) {
    var bits = bits
    for _ in 0..<count {
      if bitOffset == 8 {
        output.append(currentByte)
        currentByte = 0
        bitOffset = 0
      }
      var bit = bits & 1
      bits >>= 1
      bit <<= bitOffset
      currentByte |= bit
      bitOffset += 1
    }
  }

  mutating func alignToByte() {
    if bitOffset != 0 {
      output.append(currentByte)
      currentByte = 0
      bitOffset = 0
    }
  }

  consuming func finish() -> UniqueArray<UInt8> {
    alignToByte()
    return output
  }

  mutating func writeUInt16LittleEndian(_ value: UInt16) {
    let low = UInt8(value & 0xFF)
    let high = UInt8(value >> 8)
    writeBits(low, count: 8)
    writeBits(high, count: 8)
  }
}

public enum BitWriterError: Error {
  case inputToLong
  case invalidBit
  case reserved
}

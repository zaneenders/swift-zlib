import zlib

// Include stream setup, output allocation, and teardown in each one-shot call,
// just as the Swift API does. Use uninitialized storage to avoid timing an
// extra zero-fill or a copy of the completed output in the C baseline.
func cZlibDeflate(
  _ input: borrowing Span<UInt8>, level: Int32, strategy: Int32
) -> UniqueArray<UInt8> {
  var stream = z_stream()
  let initialized = deflateInit2_(
    &stream, level, Z_DEFLATED, -MAX_WBITS, 8, strategy,
    ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
  precondition(initialized == Z_OK, "C zlib deflate initialization failed: \(initialized)")
  defer { precondition(deflateEnd(&stream) == Z_OK) }

  var output = UniqueArray<UInt8>(minimumCapacity: Int(deflateBound(&stream, uLong(input.count))))
  input.withUnsafeBufferPointer { source in
    stream.next_in = UnsafeMutablePointer(mutating: source.baseAddress)
    stream.avail_in = uInt(source.count)
    output.edit { span in
      span.withUnsafeMutableBufferPointer { destination, initializedCount in
        stream.next_out = destination.baseAddress
        stream.avail_out = uInt(destination.count)
        let status = zlib.deflate(&stream, Z_FINISH)
        initializedCount = Int(stream.total_out)
        precondition(status == Z_STREAM_END && stream.avail_in == 0, "C zlib deflate failed: \(status)")
      }
    }
  }
  return output
}

func cZlibInflate(_ input: borrowing Span<UInt8>) -> UniqueArray<UInt8> {
  var stream = z_stream()
  let initialized = inflateInit2_(
    &stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
  precondition(initialized == Z_OK, "C zlib inflate initialization failed: \(initialized)")
  defer { precondition(inflateEnd(&stream) == Z_OK) }

  // Match ZLib.inflate's initial capacity and geometric growth. Neither
  // decoder gets the uncompressed size in advance.
  var output = UniqueArray<UInt8>(minimumCapacity: min(input.count, 65_536))
  input.withUnsafeBufferPointer { source in
    stream.next_in = UnsafeMutablePointer(mutating: source.baseAddress)
    stream.avail_in = uInt(source.count)
    while true {
      let status = output.edit { span in
        span.withUnsafeMutableBufferPointer { destination, initializedCount in
          let available = destination.count - initializedCount
          stream.next_out = destination.baseAddress?.advanced(by: initializedCount)
          stream.avail_out = uInt(available)
          let status = zlib.inflate(&stream, Z_NO_FLUSH)
          initializedCount += available - Int(stream.avail_out)
          return status
        }
      }
      if status == Z_STREAM_END {
        precondition(stream.avail_in == 0)
        break
      }
      precondition(status == Z_OK && stream.avail_out == 0, "C zlib inflate failed: \(status)")
      output.reserveCapacity(output.capacity + max(1, output.capacity))
    }
  }
  return output
}

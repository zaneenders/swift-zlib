import Zlib
import zlib

enum BenchmarkStrategy: String, CaseIterable {
  case automatic
  case stored
  case fixed
  case dynamic

  var swift: ZLib.Strategy {
    switch self {
    case .automatic: .automatic
    case .stored: .stored
    case .fixed: .fixed
    case .dynamic: .dynamic
    }
  }

  var cLevel: Int32 { self == .stored ? Z_NO_COMPRESSION : 6 }
  var cStrategy: Int32 { self == .fixed ? Z_FIXED : Z_DEFAULT_STRATEGY }
  var cStrategyName: String { self == .fixed ? "Z_FIXED" : "Z_DEFAULT_STRATEGY" }
}

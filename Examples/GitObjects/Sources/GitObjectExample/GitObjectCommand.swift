import Darwin
import Foundation

@main
enum GitObjectCommand {
  private static let usage = "Usage: git-object [--contents] PATH"

  static func main() {
    var arguments = Array(CommandLine.arguments.dropFirst())
    if arguments == ["--help"] || arguments == ["-h"] {
      print(usage)
      return
    }
    let contentsOnly = arguments.first == "--contents"
    if contentsOnly {
      arguments.removeFirst()
    }
    guard arguments.count == 1 else {
      fail(usage)
    }

    do {
      let object = try readLooseGitObject(at: URL(fileURLWithPath: arguments[0]))
      if contentsOnly {
        try FileHandle.standardOutput.write(contentsOf: object.payload)
      } else {
        print("type: \(object.type.rawValue)")
        print("size: \(object.payload.count) bytes")
      }
    } catch {
      let message = (error as? any LocalizedError)?.errorDescription ?? String(describing: error)
      fail("git-object: \(message)")
    }
  }

  private static func fail(_ message: String) -> Never {
    try? FileHandle.standardError.write(contentsOf: Data("\(message)\n".utf8))
    exit(EXIT_FAILURE)
  }
}

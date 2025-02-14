//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
import LanguageServerProtocol
import SKCore

extension Language {
  var fileExtension: String {
    switch self {
    case .objective_c: return "m"
    default: return self.rawValue
    }
  }

  init?(fileExtension: String) {
    switch fileExtension {
    case "m": self = .objective_c
    default: self.init(rawValue: fileExtension)
    }
  }
}

extension DocumentURI {
  /// Create a unique URI for a document of the given language.
  public static func `for`(_ language: Language, testName: String = #function) -> DocumentURI {
    let testBaseName = testName.prefix(while: \.isLetter)

    #if os(Windows)
    let url = URL(fileURLWithPath: "C:/\(testBaseName)/\(UUID())/test.\(language.fileExtension)")
    #else
    let url = URL(fileURLWithPath: "/\(testBaseName)/\(UUID())/test.\(language.fileExtension)")
    #endif
    return DocumentURI(url)
  }
}

public let cleanScratchDirectories = (ProcessInfo.processInfo.environment["SOURCEKITLSP_KEEP_TEST_SCRATCH_DIR"] == nil)

/// An empty directory in which a test with `#function` name `testName` can store temporary data.
public func testScratchDir(testName: String = #function) throws -> URL {
  let testBaseName = testName.prefix(while: \.isLetter)

  var uuid = UUID().uuidString[...]
  if let firstDash = uuid.firstIndex(of: "-") {
    uuid = uuid[..<firstDash]
  }
  let url = FileManager.default.temporaryDirectory
    .realpath
    .appendingPathComponent("sourcekit-lsp-test-scratch")
    .appendingPathComponent("\(testBaseName)-\(uuid)")
  try? FileManager.default.removeItem(at: url)
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}

fileprivate extension URL {
  /// Assuming this is a file URL, resolves all symlinks in the path.
  ///
  /// - Note: We need this because `URL.resolvingSymlinksInPath()` not only resolves symlinks but also standardizes the
  ///   path by stripping away `private` prefixes. Since sourcekitd is not performing this standardization, using
  ///   `resolvingSymlinksInPath` can lead to slightly mismatched URLs between the sourcekit-lsp response and the test
  ///   assertion.
  var realpath: URL {
    #if canImport(Darwin)
    return self.path.withCString { path in
      guard let realpath = Darwin.realpath(path, nil) else {
        return self
      }
      let result = URL(fileURLWithPath: String(cString: realpath))
      free(realpath)
      return result
    }
    #else
    // Non-Darwin platforms don't have the `/private` stripping issue, so we can just use `self.resolvingSymlinksInPath`
    // here.
    return self.resolvingSymlinksInPath()
    #endif
  }
}

public let hasClangd = ToolchainRegistry.shared.default?.clangd != nil

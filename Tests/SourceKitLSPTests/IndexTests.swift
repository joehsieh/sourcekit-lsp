//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import LanguageServerProtocol
import SKTestSupport
import XCTest

final class IndexTests: XCTestCase {
  func testIndexSwiftModules() async throws {
    let ws = try await SwiftPMTestWorkspace(
      files: [
        "LibA/LibA.swift": """
        public func 1️⃣aaa() {}
        """,
        "LibB/LibB.swift": """
        import LibA
        public func bbb() {
          2️⃣aaa()
        }
        """,
        "LibC/LibC.swift": """
        import LibA
        public func ccc() {
          3️⃣aaa()
        }
        """,
      ],
      manifest: """
        // swift-tools-version: 5.7

        import PackageDescription

        let package = Package(
          name: "MyLibrary",
          targets: [
           .target(name: "LibA"),
           .target(name: "LibB", dependencies: ["LibA"]),
           .target(name: "LibC", dependencies: ["LibA", "LibB"]),
          ]
        )
        """,
      build: true
    )

    let (libAUri, libAPositions) = try ws.openDocument("LibA.swift")
    let libBUri = try ws.uri(for: "LibB.swift")
    let (libCUri, libCPositions) = try ws.openDocument("LibC.swift")

    let definitionPos = libAPositions["1️⃣"]
    let referencePos = try ws.position(of: "2️⃣", in: "LibB.swift")
    let callPos = libCPositions["3️⃣"]

    // MARK: Jump to definition

    let response = try await ws.testClient.send(
      DefinitionRequest(
        textDocument: TextDocumentIdentifier(libCUri),
        position: libCPositions["3️⃣"]
      )
    )
    guard case .locations(let jump) = response else {
      XCTFail("Response is not locations")
      return
    }

    XCTAssertEqual(jump.count, 1)
    XCTAssertEqual(jump.first?.uri, libAUri)
    XCTAssertEqual(jump.first?.range.lowerBound, definitionPos)

    // MARK: Find references

    let refs = try await ws.testClient.send(
      ReferencesRequest(
        textDocument: TextDocumentIdentifier(libAUri),
        position: definitionPos,
        context: ReferencesContext(includeDeclaration: true)
      )
    )

    XCTAssertEqual(
      Set(refs),
      [
        Location(
          uri: libAUri,
          range: Range(definitionPos)
        ),
        Location(
          uri: libBUri,
          range: Range(referencePos)
        ),
        Location(
          uri: libCUri,
          range: Range(callPos)
        ),
      ]
    )
  }

  func testIndexShutdown() async throws {

    func listdir(_ url: URL) throws -> [URL] {
      try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
    }

    func checkRunningIndex(cleanUp: Bool, workspaceDirectory: URL) async throws -> URL? {
      let ws = try await IndexedSingleSwiftFileWorkspace(
        """
        func 1️⃣foo() {}

        func bar() {
          2️⃣foo()
        }
        """,
        cleanUp: cleanUp
      )

      let response = try await ws.testClient.send(
        DefinitionRequest(
          textDocument: TextDocumentIdentifier(ws.fileURI),
          position: ws.positions["2️⃣"]
        )
      )
      guard case .locations(let jump) = response else {
        XCTFail("Response is not locations")
        return nil
      }
      XCTAssertEqual(jump.count, 1)
      XCTAssertEqual(jump.first?.uri, ws.fileURI)
      XCTAssertEqual(jump.first?.range.lowerBound, ws.positions["1️⃣"])

      let tmpContents = try listdir(ws.indexDBURL)
      guard let versionedPath = tmpContents.filter({ $0.lastPathComponent.starts(with: "v") }).spm_only else {
        XCTFail("expected one version path 'v[0-9]*', found \(tmpContents)")
        return nil
      }

      let versionContentsBefore = try listdir(versionedPath)
      XCTAssertEqual(versionContentsBefore.count, 1)
      XCTAssert(versionContentsBefore.first?.lastPathComponent.starts(with: "p") ?? false)

      _ = try await ws.testClient.send(ShutdownRequest())
      return versionedPath
    }

    let workspaceDirectory = try testScratchDir()

    guard let versionedPath = try await checkRunningIndex(cleanUp: false, workspaceDirectory: workspaceDirectory) else {
      return
    }

    let versionContentsAfter = try listdir(versionedPath)
    XCTAssertEqual(versionContentsAfter.count, 1)
    XCTAssertEqual(versionContentsAfter.first?.lastPathComponent, "saved")

    _ = try await checkRunningIndex(cleanUp: true, workspaceDirectory: workspaceDirectory)
  }
}

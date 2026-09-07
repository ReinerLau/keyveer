import Foundation
import XCTest

@testable import KeyveerApp

final class ConfigurationFileSupportTests: XCTestCase {
  func testEnsureExistsCreatesDefaultConfigurationAndParentDirectory() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("keyveer-config-test-\(UUID().uuidString)")
    let url = root.appendingPathComponent("Keyveer/config.json")
    defer { try? FileManager.default.removeItem(at: root) }

    try ConfigurationFileSupport.ensureExists(at: url)

    XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    XCTAssertEqual(object["schemaVersion"] as? Int, 3)
  }

  func testEnsureExistsDoesNotOverwriteExistingConfiguration() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("keyveer-config-test-\(UUID().uuidString)")
    let url = root.appendingPathComponent("Keyveer/config.json")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let existing = Data("{\"schemaVersion\":99}".utf8)
    try existing.write(to: url)

    try ConfigurationFileSupport.ensureExists(at: url)

    XCTAssertEqual(try Data(contentsOf: url), existing)
  }
}

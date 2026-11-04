import Foundation
import Testing
@testable import Gentizer

@Test func versionMatchesVersionFile() throws {
    let file = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("VERSION")
    let text = try String(contentsOf: file, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    #expect(text == Gentizer.version)
}

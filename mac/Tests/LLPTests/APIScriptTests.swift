import Foundation
import XCTest

final class APIScriptTests: XCTestCase {
    func testSharedContractPassedToValidator() throws {
        try checkValidation(contract: "local contract", expectedStatus: 0)
    }

    func testMissingSharedContractStopsValidation() throws {
        try checkValidation(contract: nil, expectedStatus: 1)
    }

    func testEmptySharedContractStopsValidation() throws {
        try checkValidation(contract: "", expectedStatus: 1)
    }

    private func checkValidation(contract: String?, expectedStatus: Int32) throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let mac = root.appendingPathComponent("mac")
        let scripts = mac.appendingPathComponent("scripts")
        let common = root.appendingPathComponent("common/apis")
        for directory in [scripts, common, mac.appendingPathComponent("apis")] {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let package = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for name in ["common.sh", "validate-api.sh"] {
            try fm.copyItem(at: package.appendingPathComponent("scripts/" + name),
                            to: scripts.appendingPathComponent(name))
        }
        try "API 1.0.0\n".write(to: mac.appendingPathComponent("api-version"), atomically: true, encoding: .utf8)
        // A stale copy must never substitute for the shared contract.
        let destination = mac.appendingPathComponent("apis/llp-apis.yaml")
        try "previous".write(to: destination, atomically: true, encoding: .utf8)
        if let contract {
            try contract.write(to: common.appendingPathComponent("llp-apis.yaml"), atomically: true, encoding: .utf8)
        }
        let marker = root.appendingPathComponent("validated")
        let python = root.appendingPathComponent("validator-stub")
        try """
        #!/bin/bash
        set -eu
        [ "$1" = "\(scripts.path)/validate-api.py" ]
        [ "$2" = "\(mac.path)/../common/apis/llp-apis.yaml" ]
        [ "$3" = "1.0.0" ]
        /bin/cat "$2" > "\(marker.path)"
        """.write(to: python, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: python.path)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scripts.appendingPathComponent("validate-api.sh").path]
        process.currentDirectoryURL = root
        process.environment = ["PATH": "/usr/bin:/bin", "HOME": root.path, "LLP_API_PYTHON": python.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, expectedStatus)
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8),
                       "previous")
        if expectedStatus == 0 {
            XCTAssertEqual(try String(contentsOf: marker, encoding: .utf8), contract)
        } else {
            XCTAssertFalse(fm.fileExists(atPath: marker.path))
        }
    }
}

import XCTest
@testable import PortMonitor

final class PortScannerTests: XCTestCase {
    func testParsesAndGroupsListeningPorts() {
        let sample = """
        p123
        cnode
        Lwilson
        f10
        PTCP
        n*:3000
        TST=LISTEN
        f11
        PTCP
        n127.0.0.1:3001
        TST=LISTEN
        p456
        cdns-service
        Lroot
        f4
        PUDP
        n*:5353
        """

        let result = PortScanner.parse(sample)

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].pid, 123)
        XCTAssertEqual(result[0].command, "node")
        XCTAssertEqual(result[0].user, "wilson")
        XCTAssertEqual(result[0].endpoints.map(\.port), [3000, 3001])
        XCTAssertEqual(result[1].endpoints.first?.protocolName, "UDP")
    }

    func testIgnoresWildcardAndInvalidPorts() {
        let sample = """
        p123
        cservice
        Lwilson
        f10
        PUDP
        n*:*
        f11
        PTCP
        n*:70000
        """

        XCTAssertTrue(PortScanner.parse(sample).isEmpty)
    }

    func testPortLabelDeduplicatesIPv4AndIPv6Listeners() {
        let sample = """
        p123
        cserver
        Lwilson
        f10
        PTCP
        n*:8080
        f11
        PTCP
        n[::]:8080
        """

        let process = PortScanner.parse(sample).first
        XCTAssertEqual(process?.endpoints.count, 2)
        XCTAssertEqual(process?.portsLabel, "8080/TCP")
    }

    func testLiveScanCompletes() async throws {
        _ = try await PortScanner.scan()
    }
}

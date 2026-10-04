import Foundation

struct ListeningEndpoint: Hashable, Identifiable, Sendable {
    let protocolName: String
    let address: String
    let port: Int

    var id: String { "\(protocolName):\(address):\(port)" }
}

struct ListeningProcess: Identifiable, Hashable, Sendable {
    let pid: Int32
    let command: String
    let user: String
    let endpoints: [ListeningEndpoint]

    var id: Int32 { pid }
    var isRoot: Bool { user == "root" }

    var portsLabel: String {
        var seen = Set<String>()
        return endpoints.compactMap { endpoint in
            let label = "\(endpoint.port)/\(endpoint.protocolName)"
            return seen.insert(label).inserted ? label : nil
        }.joined(separator: ", ")
    }
}

enum TerminationSignal: Int32, Sendable {
    case terminate = 15
    case kill = 9

    var title: String {
        switch self {
        case .terminate: return "Stop"
        case .kill: return "Force Quit"
        }
    }
}

struct KillRequest: Sendable {
    let process: ListeningProcess
    let signal: TerminationSignal
}

enum ProcessProtection {
    static let protectedCommands: Set<String> = [
        "kernel_task",
        "launchd",
        "WindowServer",
        "loginwindow",
        "securityd",
        "authd",
        "opendirectoryd",
        "configd",
        "diskarbitrationd",
        "mDNSResponder"
    ]

    static func reason(for process: ListeningProcess) -> String? {
        if process.pid <= 1 {
            return "Essential macOS process"
        }
        if process.pid == ProcessInfo.processInfo.processIdentifier {
            return "Port Monitor cannot stop itself"
        }
        if protectedCommands.contains(process.command) {
            return "Protected macOS service"
        }
        return nil
    }
}

import Foundation

enum PortScannerError: LocalizedError {
    case launchFailed(String)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .launchFailed(let message): return "Unable to launch lsof: \(message)"
        case .commandFailed(let message): return "Port scan failed: \(message)"
        }
    }
}

enum PortScanner {
    static func scan() async throws -> [ListeningProcess] {
        try await Task.detached(priority: .utility) {
            try scanSynchronously()
        }.value
    }

    static func scanSynchronously() throws -> [ListeningProcess] {
        let task = Process()
        let output = Pipe()
        let errors = Pipe()

        task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        task.arguments = ["-nP", "-iTCP", "-sTCP:LISTEN", "-iUDP", "-FpcLPnT"]
        task.standardOutput = output
        task.standardError = errors

        do {
            try task.run()
        } catch {
            throw PortScannerError.launchFailed(error.localizedDescription)
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        // lsof returns 1 when no matching socket exists.
        guard task.terminationStatus == 0 || task.terminationStatus == 1 else {
            let message = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw PortScannerError.commandFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let text = String(data: data, encoding: .utf8) ?? ""
        return parse(text)
    }

    static func parse(_ text: String) -> [ListeningProcess] {
        struct Partial {
            var command = "Unknown process"
            var user = "unknown"
            var endpoints = Set<ListeningEndpoint>()
        }

        var records: [Int32: Partial] = [:]
        var currentPID: Int32?
        var currentProtocol: String?

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            guard let field = line.first else { continue }
            let value = String(line.dropFirst())

            switch field {
            case "p":
                currentPID = Int32(value)
                currentProtocol = nil
                if let pid = currentPID, records[pid] == nil {
                    records[pid] = Partial()
                }
            case "c":
                if let pid = currentPID { records[pid]?.command = value }
            case "L":
                if let pid = currentPID { records[pid]?.user = value }
            case "P":
                currentProtocol = value.uppercased()
            case "n":
                guard
                    let pid = currentPID,
                    let protocolName = currentProtocol,
                    let endpoint = parseEndpoint(value, protocolName: protocolName)
                else { continue }
                records[pid]?.endpoints.insert(endpoint)
            default:
                continue
            }
        }

        return records.compactMap { pid, partial in
            guard !partial.endpoints.isEmpty else { return nil }
            let endpoints = partial.endpoints.sorted {
                if $0.port != $1.port { return $0.port < $1.port }
                if $0.protocolName != $1.protocolName { return $0.protocolName < $1.protocolName }
                return $0.address < $1.address
            }
            return ListeningProcess(
                pid: pid,
                command: partial.command,
                user: partial.user,
                endpoints: endpoints
            )
        }.sorted {
            let leftPort = $0.endpoints.first?.port ?? .max
            let rightPort = $1.endpoints.first?.port ?? .max
            if leftPort != rightPort { return leftPort < rightPort }
            return $0.command.localizedCaseInsensitiveCompare($1.command) == .orderedAscending
        }
    }

    private static func parseEndpoint(_ value: String, protocolName: String) -> ListeningEndpoint? {
        let localPart = value.components(separatedBy: "->").first ?? value
        guard let colon = localPart.lastIndex(of: ":") else { return nil }

        let portText = localPart[localPart.index(after: colon)...]
        guard let port = Int(portText), (1...65535).contains(port) else { return nil }

        var address = String(localPart[..<colon])
        if address.hasPrefix("[") && address.hasSuffix("]") {
            address.removeFirst()
            address.removeLast()
        }

        return ListeningEndpoint(protocolName: protocolName, address: address, port: port)
    }
}

import Darwin
import Foundation

enum TerminationResult: Sendable {
    case success
    case permissionDenied
    case processChanged
    case protected(String)
    case failed(String)
}

enum ProcessController {
    static func terminate(_ request: KillRequest, elevated: Bool) async -> TerminationResult {
        await Task.detached(priority: .userInitiated) {
            guard ProcessProtection.reason(for: request.process) == nil else {
                return .protected(ProcessProtection.reason(for: request.process)!)
            }

            guard processStillMatches(request.process) else {
                return .processChanged
            }

            if elevated {
                return terminateWithAdministratorPrivileges(request)
            }

            errno = 0
            if Darwin.kill(request.process.pid, request.signal.rawValue) == 0 {
                return .success
            }

            switch errno {
            case EPERM: return .permissionDenied
            case ESRCH: return .processChanged
            default: return .failed(String(cString: strerror(errno)))
            }
        }.value
    }

    private static func processStillMatches(_ expected: ListeningProcess) -> Bool {
        guard let current = try? PortScanner.scanSynchronously().first(where: { $0.pid == expected.pid }) else {
            return false
        }

        let expectedPorts = Set(expected.endpoints.map { "\($0.protocolName):\($0.port)" })
        let currentPorts = Set(current.endpoints.map { "\($0.protocolName):\($0.port)" })
        return current.command == expected.command && !expectedPorts.isDisjoint(with: currentPorts)
    }

    private static func terminateWithAdministratorPrivileges(_ request: KillRequest) -> TerminationResult {
        // PID and signal are strongly typed integers, so no user-controlled shell text is interpolated.
        let command = "/bin/kill -\(request.signal.rawValue) \(request.process.pid)"
        let script = "do shell script \"\(command)\" with administrator privileges"
        let task = Process()
        let errors = Pipe()

        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]
        task.standardError = errors

        do {
            try task.run()
            let errorData = errors.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()

            if task.terminationStatus == 0 { return .success }

            let message = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return .failed(message?.isEmpty == false ? message! : "Authorization denied")
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}

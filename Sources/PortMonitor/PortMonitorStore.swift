import Foundation

@MainActor
final class PortMonitorStore: ObservableObject {
    enum Dialog: Identifiable {
        case confirm(KillRequest)
        case confirmAdministrator(KillRequest)
        case message(title: String, text: String)

        var id: String {
            switch self {
            case .confirm(let request): return "confirm-\(request.process.pid)-\(request.signal.rawValue)"
            case .confirmAdministrator(let request): return "admin-\(request.process.pid)-\(request.signal.rawValue)"
            case .message(let title, let text): return "message-\(title)-\(text)"
            }
        }
    }

    @Published private(set) var processes: [ListeningProcess] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastUpdated: Date?
    @Published var searchText = ""
    @Published var dialog: Dialog?

    var filteredProcesses: [ListeningProcess] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return processes }

        return processes.filter { process in
            process.command.localizedCaseInsensitiveContains(query)
                || process.user.localizedCaseInsensitiveContains(query)
                || process.endpoints.contains { String($0.port).contains(query) }
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            processes = try await PortScanner.scan()
            lastUpdated = Date()
        } catch {
            dialog = .message(title: "Unable to Scan", text: error.localizedDescription)
        }
    }

    func request(_ signal: TerminationSignal, for process: ListeningProcess) {
        if let reason = ProcessProtection.reason(for: process) {
            dialog = .message(title: "Protected Process", text: reason)
            return
        }
        dialog = .confirm(KillRequest(process: process, signal: signal))
    }

    func execute(_ request: KillRequest, elevated: Bool = false) async {
        let result = await ProcessController.terminate(request, elevated: elevated)

        switch result {
        case .success:
            try? await Task.sleep(nanoseconds: 350_000_000)
            await refresh()
        case .permissionDenied:
            dialog = .confirmAdministrator(request)
        case .processChanged:
            dialog = .message(
                title: "Process Changed",
                text: "The process or its ports changed. The list was refreshed without sending a signal."
            )
            await refresh()
        case .protected(let reason):
            dialog = .message(title: "Protected Process", text: reason)
        case .failed(let message):
            dialog = .message(title: "Unable to Stop Process", text: message)
            await refresh()
        }
    }
}

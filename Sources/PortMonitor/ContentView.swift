import SwiftUI

struct ContentView: View {
    @ObservedObject var store: PortMonitorStore
    private let timer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                header
                Divider()

                if store.filteredProcesses.isEmpty {
                    emptyState
                } else {
                    processList
                }

                Divider()
                footer
            }
            .allowsHitTesting(store.dialog == nil)

            if let dialog = store.dialog {
                Color.black.opacity(0.38)
                    .ignoresSafeArea()

                DialogCard(dialog: dialog, store: store)
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
            }
        }
        .frame(width: 500, height: 540)
        .animation(.easeOut(duration: 0.12), value: store.dialog?.id)
        .task { await store.refresh() }
        .onReceive(timer) { _ in
            Task { await store.refresh() }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack {
                Label("Listening Ports", systemImage: "network")
                    .font(.headline)
                Spacer()
                if store.isRefreshing {
                    ProgressView().controlSize(.small)
                }
                Button {
                    Task { await store.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh")
            }

            TextField("Search port, process, or user", text: $store.searchText)
                .textFieldStyle(.roundedBorder)
        }
        .padding(14)
    }

    private var processList: some View {
        List(store.filteredProcesses) { process in
            ProcessRow(process: process) { signal in
                store.request(signal, for: process)
            }
        }
        .listStyle(.inset)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: store.searchText.isEmpty ? "network.slash" : "magnifyingglass")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
            Text(store.searchText.isEmpty ? "No listening ports" : "No results")
                .font(.headline)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        HStack {
            if let date = store.lastUpdated {
                Text("Updated at \(date.formatted(date: .omitted, time: .standard))")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

}

private struct DialogCard: View {
    let dialog: PortMonitorStore.Dialog
    @ObservedObject var store: PortMonitorStore

    private var title: String {
        switch dialog {
        case .confirm(let request):
            return "\(request.signal.title) \(request.process.command)?"
        case .confirmAdministrator:
            return "Administrator Authorization Required"
        case .message(let title, _):
            return title
        }
    }

    private var message: String {
        switch dialog {
        case .confirm(let request):
            let rootWarning = request.process.isRoot
                ? " This process belongs to root and will probably require administrator authorization."
                : ""
            let dockerWarning = request.process.command.localizedCaseInsensitiveContains("docker")
                ? " Warning: this may interrupt multiple Docker containers."
                : ""
            return "PID \(request.process.pid), ports \(request.process.portsLabel).\(rootWarning)\(dockerWarning)"
        case .confirmAdministrator(let request):
            return "macOS will ask for your password to stop \(request.process.command) (PID \(request.process.pid))."
        case .message(_, let text):
            return text
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(.title3.weight(.semibold))

            Text(message)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Spacer()
                buttons
            }
        }
        .padding(22)
        .frame(width: 360)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.10))
        }
        .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
    }

    @ViewBuilder
    private var buttons: some View {
        switch dialog {
        case .confirm(let request):
            Button("Cancel") { store.dialog = nil }
                .keyboardShortcut(.cancelAction)
            Button(request.signal.title, role: .destructive) {
                store.dialog = nil
                Task { await store.execute(request) }
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .keyboardShortcut(.defaultAction)
        case .confirmAdministrator(let request):
            Button("Cancel") { store.dialog = nil }
                .keyboardShortcut(.cancelAction)
            Button("Continue", role: .destructive) {
                store.dialog = nil
                Task { await store.execute(request, elevated: true) }
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .keyboardShortcut(.defaultAction)
        case .message:
            Button("OK") { store.dialog = nil }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
    }
}

private struct ProcessRow: View {
    let process: ListeningProcess
    let onAction: (TerminationSignal) -> Void

    private var protectionReason: String? { ProcessProtection.reason(for: process) }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(process.command)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    if process.isRoot {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(.orange)
                            .help("Root process")
                    }
                    if protectionReason != nil {
                        Image(systemName: "shield.fill")
                            .foregroundStyle(.secondary)
                            .help(protectionReason ?? "Protected process")
                    }
                }

                Text("\(process.portsLabel)  •  PID \(process.pid)  •  \(process.user)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Menu {
                Button("Stop Normally") { onAction(.terminate) }
                Button("Force Quit", role: .destructive) { onAction(.kill) }
            } label: {
                Image(systemName: "stop.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(protectionReason != nil)
            .help(protectionReason ?? "Manage process")
        }
        .padding(.vertical, 4)
    }
}

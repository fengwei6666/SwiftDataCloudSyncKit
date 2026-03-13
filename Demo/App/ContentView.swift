import SwiftUI

struct ContentView: View {

    @StateObject private var store = DemoStore()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    engineSection
                    syncSection
                    dataSection
                    diagnosticsSection
                    logsSection
                }
                .padding(16)
            }
            .navigationTitle("SyncKit Demo")
        }
        .task {
            if !store.isEngineReady {
                store.setupEngine(cloudCapable: true)
            }
        }
    }

    private var engineSection: some View {
        GroupBox("Engine") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Button("Setup Cloud-capable") {
                        store.setupEngine(cloudCapable: true)
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Setup Local-only") {
                        store.setupEngine(cloudCapable: false)
                    }
                    .buttonStyle(.bordered)
                }

                Toggle(
                    "Cloud Sync Enabled",
                    isOn: Binding(
                        get: { store.isCloudSyncEnabled },
                        set: { store.setCloudSyncEnabled($0) }
                    )
                )
                .disabled(!store.isEngineReady || !store.isCloudCapable)

                Text("Engine Ready: \(store.isEngineReady ? "YES" : "NO")")
                Text("Cloud Capable: \(store.isCloudCapable ? "YES" : "NO")")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var syncSection: some View {
        GroupBox("Sync Monitor") {
            VStack(alignment: .leading, spacing: 8) {
                Text("isSyncing: \(store.isSyncing ? "true" : "false")")
                Text("progress: \(Int(store.syncProgress * 100))%")
                Text("lastSyncDate: \(formatDate(store.lastSyncDate))")
                Text("syncError: \(store.syncErrorMessage ?? "none")")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var dataSection: some View {
        GroupBox("Data") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Button("Add Sample Work") {
                        store.addSampleWork()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!store.isEngineReady)

                    Button("Reload Works") {
                        store.reloadWorks()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!store.isEngineReady)
                }

                Text("Count: \(store.works.count)")

                ForEach(store.works.prefix(8), id: \.persistentModelID) { work in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(work.name).font(.headline)
                        Text(work.id).font(.caption).foregroundStyle(.secondary)
                        Text(formatDate(work.updatedAt)).font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var diagnosticsSection: some View {
        GroupBox("Diagnostics") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(store.diagnostics, id: \.self) { message in
                    Text("- \(message)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var logsSection: some View {
        GroupBox("Logs") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(store.logs.prefix(40), id: \.self) { line in
                    Text(line)
                        .font(.caption2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func formatDate(_ date: Date?) -> String {
        guard let date else { return "nil" }
        return DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .medium)
    }
}

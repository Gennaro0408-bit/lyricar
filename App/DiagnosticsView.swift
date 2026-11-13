import SwiftUI

/// Mostra il registro diagnostico (ultimi eventi in alto)
struct DiagnosticsView: View {
    @State private var text = ""

    var body: some View {
        ScrollView {
            Text(text.isEmpty ? "Nessun evento registrato." : text)
                .font(.system(.caption2, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle("Diagnostica")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ShareLink(item: text) { Image(systemName: "square.and.arrow.up") }
            Button("Svuota", role: .destructive) { EventLog.clear(); load() }
        }
        .onAppear(perform: load)
        .refreshable { load() }
    }

    private func load() {
        text = EventLog.read()
            .split(separator: "\n")
            .reversed()
            .joined(separator: "\n")
    }
}

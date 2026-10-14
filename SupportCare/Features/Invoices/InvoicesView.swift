import SwiftUI
import SupportCareCore

enum InvoiceFilter: String, CaseIterable, Identifiable {
    case all, draft, sent, overdue, paid
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct InvoicesView: View {
    @Environment(DataStore.self) private var store
    @State private var filter: InvoiceFilter = .all
    @State private var selection = Set<UUID>()
    @State private var editMode: EditMode = .inactive
    @State private var showBuilder = false
    @State private var shareURL: URL?
    @State private var exporting = false
    @Namespace private var zoom

    private var list: [Invoice] {
        store.invoices.filter { filter == .all || $0.displayStatus(today: store.today).rawValue == filter.rawValue }
    }

    var body: some View {
        NavigationStack {
            List(selection: $selection) {
                Section {
                    GlassChips(options: InvoiceFilter.allCases, selection: $filter, title: \.title)
                        .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                    outstanding.listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                }
                if list.isEmpty {
                    EmptyStateView(title: "No invoices", message: "Create an NDIS invoice from your logged shifts.",
                                   systemImage: "doc.text", actionTitle: "New invoice") { showBuilder = true }
                        .listRowBackground(Color.clear)
                }
                ForEach(list) { inv in
                    NavigationLink(value: inv.id) {
                        InvoiceRow(invoice: inv).matchedTransitionSource(id: inv.id, in: zoom)
                    }
                    .tag(inv.id)
                    .swipeActions(edge: .leading) {
                        if inv.status != InvoiceStatus.paid.rawValue {
                            Button("Paid", systemImage: "checkmark.seal") { Task { await store.setStatus(.paid, for: inv) } }.tint(Theme.money)
                        }
                    }
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) { Task { await store.delete(invoice: inv) } }
                    }
                }
            }
            .environment(\.editMode, $editMode)
            .animation(Motion.smooth, value: list.map(\.id))
            .navigationTitle("Invoices")
            .navigationDestination(for: UUID.self) { id in
                InvoiceDetailView(invoiceId: id).navigationTransition(.zoom(sourceID: id, in: zoom))
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(editMode.isEditing ? "Done" : "Select") {
                        withAnimation(Motion.snappy) {
                            editMode = editMode.isEditing ? .inactive : .active
                            if !editMode.isEditing { selection.removeAll() }
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("New invoice", systemImage: "plus") { showBuilder = true }.buttonStyle(.glassProminent)
                }
                if editMode.isEditing {
                    ToolbarItemGroup(placement: .bottomBar) {
                        Button(selection.count == list.count ? "Deselect all" : "Select all") {
                            selection = selection.count == list.count ? [] : Set(list.map(\.id))
                        }
                        Spacer()
                        Button {
                            Task { await exportSelected() }
                        } label: {
                            if exporting { ProgressView() } else {
                                Label("Download \(selection.count)", systemImage: "arrow.down.doc")
                            }
                        }
                        .buttonStyle(.glassProminent)
                        .disabled(selection.isEmpty || exporting)
                    }
                }
            }
            .sheet(isPresented: $showBuilder) { InvoiceBuilderView() }
            .sheet(item: $shareURL) { ShareSheet(items: [$0]).presentationDetents([.medium, .large]) }
        }
    }

    private var outstanding: some View {
        let unpaid = store.invoices.filter { $0.status != InvoiceStatus.paid.rawValue }
        let overdue = unpaid.filter { $0.displayStatus(today: store.today) == .overdue }
        return HStack(spacing: 12) {
            StatTile(title: "Outstanding", value: unpaid.reduce(0) { $0 + $1.totalAmount }, tint: Theme.amber, symbol: "hourglass")
            StatTile(title: "Overdue", value: overdue.reduce(0) { $0 + $1.totalAmount }, tint: Theme.red, symbol: "exclamationmark.circle.fill")
        }
    }

    /// Batch download: one vector PDF per invoice in a ZIP (or the single PDF if one is selected).
    private func exportSelected() async {
        exporting = true
        defer { exporting = false }
        let docs = list.filter { selection.contains($0.id) }.map { store.document(for: $0) }
        do {
            shareURL = docs.count == 1 ? try InvoicePDFRenderer.file(for: docs[0]) : try InvoicePDFRenderer.zip(docs)
        } catch { store.lastError = error.localizedDescription }
    }
}

struct InvoiceRow: View {
    @Environment(DataStore.self) private var store
    let invoice: Invoice

    var body: some View {
        let status = invoice.displayStatus(today: store.today)
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(invoice.invoiceNumber).font(.body.weight(.semibold)).monospaced()
                    StatusBadge(status: status)
                }
                Text(store.client(invoice.clientId)?.shownName ?? "All clients").font(.subheadline)
                Text("\(Periods.shortDate(invoice.periodStart)) – \(Periods.shortDate(invoice.periodEnd))").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(invoice.totalAmount, format: .currency(code: "AUD")).font(.body.weight(.semibold)).monospacedDigit()
        }
    }
}

struct StatusBadge: View {
    let status: InvoiceStatus
    var body: some View {
        switch status {
        case .draft: Badge(text: "Draft", color: .secondary)
        case .sent: Badge(text: "Sent", color: Theme.primary, symbol: "paperplane.fill")
        case .paid: Badge(text: "Paid", color: Theme.money, symbol: "checkmark")
        case .overdue: Badge(text: "Overdue", color: Theme.red, symbol: "exclamationmark")
        }
    }
}

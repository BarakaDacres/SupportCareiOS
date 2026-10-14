import SwiftUI
import SupportCareCore

/// On-screen invoice preview + PDF share + status lifecycle (draft → sent → paid).
struct InvoiceDetailView: View {
    @Environment(DataStore.self) private var store
    let invoiceId: UUID
    @State private var shareURL: URL?
    @State private var statusBump = 0

    var body: some View {
        if let invoice = store.invoices.first(where: { $0.id == invoiceId }) {
            let doc = store.document(for: invoice)
            let status = invoice.displayStatus(today: store.today)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("INVOICE").font(.caption.weight(.bold)).foregroundStyle(Theme.primary)
                            Text(doc.number).font(.title.bold()).monospaced()
                            Text("Due \(Periods.mediumDate(doc.dueDate))").font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer()
                        StatusBadge(status: status).symbolEffect(.bounce, value: statusBump)
                    }
                    HStack(alignment: .top, spacing: 16) {
                        party("From", doc.from)
                        party("Bill to", doc.billTo)
                    }
                    if let n = doc.participantNumber, !n.isEmpty {
                        LabeledContent("NDIS number", value: n).font(.footnote)
                    }
                    Card {
                        ForEach(doc.groups) { g in
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(g.label).font(.subheadline.weight(.medium))
                                    Text(g.ndisCode).font(.caption2).monospaced().foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(g.subtotal, format: .currency(code: "AUD")).monospacedDigit()
                            }
                            Divider()
                        }
                        HStack {
                            Text("Total").font(.headline)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                MoneyText(value: doc.total, font: .title2.bold())
                                if doc.isPaid {
                                    Text("Paid, thank you").font(.caption).foregroundStyle(Theme.money).transition(.opacity)
                                }
                            }
                        }
                    }
                    if abs(doc.total - invoice.totalAmount) > 0.005 {
                        Banner(kind: .info, text: "Shifts have changed since this invoice was created (saved total \(invoice.totalAmount.formatted(.currency(code: "AUD")))).")
                    }
                    if !doc.payment.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            SectionHeader(title: "Payment details", systemImage: "building.columns")
                            ForEach(doc.payment, id: \.self) { Text($0).font(.footnote) }
                        }
                    }
                    if let notes = doc.notes, !notes.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            SectionHeader(title: "Notes")
                            Text(notes).font(.footnote)
                        }
                    }
                }
                .padding()
                .animation(Motion.smooth, value: invoice.status)
            }
            .navigationTitle(doc.number)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Share PDF", systemImage: "square.and.arrow.up") { shareURL = try? InvoicePDFRenderer.file(for: doc) }
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Menu {
                        ForEach([InvoiceStatus.draft, .sent, .paid], id: \.self) { s in
                            Button(s.label) { Task { await store.setStatus(s, for: invoice); statusBump += 1 } }
                        }
                    } label: { Label("Status", systemImage: "flag") }
                    Spacer()
                    if invoice.status == InvoiceStatus.draft.rawValue {
                        Button("Mark sent", systemImage: "paperplane") { Task { await store.setStatus(.sent, for: invoice); statusBump += 1 } }
                            .buttonStyle(.glass)
                    }
                    if invoice.status != InvoiceStatus.paid.rawValue {
                        Button("Mark paid", systemImage: "checkmark.seal.fill") { Task { await store.setStatus(.paid, for: invoice); statusBump += 1 } }
                            .buttonStyle(.glassProminent)
                    }
                }
            }
            .sheet(item: $shareURL) { ShareSheet(items: [$0]).presentationDetents([.medium, .large]) }
            .sensoryFeedback(.success, trigger: statusBump)
        } else {
            ContentUnavailableView("Invoice not found", systemImage: "doc.questionmark")
        }
    }

    private func party(_ title: String, _ p: InvoiceDocument.Party) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionHeader(title: title)
            Text(p.name).font(.subheadline.weight(.semibold))
            ForEach(p.lines, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

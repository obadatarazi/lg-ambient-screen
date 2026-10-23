import SwiftUI

struct QuotesView: View {
    @Environment(AppModel.self) private var model
    @ViewState private var drafts: [Quote] = []
    @ViewState private var loaded = false

    private var dirty: Bool { drafts.filter(\.isValid) != model.state.quotes }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PaneHeader(title: "Quotes",
                           subtitle: model.state.quotes.isEmpty
                               ? "The TV is using its 26 built-in quotes. Add your own to replace them."
                               : "The TV rotates through your \(model.state.quotes.count) quotes.") {
                    GlassEffectContainer(spacing: 10) {
                        HStack(spacing: 10) {
                            if !model.state.quotes.isEmpty {
                                Button("Use Built-in", systemImage: "arrow.uturn.backward") {
                                    model.updateSettings { $0.quotes = [] }
                                    drafts = []
                                }
                                .buttonStyle(.glass)
                            }
                            Button("Save to TV", systemImage: "checkmark") {
                                drafts = drafts.filter(\.isValid)
                                model.updateSettings { $0.quotes = drafts }
                                model.flash("Quotes saved")
                            }
                            .buttonStyle(.glassProminent)
                            .disabled(!dirty)
                        }
                    }
                    .controlSize(.large)
                }

                VStack(spacing: 12) {
                    ForEach($drafts) { $q in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "quote.opening")
                                .font(.title3)
                                .foregroundStyle(.orange)
                                .padding(.top, 4)
                            VStack(alignment: .leading, spacing: 8) {
                                TextField("Quote", text: $q.t, axis: .vertical)
                                    .font(.title3.weight(.semibold))
                                TextField("Author", text: $q.a)
                                    .foregroundStyle(.secondary)
                            }
                            .textFieldStyle(.plain)
                            Button {
                                drafts.removeAll { $0.id == q.id }
                            } label: {
                                Image(systemName: "minus.circle.fill").font(.title3)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.red)
                        }
                        .padding(18)
                        .glassEffect(.regular, in: .rect(cornerRadius: 20))
                    }

                    Button {
                        drafts.append(Quote(t: "", a: ""))
                    } label: {
                        Label("Add Quote", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                }
            }
            .padding(32)
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            drafts = model.state.quotes
        }
    }
}

private extension Quote {
    var isValid: Bool { !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

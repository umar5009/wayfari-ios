import SwiftUI

struct PriceAlert: Identifiable, Codable, Equatable {
    let id: UUID
    var originCode: String
    var destinationCode: String
    var maxPriceUSD: Int
    var isRoundTrip: Bool
    var createdAt: Date

    init(id: UUID = UUID(), originCode: String, destinationCode: String,
         maxPriceUSD: Int, isRoundTrip: Bool, createdAt: Date = Date()) {
        self.id = id
        self.originCode = originCode
        self.destinationCode = destinationCode
        self.maxPriceUSD = maxPriceUSD
        self.isRoundTrip = isRoundTrip
        self.createdAt = createdAt
    }

    var routeLabel: String {
        isRoundTrip ? "\(originCode) ⇄ \(destinationCode)" : "\(originCode) → \(destinationCode)"
    }
}

@MainActor
final class PriceAlertStore: ObservableObject {
    @Published private(set) var alerts: [PriceAlert] = []

    private static let storageKey = "wayfari.priceAlerts"

    init() { load() }

    func add(_ alert: PriceAlert) {
        alerts.insert(alert, at: 0)
        save()
    }

    func remove(_ alert: PriceAlert) {
        alerts.removeAll { $0.id == alert.id }
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([PriceAlert].self, from: data) else { return }
        alerts = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(alerts) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}

struct PriceAlertsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = PriceAlertStore()
    @State private var showCreate = false

    var defaultOrigin: Airport
    var defaultDestination: Airport

    var body: some View {
        NavigationStack {
            Group {
                if store.alerts.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(store.alerts) { alert in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(alert.routeLabel)
                                        .font(.system(size: 16, weight: .semibold))
                                    Text("Alert when under $\(alert.maxPriceUSD)")
                                        .font(.system(size: 13))
                                        .foregroundColor(Theme.sublabel)
                                }
                                Spacer()
                                Image(systemName: "bell.fill")
                                    .foregroundColor(.yellow)
                            }
                            .padding(.vertical, 4)
                        }
                        .onDelete { indexSet in
                            indexSet.map { store.alerts[$0] }.forEach { store.remove($0) }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Price Alerts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Theme.sublabel)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showCreate = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
            }
            .sheet(isPresented: $showCreate) {
                CreatePriceAlertSheet(
                    origin: defaultOrigin,
                    destination: defaultDestination
                ) { alert in
                    store.add(alert)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.systemGray6))
                    .frame(width: 120, height: 120)
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 44))
                    .foregroundColor(.yellow)
            }
            Text("Know when prices change")
                .font(.system(size: 20, weight: .bold))
            Text("Create an alert and we'll notify you when fares drop below your target price.")
                .font(.system(size: 14))
                .foregroundColor(Theme.sublabel)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button { showCreate = true } label: {
                Text("Create price alert")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Theme.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }
}

private struct CreatePriceAlertSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (PriceAlert) -> Void

    @State private var origin: Airport
    @State private var destination: Airport
    @State private var maxPrice: Double = 250
    @State private var isRoundTrip = true

    init(origin: Airport, destination: Airport, onSave: @escaping (PriceAlert) -> Void) {
        _origin = State(initialValue: origin)
        _destination = State(initialValue: destination)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Route") {
                    Picker("From", selection: $origin) {
                        ForEach(AirportCatalog.all) { ap in
                            Text(ap.label).tag(ap)
                        }
                    }
                    Picker("To", selection: $destination) {
                        ForEach(AirportCatalog.all) { ap in
                            Text(ap.label).tag(ap)
                        }
                    }
                    Toggle("Round trip", isOn: $isRoundTrip)
                }
                Section("Target price") {
                    HStack {
                        Text("$\(Int(maxPrice))")
                            .font(.system(size: 20, weight: .bold))
                        Slider(value: $maxPrice, in: 50...2000, step: 10)
                    }
                }
            }
            .navigationTitle("New Alert")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        onSave(PriceAlert(
                            originCode: origin.code,
                            destinationCode: destination.code,
                            maxPriceUSD: Int(maxPrice),
                            isRoundTrip: isRoundTrip
                        ))
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

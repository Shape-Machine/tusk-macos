import SwiftUI

struct SponsorView: View {
    private let oneTime: [(label: String, url: String)] = [
        ("Coffee €5",    "https://buy.stripe.com/14A28saQ95kI9q93qNes003"),
        ("Supporter €15","https://buy.stripe.com/4gMeVebUddRefOx7H3es004"),
        ("Sponsor €49",  "https://buy.stripe.com/00w6oI2jD7sQeKt7H3es005"),
    ]

    private let monthly: [(label: String, url: String)] = [
        ("Hero Coffee €5/mo",    "https://buy.stripe.com/8x29AU7DXdReeKtaTfes000"),
        ("Hero Supporter €15/mo","https://buy.stripe.com/9B6bJ2f6p5kI59T2mJes001"),
        ("Hero Sponsor €49/mo",  "https://buy.stripe.com/bJe5kEgat8wUfOx3qNes002"),
    ]

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 4) {
                Text("Tusk is free and open source.")
                    .font(.headline)
                Text("If it's useful to you, consider sponsoring its development.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                tierRow(label: "One-time", tiers: oneTime)
                tierRow(label: "Monthly", tiers: monthly)
            }
        }
        .padding(28)
        .frame(width: 380)
    }

    private func tierRow(label: String, tiers: [(label: String, url: String)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            HStack(spacing: 0) {
                ForEach(tiers.indices, id: \.self) { i in
                    if i > 0 {
                        Text(" · ")
                            .foregroundStyle(.secondary)
                    }
                    if let url = URL(string: tiers[i].url) {
                        Link(tiers[i].label, destination: url)
                    }
                }
            }
            .font(.callout)
        }
    }
}

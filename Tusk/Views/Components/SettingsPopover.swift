import SwiftUI

struct SettingsPopover: View {
    @AppStorage("tusk.sidebar.fontSize")    private var sidebarFontSize   = 13.0
    @AppStorage("tusk.sidebar.fontDesign") private var sidebarFontDesign: TuskFontDesign = .sansSerif
    @AppStorage("tusk.content.fontSize")   private var contentFontSize   = 13.0
    @AppStorage("tusk.content.fontDesign") private var contentFontDesign: TuskFontDesign = .sansSerif

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Appearance")
                .font(.headline)

            settingsSection("Sidebar", fontDesign: $sidebarFontDesign, fontSize: $sidebarFontSize)
            Divider()
            settingsSection("Content", fontDesign: $contentFontDesign, fontSize: $contentFontSize)
        }
        .padding(16)
        .frame(width: 280)
    }

    private func settingsSection(
        _ label: String,
        fontDesign: Binding<TuskFontDesign>,
        fontSize: Binding<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            // Font family picker — each option shown in its own typeface
            HStack(spacing: 4) {
                ForEach(TuskFontDesign.allCases, id: \.self) { option in
                    let isSelected = fontDesign.wrappedValue == option
                    Button { fontDesign.wrappedValue = option } label: {
                        Text(option.label)
                            .font(.system(size: 12, design: option.design))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                            .background(
                                isSelected ? Color(nsColor: .selectedControlColor) : Color(nsColor: .controlColor),
                                in: RoundedRectangle(cornerRadius: 5)
                            )
                            .foregroundStyle(isSelected ? .primary : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Font size slider
            HStack(spacing: 8) {
                Text("Size")
                    .frame(width: 32, alignment: .leading)
                    .foregroundStyle(.secondary)
                Slider(value: fontSize, in: 11...17, step: 1)
                Text("\(Int(fontSize.wrappedValue))pt")
                    .monospacedDigit()
                    .frame(width: 28, alignment: .trailing)
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
        }
    }
}

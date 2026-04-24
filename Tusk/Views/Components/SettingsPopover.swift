import SwiftUI
import UserNotifications

struct SettingsPopover: View {
    @Environment(\.openWindow) private var openWindow
    @AppStorage("tusk.sidebar.fontSize")             private var sidebarFontSize        = 13.0
    @AppStorage("tusk.sidebar.fontDesign")           private var sidebarFontDesign: TuskFontDesign = .sansSerif
    @AppStorage("tusk.content.fontSize")             private var contentFontSize        = 13.0
    @AppStorage("tusk.content.fontDesign")           private var contentFontDesign: TuskFontDesign = .sansSerif
    @AppStorage("tusk.sidebar.showTableSizes")       private var showTableSizes         = false
    @AppStorage("tusk.dataBrowser.pageSize")         private var dataBrowserPageSize    = 1_000
    @AppStorage("tusk.notifications.queryThreshold") private var queryNotifyThreshold   = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Appearance")
                .font(.headline)

            settingsSection("Sidebar", fontDesign: $sidebarFontDesign, fontSize: $sidebarFontSize)
            Toggle("Show table sizes", isOn: $showTableSizes)
                .toggleStyle(.checkbox)
                .font(.callout)

            HStack {
                Text("Rows per page")
                    .font(.callout)
                Spacer()
                Picker("Rows per page", selection: $dataBrowserPageSize) {
                    Text("50").tag(50)
                    Text("100").tag(100)
                    Text("500").tag(500)
                    Text("1 000").tag(1_000)
                    Text("5 000").tag(5_000)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 80)
            }
            .font(.callout)

            Divider()
            settingsSection("Content", fontDesign: $contentFontDesign, fontSize: $contentFontSize)

            Divider()

            Text("Notifications")
                .font(.headline)

            HStack {
                Text("Notify after query")
                    .font(.callout)
                Spacer()
                Picker("Notify after query", selection: $queryNotifyThreshold) {
                    Text("Never").tag(-1)
                    Text("2 s").tag(2)
                    Text("5 s").tag(5)
                    Text("10 s").tag(10)
                    Text("30 s").tag(30)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 80)
            }
            .font(.callout)

            Divider()

            Button("Sponsor Tusk…") { openWindow(id: "sponsor") }
                .font(.callout)
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
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

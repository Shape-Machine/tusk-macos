import SwiftUI

struct SettingsPopover: View {
    @AppStorage("tusk.sidebar.fontSize") private var sidebarFontSize = 13.0
    @AppStorage("tusk.content.fontSize") private var contentFontSize = 13.0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Appearance")
                .font(.headline)

            VStack(spacing: 10) {
                fontSizeRow("Sidebar", size: $sidebarFontSize)
                fontSizeRow("Content", size: $contentFontSize)
            }
        }
        .padding(16)
        .frame(width: 260)
    }

    private func fontSizeRow(_ label: String, size: Binding<Double>) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .frame(width: 52, alignment: .leading)
                .foregroundStyle(.secondary)
            Slider(value: size, in: 11...17, step: 1)
            Text("\(Int(size.wrappedValue))pt")
                .monospacedDigit()
                .frame(width: 28, alignment: .trailing)
                .foregroundStyle(.secondary)
        }
        .font(.callout)
    }
}

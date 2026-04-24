import SwiftUI

private enum ExplainViewMode: String, CaseIterable {
    case tree  = "Tree"
    case graph = "Graph"
}

struct ExplainPlanView: View {
    let result: ExplainResult

    @AppStorage("tusk.content.fontSize")   private var fontSize   = 13.0
    @AppStorage("tusk.content.fontDesign") private var fontDesign: TuskFontDesign = .sansSerif
    @State private var viewMode: ExplainViewMode = .tree

    var body: some View {
        VStack(spacing: 0) {
            // Header bar: timing stats + view toggle
            HStack(spacing: 6) {
                if let exec = result.executionMs {
                    Text(String(format: "Execution: %.3f ms", exec))
                        .font(.system(size: fontSize - 1, design: fontDesign.design))
                        .foregroundStyle(.secondary)
                }
                if let plan = result.planningMs {
                    Text("·").foregroundStyle(.tertiary)
                    Text(String(format: "Planning: %.3f ms", plan))
                        .font(.system(size: fontSize - 1, design: fontDesign.design))
                        .foregroundStyle(.secondary)
                }
                Text("·").foregroundStyle(.tertiary)
                Text(String(format: "%.3fs", result.duration))
                    .font(.system(size: fontSize - 1, design: fontDesign.design))
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("View", selection: $viewMode) {
                    ForEach(ExplainViewMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.bar)

            Divider()

            switch viewMode {
            case .tree:
                ScrollView([.vertical, .horizontal]) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ExplainNodeRow(node: result.plan, depth: 0,
                                      totalCost: result.plan.totalCost,
                                      fontSize: fontSize, fontDesign: fontDesign.design)
                    }
                    .padding(12)
                }
                .background(Color(nsColor: .textBackgroundColor))
            case .graph:
                ExplainGraphView(result: result)
            }
        }
    }
}

// MARK: - Recursive node row

private struct ExplainNodeRow: View {
    let node: ExplainNode
    let depth: Int
    let totalCost: Double
    let fontSize: Double
    let fontDesign: Font.Design

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            nodeRow
            ForEach(Array(node.children.enumerated()), id: \.offset) { _, child in
                ExplainNodeRow(node: child, depth: depth + 1,
                               totalCost: totalCost,
                               fontSize: fontSize, fontDesign: fontDesign)
            }
        }
    }

    private var nodeRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            // Indentation + connector
            if depth > 0 {
                Text(String(repeating: "  ", count: depth) + "↳")
                    .foregroundStyle(.tertiary)
                    .font(.system(size: fontSize, design: .monospaced))
            }

            // Node type — highlighted if slow
            Text(nodeLabel)
                .font(.system(size: fontSize, weight: .semibold, design: fontDesign))
                .foregroundStyle(nodeColor)

            // Cost / rows / time
            Text(costAnnotation)
                .font(.system(size: fontSize - 1, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var nodeLabel: String {
        var parts = [node.nodeType]
        if let rel = node.relationName {
            parts.append("on \(rel)")
            if let alias = node.alias, alias != rel { parts.append("(\(alias))") }
        }
        if let idx = node.indexName {
            parts.append("using \(idx)")
        }
        return parts.joined(separator: " ")
    }

    private var nodeColor: Color {
        if node.isSeqScan { return .orange }
        if node.nodeType == "Hash Join" { return .orange }
        // Flag nodes that account for >50% of total plan cost
        if totalCost > 0 && node.totalCost / totalCost > 0.5 { return .orange }
        return .primary
    }

    private var costAnnotation: String {
        var parts: [String] = []
        parts.append(String(format: "(cost=%.2f..%.2f rows=%d width=%d)",
                            node.startupCost, node.totalCost, node.planRows, node.planWidth))
        if let at = node.actualTotalTime, let ar = node.actualRows, let al = node.actualLoops {
            parts.append(String(format: "(actual time=%.3f..%.3f rows=%d loops=%d)",
                                node.actualStartupTime ?? 0, at, ar, al))
        }
        return parts.joined(separator: " ")
    }
}

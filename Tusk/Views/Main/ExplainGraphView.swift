import SwiftUI

// MARK: - Tree layout

/// Computed layout for a single node in the graph canvas.
struct PlanNodeLayout: Identifiable {
    let id = UUID()
    let node: ExplainNode
    var centerX: CGFloat
    var centerY: CGFloat
    var children: [PlanNodeLayout]

    // Card dimensions and spacing (base scale = 1.0)
    static let cardW: CGFloat = 200
    static let cardH: CGFloat = 76
    static let hGap:  CGFloat = 18
    static let vGap:  CGFloat = 52

    // MARK: Layout

    static func build(node: ExplainNode, topLeft: CGPoint) -> PlanNodeLayout {
        let sw = subtreeWidth(node)
        let cx = topLeft.x + sw / 2
        let cy = topLeft.y + cardH / 2

        guard !node.children.isEmpty else {
            return PlanNodeLayout(node: node, centerX: cx, centerY: cy, children: [])
        }

        let childY = topLeft.y + cardH + vGap
        var childX = topLeft.x
        var childLayouts: [PlanNodeLayout] = []
        for child in node.children {
            let csw = subtreeWidth(child)
            childLayouts.append(build(node: child, topLeft: CGPoint(x: childX, y: childY)))
            childX += csw + hGap
        }
        let parentCX = (childLayouts.first!.centerX + childLayouts.last!.centerX) / 2
        return PlanNodeLayout(node: node, centerX: parentCX, centerY: cy, children: childLayouts)
    }

    static func canvasSize(root: ExplainNode) -> CGSize {
        let w = subtreeWidth(root)
        let d = depth(root)
        let h = CGFloat(d) * (cardH + vGap) - vGap
        return CGSize(width: max(w, cardW), height: max(h, cardH))
    }

    /// Flattened list of all nodes in breadth-first order (for ForEach rendering).
    func allLayouts() -> [PlanNodeLayout] {
        var result: [PlanNodeLayout] = [self]
        for child in children { result += child.allLayouts() }
        return result
    }

    // MARK: Private helpers

    private static func subtreeWidth(_ node: ExplainNode) -> CGFloat {
        if node.children.isEmpty { return cardW }
        let total = node.children.map { subtreeWidth($0) }.reduce(0, +)
        let gaps  = CGFloat(node.children.count - 1) * hGap
        return max(cardW, total + gaps)
    }

    private static func depth(_ node: ExplainNode) -> Int {
        if node.children.isEmpty { return 1 }
        return 1 + (node.children.map { depth($0) }.max() ?? 0)
    }
}

// MARK: - Graph view

struct ExplainGraphView: View {
    let result: ExplainResult
    private let rootLayout: PlanNodeLayout
    private let baseSize: CGSize

    @State private var scale: CGFloat = 1.0
    @GestureState private var liveScale: CGFloat = 1.0

    init(result: ExplainResult) {
        self.result     = result
        self.rootLayout = PlanNodeLayout.build(node: result.plan, topLeft: .zero)
        self.baseSize   = PlanNodeLayout.canvasSize(root: result.plan)
    }

    private var maxNodeTime: Double {
        func maxTime(_ node: ExplainNode) -> Double {
            let t = node.actualTotalTime ?? 0
            return ([t] + node.children.map { maxTime($0) }).max() ?? 0
        }
        return maxTime(result.plan)
    }

    var body: some View {
        let effectiveScale = max(0.3, min(4.0, scale * liveScale))
        let canvasW = baseSize.width  * effectiveScale
        let canvasH = baseSize.height * effectiveScale
        let layout  = rootLayout
        let all     = layout.allLayouts()
        let rootCost = result.plan.totalCost
        let maxTime  = maxNodeTime

        ScrollView([.horizontal, .vertical]) {
            ZStack(alignment: .topLeading) {
                // Edge layer
                Canvas { ctx, _ in
                    drawEdges(ctx: &ctx, layout: layout, scale: effectiveScale)
                }
                .frame(width: canvasW, height: canvasH)

                // Node cards
                ForEach(all) { nodeLayout in
                    PlanNodeCard(
                        layout:   nodeLayout,
                        scale:    effectiveScale,
                        rootCost: rootCost,
                        maxTime:  maxTime
                    )
                }
            }
            .frame(width: canvasW, height: canvasH)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .gesture(
            MagnificationGesture()
                .updating($liveScale) { value, state, _ in state = value }
                .onEnded { scale = max(0.3, min(4.0, scale * $0)) }
        )
    }

    // MARK: - Edge drawing

    private func drawEdges(ctx: inout GraphicsContext, layout: PlanNodeLayout, scale: CGFloat) {
        for child in layout.children {
            let from = CGPoint(x: layout.centerX * scale,
                               y: (layout.centerY + PlanNodeLayout.cardH / 2) * scale)
            let to   = CGPoint(x: child.centerX  * scale,
                               y: (child.centerY  - PlanNodeLayout.cardH / 2) * scale)
            var path = Path()
            path.move(to: from)
            path.addCurve(
                to:       to,
                control1: CGPoint(x: from.x, y: from.y + (to.y - from.y) * 0.5),
                control2: CGPoint(x: to.x,   y: to.y   - (to.y - from.y) * 0.5)
            )
            ctx.stroke(path, with: .color(Color(nsColor: .separatorColor)), lineWidth: 1.5)
            drawEdges(ctx: &ctx, layout: child, scale: scale)
        }
    }
}

// MARK: - Node card

private struct PlanNodeCard: View {
    let layout:   PlanNodeLayout
    let scale:    CGFloat
    let rootCost: Double
    let maxTime:  Double

    var body: some View {
        let w = PlanNodeLayout.cardW * scale
        let h = PlanNodeLayout.cardH * scale

        VStack(alignment: .leading, spacing: 2 * scale) {
            Text(nodeLabel)
                .font(.system(size: 11 * scale, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(nodeColor)

            Text(costLine)
                .font(.system(size: 9.5 * scale, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if let tl = timeLine {
                Text(tl)
                    .font(.system(size: 9.5 * scale, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8 * scale)
        .padding(.vertical, 6 * scale)
        .frame(width: w, height: h, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 8 * scale).fill(nodeColor.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 8 * scale)
            .strokeBorder(nodeColor.opacity(0.5), lineWidth: 1.5 * scale))
        .position(x: layout.centerX * scale, y: layout.centerY * scale)
    }

    private var nodeLabel: String {
        var parts = [layout.node.nodeType]
        if let rel = layout.node.relationName {
            parts.append("on \(rel)")
            if let alias = layout.node.alias, alias != rel { parts.append("(\(alias))") }
        }
        if let idx = layout.node.indexName { parts.append("using \(idx)") }
        return parts.joined(separator: " ")
    }

    private var costLine: String {
        String(format: "cost=%.2f..%.2f  rows=%d  width=%d",
               layout.node.startupCost, layout.node.totalCost,
               layout.node.planRows, layout.node.planWidth)
    }

    private var timeLine: String? {
        guard let at = layout.node.actualTotalTime,
              let ar = layout.node.actualRows,
              let al = layout.node.actualLoops else { return nil }
        return String(format: "actual=%.3f ms  rows=%d  loops=%d", at, ar, al)
    }

    private var nodeColor: Color {
        let fraction: Double
        if maxTime > 0, let t = layout.node.actualTotalTime {
            fraction = t / maxTime
        } else if rootCost > 0 {
            fraction = layout.node.totalCost / rootCost
        } else {
            fraction = 0
        }
        switch fraction {
        case ..<0.25: return .green
        case ..<0.50: return Color(red: 0.65, green: 0.65, blue: 0.0)
        case ..<0.75: return .orange
        default:      return .red
        }
    }
}

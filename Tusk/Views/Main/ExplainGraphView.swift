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

    // MARK: Layout entry point

    /// Builds the layout tree and canvas size in a single traversal — no redundant subtree walks.
    static func buildAll(node: ExplainNode) -> (layout: PlanNodeLayout, size: CGSize) {
        let (layout, w) = build(node: node, topLeft: .zero)
        let d = treeDepth(node)
        let h = CGFloat(d) * (cardH + vGap) - vGap
        let size = CGSize(width: max(w, cardW), height: max(h, cardH))
        return (layout, size)
    }

    /// Flattened list of all nodes depth-first (for ForEach rendering).
    func allLayouts() -> [PlanNodeLayout] {
        var result: [PlanNodeLayout] = [self]
        for child in children { result += child.allLayouts() }
        return result
    }

    // MARK: Private helpers

    /// Returns (layout, subtreeWidth). Each subtree is traversed exactly once:
    /// the child's width comes from the recursive return value, not a second subtreeWidth() call.
    private static func build(node: ExplainNode, topLeft: CGPoint) -> (PlanNodeLayout, CGFloat) {
        guard !node.children.isEmpty else {
            let cx = topLeft.x + cardW / 2
            let cy = topLeft.y + cardH / 2
            return (PlanNodeLayout(node: node, centerX: cx, centerY: cy, children: []), cardW)
        }

        let childY = topLeft.y + cardH + vGap
        var childX = topLeft.x
        var childLayouts: [PlanNodeLayout] = []

        for (i, child) in node.children.enumerated() {
            let (childLayout, childW) = build(node: child, topLeft: CGPoint(x: childX, y: childY))
            childLayouts.append(childLayout)
            childX += childW + (i < node.children.count - 1 ? hGap : 0)
        }

        let sw = max(cardW, childX - topLeft.x)
        let parentCX = (childLayouts.first!.centerX + childLayouts.last!.centerX) / 2
        let cy = topLeft.y + cardH / 2
        return (PlanNodeLayout(node: node, centerX: parentCX, centerY: cy, children: childLayouts), sw)
    }

    private static func treeDepth(_ node: ExplainNode) -> Int {
        if node.children.isEmpty { return 1 }
        return 1 + (node.children.map { treeDepth($0) }.max() ?? 0)
    }
}

// MARK: - Graph view

struct ExplainGraphView: View {
    let result: ExplainResult
    private let rootLayout: PlanNodeLayout
    private let baseSize: CGSize
    private let allNodeLayouts: [PlanNodeLayout]
    private let maxNodeTime: Double

    @State private var scale: CGFloat = 1.0
    @GestureState private var liveScale: CGFloat = 1.0

    init(result: ExplainResult) {
        self.result = result
        let (layout, size) = PlanNodeLayout.buildAll(node: result.plan)
        self.rootLayout     = layout
        self.baseSize       = size
        self.allNodeLayouts = layout.allLayouts()
        // Compute max actual time once; used by PlanNodeCard for relative colour-coding
        self.maxNodeTime = {
            func maxT(_ node: ExplainNode) -> Double {
                let t = node.actualTotalTime ?? 0
                return ([t] + node.children.map { maxT($0) }).max() ?? 0
            }
            return maxT(result.plan)
        }()
    }

    var body: some View {
        let effectiveScale = max(0.3, min(4.0, scale * liveScale))
        let canvasW = baseSize.width  * effectiveScale
        let canvasH = baseSize.height * effectiveScale

        ScrollView([.horizontal, .vertical]) {
            ZStack(alignment: .topLeading) {
                // Edge layer
                Canvas { ctx, _ in
                    drawEdges(ctx: &ctx, layout: rootLayout, scale: effectiveScale)
                }
                .frame(width: canvasW, height: canvasH)

                // Node cards — pre-flattened list avoids tree traversal in body
                ForEach(allNodeLayouts) { nodeLayout in
                    PlanNodeCard(
                        layout:   nodeLayout,
                        scale:    effectiveScale,
                        rootCost: result.plan.totalCost,
                        maxTime:  maxNodeTime
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

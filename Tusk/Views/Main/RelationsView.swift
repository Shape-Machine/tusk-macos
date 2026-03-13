import SwiftUI

// MARK: - Relations view (column relationship map)

struct RelationsView: View {
    let client: DatabaseClient
    let schemaName: String
    let tableName: String

    @State private var outgoing: [ForeignKeyInfo] = []    // this table → other
    @State private var incoming: [IncomingReference] = [] // other table → this table
    @State private var isLoading = true

    // MARK: - Edge model

    struct Edge: Identifiable {
        let id = UUID()
        let relatedTable: String
        let label: String       // "fromCol → toCol"
        let isOutgoing: Bool    // true = arrow points away from focal node
    }

    var edges: [Edge] {
        let out = outgoing.map {
            Edge(relatedTable: $0.toTable,
                 label: "\($0.fromColumn) → \($0.toColumn)",
                 isOutgoing: true)
        }
        let inc = incoming.map {
            Edge(relatedTable: $0.fromTable,
                 label: "\($0.fromColumn) → \($0.toColumn)",
                 isOutgoing: false)
        }
        return out + inc
    }

    // MARK: - Body

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if edges.isEmpty {
                ContentUnavailableView(
                    "No Relationships",
                    systemImage: "point.3.connected.trianglepath.dotted",
                    description: Text("\(tableName) has no foreign key relationships.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                diagram
            }
        }
        .task(id: tableName) { await loadRelations() }
    }

    // MARK: - Diagram

    private var diagram: some View {
        GeometryReader { geo in
            let center   = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius   = min(geo.size.width, geo.size.height) * 0.36
            let positions = radialPositions(count: edges.count, center: center, radius: radius)

            ZStack {
                // Edges (drawn behind nodes)
                Canvas { ctx, _ in
                    for (i, edge) in edges.enumerated() {
                        let (line, arrow) = edgePaths(
                            from: center,
                            to: positions[i],
                            isOutgoing: edge.isOutgoing
                        )
                        let color = edge.isOutgoing
                            ? Color.orange.opacity(0.65)
                            : Color.green.opacity(0.65)
                        ctx.stroke(line,  with: .color(color), lineWidth: 1.5)
                        ctx.stroke(arrow, with: .color(color), lineWidth: 1.5)
                    }
                }

                // Edge labels at midpoints
                ForEach(Array(edges.enumerated()), id: \.element.id) { i, edge in
                    edgeLabelView(edge.label, isOutgoing: edge.isOutgoing)
                        .position(midpoint(center, positions[i]))
                }

                // Surrounding nodes
                ForEach(Array(edges.enumerated()), id: \.element.id) { i, edge in
                    relatedNodeView(edge)
                        .position(positions[i])
                }

                // Focal (center) node — on top
                focalNodeView
                    .position(center)
            }
        }
        .padding(32)
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: - Node views

    private var focalNodeView: some View {
        Text(tableName)
            .font(.system(size: 13, weight: .bold))
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .foregroundStyle(.white)
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
    }

    private func relatedNodeView(_ edge: Edge) -> some View {
        let borderColor: Color = edge.isOutgoing ? .orange : .green
        return Text(edge.relatedTable)
            .font(.system(size: 12))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: .black.opacity(0.1), radius: 3, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(borderColor.opacity(0.7), lineWidth: 1.5)
            )
    }

    private func edgeLabelView(_ text: String, isOutgoing: Bool) -> some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundStyle(isOutgoing ? Color.orange : Color.green)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Layout helpers

    private func radialPositions(count: Int, center: CGPoint, radius: CGFloat) -> [CGPoint] {
        guard count > 0 else { return [] }
        return (0..<count).map { i in
            // Start at top (-π/2) and distribute evenly clockwise
            let angle = (2 * Double.pi * Double(i)) / Double(count) - Double.pi / 2
            return CGPoint(
                x: center.x + radius * CGFloat(cos(angle)),
                y: center.y + radius * CGFloat(sin(angle))
            )
        }
    }

    private func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }

    // MARK: - Edge path helpers (return Paths so Canvas can stroke them)

    private func edgePaths(
        from: CGPoint,
        to: CGPoint,
        isOutgoing: Bool
    ) -> (line: Path, arrow: Path) {
        // Offset endpoints so lines start/end outside the node boxes (~24 pt radius)
        let nodeRadius: CGFloat = 24
        let (trimFrom, trimTo) = trimmedEndpoints(from: from, to: to, inset: nodeRadius)

        var line = Path()
        line.move(to: trimFrom)
        line.addLine(to: trimTo)

        // Arrow tip is at trimTo for outgoing, trimFrom for incoming
        let tip   = isOutgoing ? trimTo   : trimFrom
        let tail  = isOutgoing ? trimFrom : trimTo
        let arrow = arrowheadPath(tip: tip, tail: tail, size: 7)

        return (line, arrow)
    }

    /// Shrinks both endpoints inward by `inset` points along the line direction.
    private func trimmedEndpoints(
        from: CGPoint, to: CGPoint, inset: CGFloat
    ) -> (CGPoint, CGPoint) {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let len = sqrt(dx * dx + dy * dy)
        guard len > inset * 2 else { return (from, to) }
        let ux = dx / len, uy = dy / len
        return (
            CGPoint(x: from.x + ux * inset, y: from.y + uy * inset),
            CGPoint(x: to.x   - ux * inset, y: to.y   - uy * inset)
        )
    }

    /// Two-stroke arrowhead at `tip` pointing away from `tail`.
    private func arrowheadPath(tip: CGPoint, tail: CGPoint, size: CGFloat) -> Path {
        let dx = tip.x - tail.x
        let dy = tip.y - tail.y
        let len = sqrt(dx * dx + dy * dy)
        guard len > 0 else { return Path() }
        let ux = dx / len, uy = dy / len
        let spread = CGFloat(0.45) // ~26°

        let cosS = CGFloat(cos(spread)), sinS = CGFloat(sin(spread))
        let p1 = CGPoint(
            x: tip.x - size * (ux * cosS - uy * sinS),
            y: tip.y - size * (ux * sinS + uy * cosS)
        )
        let p2 = CGPoint(
            x: tip.x - size * (ux * cosS + uy * sinS),
            y: tip.y - size * (-ux * sinS + uy * cosS)
        )

        var path = Path()
        path.move(to: tip); path.addLine(to: p1)
        path.move(to: tip); path.addLine(to: p2)
        return path
    }

    // MARK: - Data loading

    private func loadRelations() async {
        isLoading = true
        async let out = try? await client.foreignKeys(schema: schemaName, table: tableName)
        async let inc = try? await client.incomingReferences(schema: schemaName, table: tableName)
        outgoing = await out ?? []
        incoming = await inc ?? []
        isLoading = false
    }
}

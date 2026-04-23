import SwiftUI

// MARK: - Relations view (column relationship map)

struct RelationsView: View {
    let client: DatabaseClient
    let connectionID: UUID
    let schemaName: String
    let tableName: String

    @Environment(AppState.self) private var appState

    @AppStorage("tusk.content.fontSize")   private var contentFontSize   = 13.0
    @AppStorage("tusk.content.fontDesign") private var contentFontDesign: TuskFontDesign = .sansSerif

    @State private var outgoing: [ForeignKeyInfo] = []    // this table → other
    @State private var incoming: [IncomingReference] = [] // other table → this table
    @State private var isLoading = true
    @State private var loadError: String? = nil

    // MARK: - Zoom / pan state

    @State private var scale: CGFloat = 1.0
    @State private var gestureScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var gestureOffset: CGSize = .zero

    private var effectiveScale: CGFloat {
        max(0.3, min(3.0, scale * gestureScale))
    }
    private var effectiveOffset: CGSize {
        CGSize(
            width:  offset.width  + gestureOffset.width,
            height: offset.height + gestureOffset.height
        )
    }

    // MARK: - Edge model

    struct Edge: Identifiable {
        var id: String { "\(isOutgoing ? "out" : "in"):\(relatedTable):\(label)" }
        let relatedSchema: String
        let relatedTable: String
        let label: String       // "fromCol → toCol"
        let isOutgoing: Bool    // true = arrow points away from focal node
    }

    var edges: [Edge] {
        let out = outgoing.map {
            Edge(relatedSchema: $0.toSchema,
                 relatedTable: $0.toTable,
                 label: "\($0.fromColumn) → \($0.toColumn)",
                 isOutgoing: true)
        }
        let inc = incoming.map {
            Edge(relatedSchema: $0.fromSchema,
                 relatedTable: $0.fromTable,
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
            } else if let error = loadError {
                ContentUnavailableView(
                    "Failed to Load Relationships",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
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
        .task(id: "\(schemaName).\(tableName)") {
            scale = 1.0
            gestureScale = 1.0
            offset = .zero
            gestureOffset = .zero
            await loadRelations()
        }
    }

    // MARK: - Diagram

    private var diagram: some View {
        GeometryReader { geo in
            let center    = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius    = min(geo.size.width, geo.size.height) * 0.36
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
            .scaleEffect(effectiveScale)
            .offset(effectiveOffset)
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        gestureScale = value
                    }
                    .onEnded { value in
                        scale = max(0.3, min(3.0, scale * value))
                        gestureScale = 1.0
                    }
                    .simultaneously(with:
                        DragGesture()
                            .onChanged { value in
                                gestureOffset = CGSize(
                                    width:  value.translation.width,
                                    height: value.translation.height
                                )
                            }
                            .onEnded { value in
                                offset = CGSize(
                                    width:  offset.width  + value.translation.width,
                                    height: offset.height + value.translation.height
                                )
                                gestureOffset = .zero
                            }
                    )
            )
            .onTapGesture(count: 2) {
                scale = 1.0
                gestureScale = 1.0
                offset = .zero
                gestureOffset = .zero
            }
        }
        .padding(32)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(alignment: .bottomTrailing) { zoomControls }
    }

    // MARK: - Zoom controls overlay

    private var zoomControls: some View {
        HStack(spacing: 2) {
            Button {
                scale = max(0.3, scale / 1.25)
            } label: {
                Image(systemName: "minus")
                    .frame(width: 20, height: 20)
            }
            Button {
                scale = 1.0
                gestureScale = 1.0
                offset = .zero
                gestureOffset = .zero
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .frame(width: 20, height: 20)
            }
            Button {
                scale = min(3.0, scale * 1.25)
            } label: {
                Image(systemName: "plus")
                    .frame(width: 20, height: 20)
            }
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .padding(6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .padding(12)
    }

    // MARK: - Node views

    private var focalNodeView: some View {
        Text(tableName)
            .font(.system(size: contentFontSize, weight: .bold, design: contentFontDesign.design))
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .foregroundStyle(.white)
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
    }

    private func relatedNodeView(_ edge: Edge) -> some View {
        let borderColor: Color = edge.isOutgoing ? .orange : .green
        return Text(edge.relatedTable)
            .font(.system(size: contentFontSize - 1, design: contentFontDesign.design))
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
            .onHover { inside in
                if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
            .onTapGesture {
                appState.openOrActivateTableTab(
                    connectionID: connectionID,
                    schema: edge.relatedSchema,
                    tableName: edge.relatedTable
                )
            }
    }

    private func edgeLabelView(_ text: String, isOutgoing: Bool) -> some View {
        Text(text)
            .font(.system(size: contentFontSize - 3, design: contentFontDesign.design))
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
        loadError = nil
        do {
            async let out = try await client.foreignKeys(schema: schemaName, table: tableName)
            async let inc = try await client.incomingReferences(schema: schemaName, table: tableName)
            outgoing = try await out
            incoming = try await inc
            guard !Task.isCancelled else { isLoading = false; return }
            // Auto-scale for dense graphs
            let edgeCount = outgoing.count + incoming.count
            if edgeCount > 6 {
                scale = max(0.4, 6.0 / CGFloat(edgeCount))
            }
        } catch {
            guard !Task.isCancelled else { isLoading = false; return }
            outgoing = []
            incoming = []
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}

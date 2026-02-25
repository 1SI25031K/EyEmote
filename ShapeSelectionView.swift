//
//  ShapeSelectionView.swift
//  EyEmote
//
//  Lets the user choose the geometry of their Soul Shape. Inherits color, opacity, and texture.
//  3x4 grid; lift & scale feedback on hover. No cursor.
//

import SwiftUI

private let shapeRows = 3
private let shapeCols = 4
private let shapeTotal = shapeRows * shapeCols

private let shapeCases: [SoulShape] = SoulShape.allCases

struct ShapeSelectionView: View {
    @ObservedObject var gazeManager: GazeManager
    var onComplete: () -> Void
    
    private let dwellThreshold: TimeInterval = 3.0
    
    @State private var hoveredIndex: Int? = nil
    @State private var lastHoveredIndex: Int? = nil
    @State private var hasTriggeredSelection = false
    @State private var hasMorphedIn = false
    
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let rel = gazeManager.cursorRelativePosition
            let cursorPt = CGPoint(x: rel.x * size.width, y: rel.y * size.height)
            let indexUnderCursor = tileIndexAt(point: cursorPt, in: size)
            let baseColor = (gazeManager.decidedColor ?? Color.white).opacity(gazeManager.selectedAlpha)
            
            ZStack {
                Color.black
                    .ignoresSafeArea()
                
                shapeGridView(
                    size: size,
                    baseColor: baseColor,
                    hoveredIndex: hoveredIndex
                )
                .opacity(hasMorphedIn ? 1 : 0)
                .scaleEffect(hasMorphedIn ? 1 : 0.96)
                .animation(.spring(response: 0.45, dampingFraction: 0.78), value: hasMorphedIn)
                
                if gazeManager.selectedDecisionMethod == .dwell,
                   indexUnderCursor != nil,
                   !hasTriggeredSelection,
                   gazeManager.dwellTime > 0 {
                    dwellProgressOverlay(progress: min(1.0, gazeManager.dwellTime / dwellThreshold))
                }
                
                VStack {
                    Spacer()
                    Text("Choose a shape. Confirm with your chosen method.")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 44)
                }
            }
            .onAppear {
                gazeManager.isInDecisionSelectionPhase = true
                withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
                    hasMorphedIn = true
                }
            }
            .onDisappear {
                gazeManager.isInDecisionSelectionPhase = false
            }
            .onChange(of: indexUnderCursor) { newIndex in
                if let newIndex = newIndex {
                    let prev = lastHoveredIndex
                    hoveredIndex = newIndex
                    if newIndex != prev {
                        lastHoveredIndex = newIndex
                        let gen = UIImpactFeedbackGenerator(style: .medium)
                        gen.impactOccurred()
                    }
                }
            }
            .onChange(of: gazeManager.didPerformDeepBlink) { newValue in
                if newValue, !hasTriggeredSelection { tryConfirmShape(size: size, cursorPt: cursorPt) }
            }
            .onChange(of: gazeManager.didPerformMouthOpenTwice) { newValue in
                if newValue, !hasTriggeredSelection { tryConfirmShape(size: size, cursorPt: cursorPt) }
            }
            .onChange(of: gazeManager.dwellTime) { _ in
                if gazeManager.selectedDecisionMethod == .dwell,
                   indexUnderCursor != nil,
                   gazeManager.dwellTime >= dwellThreshold,
                   !hasTriggeredSelection {
                    tryConfirmShape(size: size, cursorPt: cursorPt)
                }
            }
        }
        .ignoresSafeArea()
    }
    
    private func shapeGridView(size: CGSize, baseColor: Color, hoveredIndex: Int?) -> some View {
        let cellW = size.width / CGFloat(shapeCols)
        let cellH = size.height / CGFloat(shapeRows)
        
        return Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            ForEach(0..<shapeRows, id: \.self) { row in
                GridRow {
                    ForEach(0..<shapeCols, id: \.self) { col in
                        let index = row * shapeCols + col
                        let shapeKind = shapeCases[index]
                        let isHovered = hoveredIndex == index
                        ShapeTileView(
                            shapeKind: shapeKind,
                            baseColor: baseColor,
                            texture: gazeManager.selectedTexture,
                            isHovered: isHovered
                        )
                        .frame(width: cellW, height: cellH)
                        .contentShape(Rectangle())
                    }
                }
            }
        }
        .animation(.interactiveSpring(response: 0.35, dampingFraction: 0.65), value: hoveredIndex)
    }
    
    private func tileIndexAt(point: CGPoint, in size: CGSize) -> Int? {
        guard point.x >= 0, point.x < size.width, point.y >= 0, point.y < size.height else { return nil }
        let col = Int((point.x / size.width) * CGFloat(shapeCols))
        let row = Int((point.y / size.height) * CGFloat(shapeRows))
        let c = max(0, min(shapeCols - 1, col))
        let r = max(0, min(shapeRows - 1, row))
        return r * shapeCols + c
    }
    
    private func tryConfirmShape(size: CGSize, cursorPt: CGPoint) {
        guard let index = tileIndexAt(point: cursorPt, in: size), !hasTriggeredSelection else {
            gazeManager.didPerformDeepBlink = false
            gazeManager.didPerformMouthOpenTwice = false
            return
        }
        hasTriggeredSelection = true
        gazeManager.selectedShape = shapeCases[index]
        gazeManager.didPerformDeepBlink = false
        gazeManager.didPerformMouthOpenTwice = false
        
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            onComplete()
        }
    }
    
    private func dwellProgressOverlay(progress: Double) -> some View {
        Circle()
            .stroke(Color.white.opacity(0.2), lineWidth: 4)
            .frame(width: 120, height: 120)
            .overlay(
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 120, height: 120)
                    .animation(.easeInOut(duration: 0.1), value: progress)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Shape Tile (geometry + texture styling; lift & scale when hovered)

private struct ShapeTileView: View {
    let shapeKind: SoulShape
    let baseColor: Color
    let texture: SoulTexture
    let isHovered: Bool
    
    private let size: CGFloat = 56
    
    var body: some View {
        ZStack {
            shapeContent
                .frame(width: shapeWidth, height: shapeHeight)
        }
        .scaleEffect(isHovered ? 1.2 : 1.0)
        .offset(y: isHovered ? -15 : 0)
        .shadow(color: baseColor.opacity(isHovered ? 0.7 : 0.4), radius: isHovered ? 18 : 8)
        .shadow(color: .black.opacity(isHovered ? 0.35 : 0.15), radius: isHovered ? 12 : 4)
        .animation(.interactiveSpring(response: 0.35, dampingFraction: 0.65), value: isHovered)
    }
    
    private var shapeWidth: CGFloat {
        switch shapeKind {
        case .capsule, .wave: return 72
        default: return size
        }
    }
    
    private var shapeHeight: CGFloat { size }
    
    @ViewBuilder
    private var shapeContent: some View {
        let base = baseFill
        switch texture {
        case .glossy:
            base.overlay(specularHighlight).overlay(glassStroke)
        case .frosted:
            base.overlay(shapePath.fill(.ultraThinMaterial).blendMode(.overlay)).overlay(shapePath.stroke(.white.opacity(0.4), lineWidth: 1.5))
        case .metallic:
            base.overlay(metallicHighlight).overlay(shapePath.stroke(.white.opacity(0.5), lineWidth: 1))
        case .pearlescent:
            base.overlay(pearlescentOverlay).overlay(shapePath.stroke(.white.opacity(0.35), lineWidth: 1.5))
        case .iridescent:
            base.overlay(iridescentOverlay).overlay(shapePath.stroke(.white.opacity(0.4), lineWidth: 1.5))
        case .chrome:
            base.overlay(metallicHighlight).overlay(shapePath.stroke(.white.opacity(0.6), lineWidth: 1.5))
        case .holographic:
            base.overlay(iridescentOverlay).overlay(shapePath.stroke(.white.opacity(0.45), lineWidth: 1.5))
        case .neonGlow:
            base.overlay(shapePath.stroke(baseColor, lineWidth: 2))
        case .glassyJelly:
            base.overlay(specularHighlight).overlay(shapePath.stroke(.white.opacity(0.5), lineWidth: 2))
        case .brushedAluminum:
            base.overlay(metallicHighlight).overlay(shapePath.stroke(.white.opacity(0.35), lineWidth: 1))
        case .deepVelvet:
            base.overlay(shapePath.stroke(LinearGradient(colors: [.white.opacity(0.2), .black.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2))
        case .crystal:
            base.overlay(specularHighlight).overlay(glassStroke)
        }
    }
    
    private var baseFill: some View {
        Group {
            if texture == .deepVelvet {
                shapePath.fill(
                    RadialGradient(
                        colors: [baseColor, baseColor.opacity(0.8), baseColor.opacity(0.4)],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.6
                    )
                )
            } else {
                shapePath.fill(baseColor)
            }
        }
    }
    
    private var shapePath: SoulShapeForm {
        SoulShapeForm(shapeKind)
    }
    
    private var specularHighlight: some View {
        shapePath.fill(
            LinearGradient(
                colors: [.white.opacity(0.85), .white.opacity(0.1), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
    
    private var glassStroke: some View {
        shapePath.stroke(
            LinearGradient(
                colors: [.white.opacity(0.9), .white.opacity(0.2)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            lineWidth: 2
        )
    }
    
    private var metallicHighlight: some View {
        shapePath.fill(
            LinearGradient(
                colors: [.white.opacity(0.6), .clear, .black.opacity(0.15)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
    
    private var pearlescentOverlay: some View {
        shapePath.fill(
            LinearGradient(
                colors: [
                    .white.opacity(0.5),
                    Color.pink.opacity(0.15),
                    Color.blue.opacity(0.1),
                    .clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
    
    private var iridescentOverlay: some View {
        let hueShift = Color(hue: 0.15, saturation: 0.4, brightness: 1.0)
        return shapePath.fill(hueShift.opacity(0.35)).blendMode(.plusLighter)
            .overlay(
                shapePath.fill(
                    LinearGradient(
                        colors: [.white.opacity(0.5), .clear],
                        startPoint: .topLeading,
                        endPoint: .center
                    )
                )
            )
    }
}

// MARK: - Shape Form (enum-based, Sendable-safe; no stored closures)

private enum SoulShapeForm: Shape {
    case circle, squircle, blob, capsule, diamond, hexagon, starSoft, leaf, wave, teardrop, roundedTriangle, smoothCross

    init(_ kind: SoulShape) {
        switch kind {
        case .circle: self = .circle
        case .squircle: self = .squircle
        case .blob: self = .blob
        case .capsule: self = .capsule
        case .diamond: self = .diamond
        case .hexagon: self = .hexagon
        case .starSoft: self = .starSoft
        case .leaf: self = .leaf
        case .wave: self = .wave
        case .teardrop: self = .teardrop
        case .roundedTriangle: self = .roundedTriangle
        case .smoothCross: self = .smoothCross
        }
    }

    func path(in rect: CGRect) -> Path {
        switch self {
        case .circle: return Circle().path(in: rect)
        case .squircle: return RoundedRectangle(cornerRadius: 14).path(in: rect)
        case .blob: return SoftBlobShape().path(in: rect)
        case .capsule: return Capsule().path(in: rect)
        case .diamond: return DiamondShape().path(in: rect)
        case .hexagon: return HexagonShape().path(in: rect)
        case .starSoft: return StarSoftShape().path(in: rect)
        case .leaf: return LeafShape().path(in: rect)
        case .wave: return WaveShape().path(in: rect)
        case .teardrop: return TeardropShape().path(in: rect)
        case .roundedTriangle: return RoundedTriangleShape().path(in: rect)
        case .smoothCross: return SmoothCrossShape().path(in: rect)
        }
    }
}

// MARK: - Custom Shapes

private struct SoftBlobShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let cx = w / 2, cy = h / 2
        let r = min(w, h) * 0.42
        var p = Path()
        let pts = 8
        for i in 0..<pts {
            let angle = (CGFloat(i) / CGFloat(pts)) * 2 * .pi - .pi / 2
            let wobble = 1.0 + (i % 2 == 0 ? 0.08 : -0.06)
            let x = cx + cos(angle) * r * wobble
            let y = cy + sin(angle) * r * wobble
            if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
            else { p.addLine(to: CGPoint(x: x, y: y)) }
        }
        p.closeSubpath()
        return p
    }
}

private struct DiamondShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let cx = w / 2, cy = h / 2
        let r = min(w, h) * 0.44
        var p = Path()
        p.move(to: CGPoint(x: cx, y: cy - r))
        p.addLine(to: CGPoint(x: cx + r * 0.85, y: cy))
        p.addLine(to: CGPoint(x: cx, y: cy + r))
        p.addLine(to: CGPoint(x: cx - r * 0.85, y: cy))
        p.closeSubpath()
        return p
    }
}

private struct HexagonShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let cx = w / 2, cy = h / 2
        let r = min(w, h) * 0.44
        var p = Path()
        for i in 0..<6 {
            let angle = (CGFloat(i) / 6) * 2 * .pi - .pi / 6
            let x = cx + cos(angle) * r
            let y = cy + sin(angle) * r
            if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
            else { p.addLine(to: CGPoint(x: x, y: y)) }
        }
        p.closeSubpath()
        return p
    }
}

private struct StarSoftShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let cx = w / 2, cy = h / 2
        let lobes = 5
        let outerR = min(w, h) * 0.42
        let innerR = outerR * 0.45
        var p = Path()
        for i in 0..<(lobes * 2) {
            let angle = (CGFloat(i) / CGFloat(lobes * 2)) * 2 * .pi - .pi / 2
            let r = i % 2 == 0 ? outerR : innerR
            let x = cx + cos(angle) * r
            let y = cy + sin(angle) * r
            if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
            else { p.addLine(to: CGPoint(x: x, y: y)) }
        }
        p.closeSubpath()
        return p
    }
}

private struct LeafShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let cx = w / 2, cy = h / 2
        let r = min(w, h) * 0.4
        var p = Path()
        let pts = 12
        for i in 0..<pts {
            let t = CGFloat(i) / CGFloat(pts)
            let angle = t * .pi
            let bulge = 1.0 + 0.3 * sin(angle * 2)
            let x = cx + (t - 0.5) * w * 0.85
            let y = cy - sin(angle) * r * bulge
            if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
            else { p.addLine(to: CGPoint(x: x, y: y)) }
        }
        for i in (0..<pts).reversed() {
            let t = CGFloat(i) / CGFloat(pts)
            let angle = t * .pi
            let bulge = 1.0 + 0.15 * sin(angle * 2)
            let x = cx + (t - 0.5) * w * 0.6
            let y = cy - sin(angle) * r * 0.4 * bulge
            p.addLine(to: CGPoint(x: x, y: y))
        }
        p.closeSubpath()
        return p
    }
}

private struct WaveShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        return Capsule().path(in: CGRect(x: 0, y: (h - h * 0.5) / 2, width: w, height: h * 0.5))
    }
}

private struct TeardropShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let cx = w / 2
        let top = h * 0.12
        let bottom = h * 0.88
        let r = w * 0.4
        var p = Path()
        p.move(to: CGPoint(x: cx, y: top))
        p.addQuadCurve(to: CGPoint(x: cx + r, y: bottom - r * 0.5), control: CGPoint(x: cx + r * 1.2, y: h * 0.4))
        p.addQuadCurve(to: CGPoint(x: cx, y: top), control: CGPoint(x: cx + r * 0.3, y: h * 0.5))
        p.closeSubpath()
        return p
    }
}

private struct RoundedTriangleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let cx = w / 2
        let r = min(w, h) * 0.38
        var p = Path()
        let pts: [(CGFloat, CGFloat)] = [(cx, h * 0.15), (w * 0.85, h * 0.82), (w * 0.15, h * 0.82)]
        for i in 0..<3 {
            let (x, y) = pts[i]
            if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
            else { p.addLine(to: CGPoint(x: x, y: y)) }
        }
        p.closeSubpath()
        return p
    }
}

private struct SmoothCrossShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let cx = w / 2, cy = h / 2
        let armW = w * 0.24
        let armH = h * 0.4
        let corner = min(armW, armH) * 0.45
        var p = Path()
        p.addRoundedRect(in: CGRect(x: cx - armW / 2, y: cy - armH / 2, width: armW, height: armH), cornerSize: CGSize(width: corner, height: corner))
        p.addRoundedRect(in: CGRect(x: cx - armH / 2, y: cy - armW / 2, width: armH, height: armW), cornerSize: CGSize(width: corner, height: corner))
        return p
    }
}

//
//  ShapeSelectionView.swift
//  EyEmote
//
//  Lets the user choose the geometry of their Soul Shape. Inherits color, opacity, and texture.
//  Same grid layout as Opacity/Texture; items morph from circles into shape options. Glowing halo on hover.
//

import SwiftUI

private let shapeRows = 2
private let shapeCols = 3
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
                        let gen = UIImpactFeedbackGenerator(style: .light)
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
                        ZStack {
                            ShapeTileView(
                                shapeKind: shapeKind,
                                baseColor: baseColor,
                                texture: gazeManager.selectedTexture
                            )
                            if isHovered {
                                haloFrame(shapeKind: shapeKind, color: baseColor)
                            }
                        }
                        .frame(width: cellW, height: cellH)
                        .contentShape(Rectangle())
                    }
                }
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hoveredIndex)
    }
    
    private func haloFrame(shapeKind: SoulShape, color: Color) -> some View {
        Group {
            switch shapeKind {
            case .circle:
                Circle()
                    .strokeBorder(color.opacity(0.95), lineWidth: 3)
                    .frame(width: 72, height: 72)
            case .squircle, .diamond:
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(color.opacity(0.95), lineWidth: 3)
                    .frame(width: 72, height: 72)
            case .softBlob, .flowerStar:
                Circle()
                    .strokeBorder(color.opacity(0.95), lineWidth: 3)
                    .frame(width: 72, height: 72)
            case .capsule:
                Capsule()
                    .strokeBorder(color.opacity(0.95), lineWidth: 3)
                    .frame(width: 80, height: 56)
            }
        }
        .shadow(color: color.opacity(0.9), radius: 8)
        .shadow(color: color.opacity(0.5), radius: 14)
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

// MARK: - Shape Tile (geometry + texture styling)

private struct ShapeTileView: View {
    let shapeKind: SoulShape
    let baseColor: Color
    let texture: SoulTexture
    
    private let size: CGFloat = 56
    
    var body: some View {
        ZStack {
            shapeContent
                .frame(width: shapeWidth, height: shapeHeight)
        }
    }
    
    private var shapeWidth: CGFloat {
        switch shapeKind {
        case .capsule: return 72
        default: return size
        }
    }
    
    private var shapeHeight: CGFloat { size }
    
    @ViewBuilder
    private var shapeContent: some View {
        let base = baseFill
        switch texture {
        case .glossy:
            base
                .overlay(specularHighlight)
                .overlay(glassStroke)
                .shadow(color: baseColor.opacity(0.6), radius: 10)
        case .frosted:
            base
                .overlay(shapePath.fill(.ultraThinMaterial).blendMode(.overlay))
                .overlay(shapePath.stroke(.white.opacity(0.4), lineWidth: 1.5))
                .shadow(color: baseColor.opacity(0.4), radius: 8)
        case .metallic:
            base
                .overlay(metallicHighlight)
                .overlay(shapePath.stroke(.white.opacity(0.5), lineWidth: 1))
                .shadow(color: baseColor.opacity(0.5), radius: 8)
        case .pearlescent:
            base
                .overlay(pearlescentOverlay)
                .overlay(shapePath.stroke(.white.opacity(0.35), lineWidth: 1.5))
                .shadow(color: baseColor.opacity(0.5), radius: 8)
        case .iridescent:
            base
                .overlay(iridescentOverlay)
                .overlay(shapePath.stroke(.white.opacity(0.4), lineWidth: 1.5))
                .shadow(color: baseColor.opacity(0.5), radius: 8)
        case .deepLiquid:
            base
                .overlay(shapePath.stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.3), .black.opacity(0.4)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2
                ))
                .shadow(color: .black.opacity(0.4), radius: 4)
                .shadow(color: baseColor.opacity(0.7), radius: 12)
        }
    }
    
    private var baseFill: some View {
        Group {
            if texture == .deepLiquid {
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
    case circle
    case squircle
    case softBlob
    case capsule
    case diamond
    case flowerStar

    init(_ kind: SoulShape) {
        switch kind {
        case .circle: self = .circle
        case .squircle: self = .squircle
        case .softBlob: self = .softBlob
        case .capsule: self = .capsule
        case .diamond: self = .diamond
        case .flowerStar: self = .flowerStar
        }
    }

    func path(in rect: CGRect) -> Path {
        switch self {
        case .circle: return Circle().path(in: rect)
        case .squircle: return RoundedRectangle(cornerRadius: 14).path(in: rect)
        case .softBlob: return SoftBlobShape().path(in: rect)
        case .capsule: return Capsule().path(in: rect)
        case .diamond: return DiamondShape().path(in: rect)
        case .flowerStar: return FlowerStarShape().path(in: rect)
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

private struct FlowerStarShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let cx = w / 2, cy = h / 2
        let lobes = 6
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

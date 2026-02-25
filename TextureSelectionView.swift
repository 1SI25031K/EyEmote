//
//  TextureSelectionView.swift
//  EyEmote
//
//  Lets the user choose the visual material (texture) of their Soul Shape.
//  Uses decidedColor and selectedAlpha. Same grid layout as Opacity phase; circles morph to texture variants.
//  No cursor; "Border Frame" (halo) feedback on hover.
//

import SwiftUI

private let textureRows = 2
private let textureCols = 3
private let textureTotal = textureRows * textureCols

private let textureCases: [SoulTexture] = SoulTexture.allCases

struct TextureSelectionView: View {
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
                
                textureGridView(
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
                    Text("Choose a texture. Confirm with your chosen method.")
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
                if newValue, !hasTriggeredSelection { tryConfirmTexture(size: size, cursorPt: cursorPt) }
            }
            .onChange(of: gazeManager.didPerformMouthOpenTwice) { newValue in
                if newValue, !hasTriggeredSelection { tryConfirmTexture(size: size, cursorPt: cursorPt) }
            }
            .onChange(of: gazeManager.dwellTime) { _ in
                if gazeManager.selectedDecisionMethod == .dwell,
                   indexUnderCursor != nil,
                   gazeManager.dwellTime >= dwellThreshold,
                   !hasTriggeredSelection {
                    tryConfirmTexture(size: size, cursorPt: cursorPt)
                }
            }
        }
        .ignoresSafeArea()
    }
    
    private func textureGridView(size: CGSize, baseColor: Color, hoveredIndex: Int?) -> some View {
        let cellW = size.width / CGFloat(textureCols)
        let cellH = size.height / CGFloat(textureRows)
        
        return Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            ForEach(0..<textureRows, id: \.self) { row in
                GridRow {
                    ForEach(0..<textureCols, id: \.self) { col in
                        let index = row * textureCols + col
                        let texture = textureCases[index]
                        let isHovered = hoveredIndex == index
                        ZStack {
                            TextureTileView(texture: texture, baseColor: baseColor)
                            if isHovered {
                                haloFrame(color: baseColor)
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
    
    private func haloFrame(color: Color) -> some View {
        Circle()
            .strokeBorder(
                color.opacity(0.95),
                lineWidth: 3
            )
            .frame(width: 72, height: 72)
            .shadow(color: color.opacity(0.9), radius: 8)
            .shadow(color: color.opacity(0.5), radius: 14)
    }
    
    private func tileIndexAt(point: CGPoint, in size: CGSize) -> Int? {
        guard point.x >= 0, point.x < size.width, point.y >= 0, point.y < size.height else { return nil }
        let col = Int((point.x / size.width) * CGFloat(textureCols))
        let row = Int((point.y / size.height) * CGFloat(textureRows))
        let c = max(0, min(textureCols - 1, col))
        let r = max(0, min(textureRows - 1, row))
        return r * textureCols + c
    }
    
    private func tryConfirmTexture(size: CGSize, cursorPt: CGPoint) {
        guard let index = tileIndexAt(point: cursorPt, in: size), !hasTriggeredSelection else {
            gazeManager.didPerformDeepBlink = false
            gazeManager.didPerformMouthOpenTwice = false
            return
        }
        hasTriggeredSelection = true
        gazeManager.selectedTexture = textureCases[index]
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

// MARK: - Texture Tile (one circle per SoulTexture variant)

private struct TextureTileView: View {
    let texture: SoulTexture
    let baseColor: Color
    
    var body: some View {
        switch texture {
        case .glossy:
            glossyCircle
        case .frosted:
            frostedCircle
        case .metallic:
            metallicCircle
        case .pearlescent:
            pearlescentCircle
        case .iridescent:
            iridescentCircle
        case .deepLiquid:
            deepLiquidCircle
        }
    }
    
    private var glossyCircle: some View {
        ZStack {
            Circle()
                .fill(baseColor)
                .overlay(
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.85), .white.opacity(0.1), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.9), .white.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                )
                .shadow(color: baseColor.opacity(0.6), radius: 10)
        }
        .frame(width: 56, height: 56)
    }
    
    private var frostedCircle: some View {
        ZStack {
            Circle()
                .fill(baseColor)
            Circle()
                .fill(.ultraThinMaterial)
                .blendMode(.overlay)
            Circle()
                .strokeBorder(.white.opacity(0.4), lineWidth: 1.5)
        }
        .frame(width: 56, height: 56)
        .shadow(color: baseColor.opacity(0.4), radius: 8)
    }
    
    private var metallicCircle: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            baseColor,
                            baseColor.opacity(0.7),
                            baseColor.opacity(0.5)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.6), .clear, .black.opacity(0.15)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
                .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 1))
                .shadow(color: baseColor.opacity(0.5), radius: 8)
        }
        .frame(width: 56, height: 56)
    }
    
    private var pearlescentCircle: some View {
        ZStack {
            Circle()
                .fill(baseColor)
                .overlay(
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.5),
                                    Color.pink.opacity(0.15),
                                    Color.blue.opacity(0.1),
                                    .clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1.5))
                .shadow(color: baseColor.opacity(0.5), radius: 8)
        }
        .frame(width: 56, height: 56)
    }
    
    private var iridescentCircle: some View {
        let hueShift = Color(hue: 0.15, saturation: 0.4, brightness: 1.0)
        return ZStack {
            Circle()
                .fill(baseColor)
                .overlay(
                    Circle()
                        .fill(hueShift.opacity(0.35))
                        .blendMode(.plusLighter)
                )
                .overlay(
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.5), .clear],
                                startPoint: .topLeading,
                                endPoint: .center
                            )
                        )
                )
                .overlay(Circle().strokeBorder(.white.opacity(0.4), lineWidth: 1.5))
                .shadow(color: baseColor.opacity(0.5), radius: 8)
        }
        .frame(width: 56, height: 56)
    }
    
    private var deepLiquidCircle: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            baseColor,
                            baseColor.opacity(0.8),
                            baseColor.opacity(0.4)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 35
                    )
                )
                .overlay(
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.3), .black.opacity(0.4)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                )
                .shadow(color: .black.opacity(0.4), radius: 4)
                .shadow(color: baseColor.opacity(0.7), radius: 12)
        }
        .frame(width: 56, height: 56)
    }
}

//
//  TextureSelectionView.swift
//  EyEmote
//
//  Lets the user choose the visual material (texture) of their Soul Shape.
//  Uses decidedColor and selectedAlpha. 3x4 grid; lift & scale feedback on hover. No cursor.
//

import SwiftUI

private let textureRows = 3
private let textureCols = 4
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
                        let gen = UIImpactFeedbackGenerator(style: .medium)
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
                        TextureTileView(texture: texture, baseColor: baseColor, isHovered: isHovered)
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

// MARK: - Texture Tile (one circle per SoulTexture variant; lift & scale when hovered)

private struct TextureTileView: View {
    let texture: SoulTexture
    let baseColor: Color
    let isHovered: Bool
    
    var body: some View {
        Group {
            switch texture {
            case .glossy: glossyCircle
            case .frosted: frostedCircle
            case .metallic: metallicCircle
            case .pearlescent: pearlescentCircle
            case .iridescent: iridescentCircle
            case .chrome: chromeCircle
            case .holographic: holographicCircle
            case .neonGlow: neonGlowCircle
            case .glassyJelly: glassyJellyCircle
            case .brushedAluminum: brushedAluminumCircle
            case .deepVelvet: deepVelvetCircle
            case .crystal: crystalCircle
            }
        }
        .frame(width: 56, height: 56)
        .scaleEffect(isHovered ? 1.2 : 1.0)
        .offset(y: isHovered ? -15 : 0)
        .shadow(color: baseColor.opacity(isHovered ? 0.7 : 0.4), radius: isHovered ? 18 : 8)
        .shadow(color: .black.opacity(isHovered ? 0.35 : 0.15), radius: isHovered ? 12 : 4)
        .animation(.interactiveSpring(response: 0.35, dampingFraction: 0.65), value: isHovered)
    }
    
    private var glossyCircle: some View {
        ZStack {
            Circle().fill(baseColor)
                .overlay(Circle().fill(LinearGradient(colors: [.white.opacity(0.85), .white.opacity(0.1), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)))
                .overlay(Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.9), .white.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2))
        }
    }
    
    private var frostedCircle: some View {
        ZStack {
            Circle().fill(baseColor)
            Circle().fill(.ultraThinMaterial).blendMode(.overlay)
            Circle().strokeBorder(.white.opacity(0.4), lineWidth: 1.5)
        }
    }
    
    private var metallicCircle: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [baseColor, baseColor.opacity(0.7), baseColor.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(Circle().fill(LinearGradient(colors: [.white.opacity(0.6), .clear, .black.opacity(0.15)], startPoint: .top, endPoint: .bottom)))
                .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 1))
        }
    }
    
    private var pearlescentCircle: some View {
        ZStack {
            Circle().fill(baseColor)
                .overlay(Circle().fill(LinearGradient(colors: [.white.opacity(0.5), Color.pink.opacity(0.15), Color.blue.opacity(0.1), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)))
                .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1.5))
        }
    }
    
    private var iridescentCircle: some View {
        let hueShift = Color(hue: 0.15, saturation: 0.4, brightness: 1.0)
        return ZStack {
            Circle().fill(baseColor)
                .overlay(Circle().fill(hueShift.opacity(0.35)).blendMode(.plusLighter))
                .overlay(Circle().fill(LinearGradient(colors: [.white.opacity(0.5), .clear], startPoint: .topLeading, endPoint: .center)))
                .overlay(Circle().strokeBorder(.white.opacity(0.4), lineWidth: 1.5))
        }
    }
    
    private var chromeCircle: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [.white.opacity(0.9), baseColor.opacity(0.8), baseColor.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(Circle().fill(LinearGradient(colors: [.white.opacity(0.8), .clear], startPoint: .top, endPoint: .center)))
                .overlay(Circle().strokeBorder(LinearGradient(colors: [.white, .white.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5))
        }
    }
    
    private var holographicCircle: some View {
        ZStack {
            Circle().fill(baseColor)
                .overlay(Circle().fill(LinearGradient(colors: [Color.cyan.opacity(0.4), Color.purple.opacity(0.3), Color.pink.opacity(0.2), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)).blendMode(.plusLighter))
                .overlay(Circle().fill(LinearGradient(colors: [.white.opacity(0.6), .clear], startPoint: .topLeading, endPoint: .center)))
                .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 1.5))
        }
    }
    
    private var neonGlowCircle: some View {
        ZStack {
            Circle().fill(baseColor)
                .overlay(Circle().strokeBorder(baseColor, lineWidth: 2))
                .shadow(color: baseColor, radius: 12)
                .shadow(color: baseColor.opacity(0.8), radius: 6)
        }
    }
    
    private var glassyJellyCircle: some View {
        ZStack {
            Circle().fill(baseColor.opacity(0.9))
                .overlay(Circle().fill(LinearGradient(colors: [.white.opacity(0.6), .clear], startPoint: .topLeading, endPoint: .center)))
                .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 2))
        }
        .blur(radius: 0.5)
    }
    
    private var brushedAluminumCircle: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [baseColor.opacity(0.95), baseColor.opacity(0.7)], startPoint: .top, endPoint: .bottom))
                .overlay(Circle().fill(LinearGradient(colors: [.white.opacity(0.4), .white.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing)))
                .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1))
        }
    }
    
    private var deepVelvetCircle: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [baseColor, baseColor.opacity(0.6)], center: .center, startRadius: 0, endRadius: 35))
                .overlay(Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.2), .black.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2))
        }
    }
    
    private var crystalCircle: some View {
        ZStack {
            Circle().fill(baseColor)
                .overlay(Circle().fill(LinearGradient(colors: [.white.opacity(0.9), .white.opacity(0.2), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)))
                .overlay(Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.95), .white.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2))
        }
    }
}

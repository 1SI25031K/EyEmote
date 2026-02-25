//
//  OpacitySelectionView.swift
//  EyEmote
//
//  Lets the user choose the transparency (alpha) of decidedColor via a discrete grid.
//  Transition: single Soul Shape "splits" into a grid of opacity options. No visible cursor; lift feedback.
//

import SwiftUI

private let opacityRows = 2
private let opacityCols = 5
private let opacityTotal = opacityRows * opacityCols

private let opacityValues: [Double] = (1...opacityTotal).map { Double($0) / Double(opacityTotal) }

struct OpacitySelectionView: View {
    @ObservedObject var gazeManager: GazeManager
    var onComplete: () -> Void
    
    private let dwellThreshold: TimeInterval = 3.0
    
    @State private var showSingleCircle: Bool = true
    @State private var hoveredIndex: Int? = nil
    @State private var lastHoveredIndex: Int? = nil
    @State private var confirmedIndex: Int? = nil
    @State private var confirmPulsateScale: CGFloat = 1.0
    @State private var hasTriggeredSelection = false
    
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let rel = gazeManager.cursorRelativePosition
            let cursorPt = CGPoint(x: rel.x * size.width, y: rel.y * size.height)
            let indexUnderCursor = tileIndexAt(point: cursorPt, in: size)
            let baseColor = gazeManager.decidedColor ?? Color.white
            
            ZStack {
                Color.black
                    .ignoresSafeArea()
                
                if showSingleCircle {
                    singleSoulCircle(color: baseColor)
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
                
                ZStack {
                    opacityGridView(
                        size: size,
                        baseColor: baseColor,
                        hoveredIndex: hoveredIndex,
                        confirmedIndex: confirmedIndex,
                        confirmPulsateScale: confirmPulsateScale
                    )
                    if gazeManager.selectedDecisionMethod == .dwell,
                       indexUnderCursor != nil,
                       !hasTriggeredSelection,
                       gazeManager.dwellTime > 0 {
                        dwellProgressOverlay(progress: min(1.0, gazeManager.dwellTime / dwellThreshold))
                    }
                }
                .opacity(showSingleCircle ? 0 : 1)
                .scaleEffect(showSingleCircle ? 0.5 : 1)
                .animation(.interactiveSpring(response: 0.5, dampingFraction: 0.75), value: showSingleCircle)
                
                VStack {
                    Spacer()
                    Text("Choose transparency. Confirm with your chosen method.")
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
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    withAnimation(.interactiveSpring(response: 0.55, dampingFraction: 0.8)) {
                        showSingleCircle = false
                    }
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
                if newValue, !hasTriggeredSelection { tryConfirmOpacity(size: size, cursorPt: cursorPt) }
            }
            .onChange(of: gazeManager.didPerformMouthOpenTwice) { newValue in
                if newValue, !hasTriggeredSelection { tryConfirmOpacity(size: size, cursorPt: cursorPt) }
            }
            .onChange(of: gazeManager.dwellTime) { _ in
                if gazeManager.selectedDecisionMethod == .dwell,
                   indexUnderCursor != nil,
                   gazeManager.dwellTime >= dwellThreshold,
                   !hasTriggeredSelection {
                    tryConfirmOpacity(size: size, cursorPt: cursorPt)
                }
            }
        }
        .ignoresSafeArea()
        .drawingGroup(opaque: false, colorMode: .nonLinear)
    }
    
    private func singleSoulCircle(color: Color) -> some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [color.opacity(0.9), color.opacity(0.5)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 120
                    )
                )
                .frame(width: 200, height: 200)
                .blur(radius: 8)
                .opacity(0.8)
            Circle()
                .fill(color)
                .frame(width: 160, height: 160)
                .overlay(
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.7), .white.opacity(0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 3
                        )
                )
                .shadow(color: color.opacity(0.9), radius: 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func opacityGridView(size: CGSize, baseColor: Color, hoveredIndex: Int?, confirmedIndex: Int?, confirmPulsateScale: CGFloat) -> some View {
        let cellW = size.width / CGFloat(opacityCols)
        let cellH = size.height / CGFloat(opacityRows)
        
        return Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            ForEach(0..<opacityRows, id: \.self) { row in
                GridRow {
                    ForEach(0..<opacityCols, id: \.self) { col in
                        let index = row * opacityCols + col
                        let alpha = opacityValues[index]
                        OpacityTileView(
                            color: baseColor.opacity(alpha),
                            isHovered: hoveredIndex == index,
                            pulsateScale: confirmedIndex == index ? confirmPulsateScale : 1.0
                        )
                        .frame(width: cellW, height: cellH)
                        .contentShape(Rectangle())
                    }
                }
            }
        }
    }
    
    private func tileIndexAt(point: CGPoint, in size: CGSize) -> Int? {
        guard point.x >= 0, point.x < size.width, point.y >= 0, point.y < size.height else { return nil }
        let col = Int((point.x / size.width) * CGFloat(opacityCols))
        let row = Int((point.y / size.height) * CGFloat(opacityRows))
        let c = max(0, min(opacityCols - 1, col))
        let r = max(0, min(opacityRows - 1, row))
        return r * opacityCols + c
    }
    
    private func tryConfirmOpacity(size: CGSize, cursorPt: CGPoint) {
        guard let index = tileIndexAt(point: cursorPt, in: size), !hasTriggeredSelection else {
            gazeManager.didPerformDeepBlink = false
            gazeManager.didPerformMouthOpenTwice = false
            return
        }
        hasTriggeredSelection = true
        let alpha = opacityValues[index]
        confirmedIndex = index
        gazeManager.selectedAlpha = alpha
        gazeManager.didPerformDeepBlink = false
        gazeManager.didPerformMouthOpenTwice = false
        
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.6)) { confirmPulsateScale = 1.25 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.7)) { confirmPulsateScale = 1.0 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
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

private struct OpacityTileView: View {
    let color: Color
    let isHovered: Bool
    var pulsateScale: CGFloat = 1.0
    
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [color.opacity(0.95), color.opacity(0.6)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 50
                    )
                )
                .frame(width: 64, height: 64)
                .blur(radius: 4)
                .opacity(0.7)
            
            Circle()
                .fill(color)
                .frame(width: 56, height: 56)
                .overlay(
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.6), .white.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                )
                .shadow(color: color.opacity(isHovered ? 0.8 : 0.4), radius: isHovered ? 14 : 6)
                .scaleEffect(isHovered ? 1.2 : 1.0)
                .scaleEffect(pulsateScale)
                .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.6), value: isHovered)
                .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.6), value: pulsateScale)
            
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.4), .clear],
                        startPoint: .topLeading,
                        endPoint: .center
                    )
                )
                .frame(width: 28, height: 28)
                .offset(x: -10, y: -10)
                .blendMode(.overlay)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

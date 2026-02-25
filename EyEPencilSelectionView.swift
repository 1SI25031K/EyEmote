//
//  EyEPencilSelectionView.swift
//  EyEmote
//
//  Discrete pencil grid selection (EyEPencil) replacing the gradient wheel
//  for better gaze affordance and inclusion. Left: grid; Right: Soul Shape preview.
//  Gaze is clamped to the left half ("invisible wall"); no visible cursor in this phase.
//

import SwiftUI

// MARK: - EyEPencil Color Palette (4 rows × 12 columns = 48 pencils)

private let eyepencilRows = 4
private let eyepencilCols = 12
private let eyepencilTotal = eyepencilRows * eyepencilCols

private let eyepencilColors: [Color] = {
    var colors: [Color] = []
    let row1: [Color] = [
        Color(red: 1.0, green: 0.95, blue: 0.4),
        Color(red: 1.0, green: 0.85, blue: 0.2),
        Color(red: 1.0, green: 0.6, blue: 0.1),
        Color(red: 1.0, green: 0.35, blue: 0.2),
        Color(red: 0.95, green: 0.25, blue: 0.35),
        Color(red: 0.9, green: 0.2, blue: 0.5),
        Color(red: 0.7, green: 0.2, blue: 0.7),
        Color(red: 0.5, green: 0.25, blue: 0.85),
        Color(red: 0.25, green: 0.4, blue: 0.95),
        Color(red: 0.2, green: 0.65, blue: 0.9),
        Color(red: 0.2, green: 0.8, blue: 0.7),
        Color(red: 0.3, green: 0.85, blue: 0.4)
    ]
    let row2: [Color] = [
        Color(red: 0.5, green: 0.9, blue: 0.3),
        Color(red: 0.75, green: 0.9, blue: 0.2),
        Color(red: 0.95, green: 0.75, blue: 0.15),
        Color(red: 0.95, green: 0.5, blue: 0.1),
        Color(red: 0.9, green: 0.35, blue: 0.3),
        Color(red: 0.85, green: 0.3, blue: 0.5),
        Color(red: 0.6, green: 0.35, blue: 0.8),
        Color(red: 0.4, green: 0.5, blue: 0.9),
        Color(red: 0.3, green: 0.7, blue: 0.85),
        Color(red: 0.35, green: 0.8, blue: 0.6),
        Color(red: 0.4, green: 0.75, blue: 0.4),
        Color(red: 0.55, green: 0.7, blue: 0.35)
    ]
    let row3: [Color] = [
        Color(red: 0.6, green: 0.55, blue: 0.35),
        Color(red: 0.7, green: 0.5, blue: 0.3),
        Color(red: 0.8, green: 0.4, blue: 0.25),
        Color(red: 0.75, green: 0.3, blue: 0.25),
        Color(red: 0.6, green: 0.25, blue: 0.3),
        Color(red: 0.5, green: 0.25, blue: 0.45),
        Color(red: 0.4, green: 0.3, blue: 0.55),
        Color(red: 0.35, green: 0.4, blue: 0.5),
        Color(red: 0.4, green: 0.5, blue: 0.5),
        Color(red: 0.45, green: 0.55, blue: 0.4),
        Color(red: 0.5, green: 0.5, blue: 0.35),
        Color(red: 0.55, green: 0.5, blue: 0.4)
    ]
    let row4: [Color] = [
        Color(red: 0.6, green: 0.55, blue: 0.55),
        Color(red: 0.5, green: 0.5, blue: 0.5),
        Color(red: 0.4, green: 0.4, blue: 0.42),
        Color(red: 0.35, green: 0.35, blue: 0.38),
        Color(red: 0.95, green: 0.9, blue: 0.85),
        Color(red: 0.9, green: 0.85, blue: 0.95),
        Color(red: 0.9, green: 0.95, blue: 0.9),
        Color(red: 0.95, green: 0.92, blue: 0.88),
        Color(red: 0.3, green: 0.25, blue: 0.2),
        Color(red: 0.45, green: 0.35, blue: 0.25),
        Color(red: 0.55, green: 0.4, blue: 0.3),
        Color(red: 0.5, green: 0.3, blue: 0.25)
    ]
    colors.append(contentsOf: row1)
    colors.append(contentsOf: row2)
    colors.append(contentsOf: row3)
    colors.append(contentsOf: row4)
    return colors
}()

// MARK: - EyEPencil Selection View

struct EyEPencilSelectionView: View {
    @ObservedObject var gazeManager: GazeManager
    var onComplete: () -> Void
    
    private let dwellThreshold: TimeInterval = 3.0
    /// Minimum target size for gaze (pt). Hit test uses nearest-pencil within this radius for stable selection.
    private let pencilHitRadiusPt: CGFloat = 44
    
    @State private var hoveredIndex: Int? = nil
    @State private var selectedColor: Color? = nil
    @State private var soulPulsateScale: CGFloat = 1.0
    @State private var hasTriggeredSelection = false
    @State private var lastHoveredIndex: Int? = nil
    
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let rel = gazeManager.cursorRelativePosition
            let leftWidth = size.width / 2
            let clampedXRel = min(rel.x, 0.5)
            let clampedCursorPt = CGPoint(
                x: clampedXRel * size.width,
                y: rel.y * size.height
            )
            let indexUnderCursor = pencilIndexAt(point: clampedCursorPt, in: size)
            
            ZStack {
                Color.black
                    .ignoresSafeArea()
                
                HStack(spacing: 0) {
                    EyEPencilGridView(
                        cursorPt: clampedCursorPt,
                        viewSize: size,
                        hoveredIndex: $hoveredIndex
                    )
                    .frame(width: leftWidth, height: size.height)
                    
                    ZStack {
                        SoulShapePreviewView(
                            color: displayColor(index: indexUnderCursor),
                            isConfirmed: selectedColor != nil,
                            pulsateScale: soulPulsateScale
                        )
                        if gazeManager.selectedDecisionMethod == .dwell,
                           indexUnderCursor != nil,
                           selectedColor == nil,
                           gazeManager.dwellTime > 0 {
                            dwellProgressRing(progress: min(1.0, gazeManager.dwellTime / dwellThreshold))
                        }
                    }
                    .frame(width: leftWidth, height: size.height)
                }
                
                VStack {
                    Spacer()
                    Text("Look at a pencil, then confirm with your chosen method.")
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
                if newValue, !hasTriggeredSelection { tryConfirmPencil(size: size, cursorPt: clampedCursorPt) }
            }
            .onChange(of: gazeManager.didPerformMouthOpenTwice) { newValue in
                if newValue, !hasTriggeredSelection { tryConfirmPencil(size: size, cursorPt: clampedCursorPt) }
            }
            .onChange(of: gazeManager.dwellTime) { _ in
                if gazeManager.selectedDecisionMethod == .dwell,
                   indexUnderCursor != nil,
                   gazeManager.dwellTime >= dwellThreshold,
                   !hasTriggeredSelection {
                    tryConfirmPencil(size: size, cursorPt: clampedCursorPt)
                }
            }
        }
        .ignoresSafeArea()
    }
    
    private func displayColor(index: Int?) -> Color {
        if let c = selectedColor { return c }
        guard let i = index, i >= 0, i < eyepencilTotal else {
            return hoveredIndex.flatMap { eyepencilColors[$0] } ?? Color.white.opacity(0.3)
        }
        return eyepencilColors[i]
    }
    
    /// Maps gaze point to pencil index: nearest pencil center within hit radius (gaze-friendly, accommodates jitter).
    private func pencilIndexAt(point: CGPoint, in size: CGSize) -> Int? {
        let leftWidth = size.width / 2
        guard point.y >= 0, point.y < size.height else { return nil }
        let cellW = leftWidth / CGFloat(eyepencilCols)
        let cellH = size.height / CGFloat(eyepencilRows)
        var bestIndex: Int? = nil
        var bestDist: CGFloat = pencilHitRadiusPt + 1
        for r in 0..<eyepencilRows {
            for c in 0..<eyepencilCols {
                let cx = (CGFloat(c) + 0.5) * cellW
                let cy = (CGFloat(r) + 0.5) * cellH
                let d = hypot(point.x - cx, point.y - cy)
                if d < bestDist {
                    bestDist = d
                    bestIndex = r * eyepencilCols + c
                }
            }
        }
        return bestDist <= pencilHitRadiusPt ? bestIndex : nil
    }
    
    private func tryConfirmPencil(size: CGSize, cursorPt: CGPoint) {
        let idx = pencilIndexAt(point: cursorPt, in: size)
        guard let index = idx, !hasTriggeredSelection else {
            gazeManager.didPerformDeepBlink = false
            gazeManager.didPerformMouthOpenTwice = false
            return
        }
        hasTriggeredSelection = true
        let color = eyepencilColors[index]
        selectedColor = color
        gazeManager.decidedColor = color
        gazeManager.didPerformDeepBlink = false
        gazeManager.didPerformMouthOpenTwice = false
        
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { soulPulsateScale = 1.2 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { soulPulsateScale = 1.0 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            onComplete()
        }
    }
    
    private func dwellProgressRing(progress: Double) -> some View {
        Circle()
            .stroke(Color.white.opacity(0.2), lineWidth: 4)
            .frame(width: 200, height: 200)
            .overlay(
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        Color.white.opacity(0.9),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 200, height: 200)
                .animation(.easeInOut(duration: 0.1), value: progress)
            )
    }
}

// MARK: - EyEPencil Grid (left half)

private struct EyEPencilGridView: View {
    let cursorPt: CGPoint
    let viewSize: CGSize
    @Binding var hoveredIndex: Int?
    
    private let cols = eyepencilCols
    private let rows = eyepencilRows
    private let minTouchPt: CGFloat = 56
    
    var body: some View {
        let leftWidth = viewSize.width / 2
        let cellW = leftWidth / CGFloat(cols)
        let cellH = viewSize.height / CGFloat(rows)
        let padX = max(0, (cellW - minTouchPt) / 2)
        let padY = max(0, (cellH - minTouchPt) / 2)
        
        Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            ForEach(0..<rows, id: \.self) { row in
                GridRow {
                    ForEach(0..<cols, id: \.self) { col in
                        let index = row * cols + col
                        let isHovered = hoveredIndex == index
                        EyEPencilCell(
                            color: eyepencilColors[index],
                            isHovered: isHovered
                        )
                        .frame(minWidth: cellW, minHeight: cellH)
                        .contentShape(Rectangle())
                    }
                }
            }
        }
        .padding(.horizontal, padX)
        .padding(.vertical, padY)
        .onChange(of: cursorPt.x) { _ in updateHover(cursorPt: cursorPt, leftWidth: leftWidth) }
        .onChange(of: cursorPt.y) { _ in updateHover(cursorPt: cursorPt, leftWidth: leftWidth) }
        .onAppear { updateHover(cursorPt: cursorPt, leftWidth: leftWidth) }
    }
    
    private func updateHover(cursorPt: CGPoint, leftWidth: CGFloat) {
        guard cursorPt.x >= 0, cursorPt.x < leftWidth,
              cursorPt.y >= 0, cursorPt.y < viewSize.height else {
            hoveredIndex = nil
            return
        }
        let col = Int((cursorPt.x / leftWidth) * CGFloat(cols))
        let row = Int((cursorPt.y / viewSize.height) * CGFloat(rows))
        let c = max(0, min(cols - 1, col))
        let r = max(0, min(rows - 1, row))
        hoveredIndex = r * cols + c
    }
}

// MARK: - Single Pencil Cell (wooden tip + colored body, lift on hover)

private struct EyEPencilCell: View {
    let color: Color
    let isHovered: Bool
    
    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.85, green: 0.75, blue: 0.55), Color(red: 0.7, green: 0.55, blue: 0.35)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 6, height: 20)
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(maxWidth: .infinity, minHeight: 20)
        }
        .padding(6)
        .scaleEffect(isHovered ? 1.08 : 1.0)
        .offset(y: isHovered ? -10 : 0)
        .shadow(color: isHovered ? color.opacity(0.6) : .clear, radius: 8)
        .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.6), value: isHovered)
    }
}

// MARK: - Soul Shape Preview (right half, Liquid Glass)

private struct SoulShapePreviewView: View {
    let color: Color
    let isConfirmed: Bool
    let pulsateScale: CGFloat
    
    var body: some View {
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
                .shadow(color: color.opacity(0.9), radius: isConfirmed ? 28 : 18)
                .shadow(color: color.opacity(0.4), radius: isConfirmed ? 44 : 28)
                .scaleEffect(pulsateScale)
            
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.5), .clear],
                        startPoint: .topLeading,
                        endPoint: .center
                    )
                )
                .frame(width: 80, height: 80)
                .offset(x: -30, y: -30)
                .blendMode(.overlay)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

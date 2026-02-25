//
//  FeelingColorPickerView.swift
//  EyEmote
//
//  User picks a feeling color via gaze and confirms with their selected decision method.
//

import SwiftUI

// MARK: - Helpers

private func hueFromAngle(_ angle: CGFloat) -> Double {
    let normalized = (angle + .pi) / (2 * .pi)
    return Double(normalized.truncatingRemainder(dividingBy: 1.0))
}

private func colorFromCursor(relative position: CGPoint, center: CGPoint = CGPoint(x: 0.5, y: 0.5), wheelRadius: CGFloat) -> Color {
    let dx = position.x - center.x
    let dy = position.y - center.y
    let distance = sqrt(dx * dx + dy * dy)
    let angle = atan2(dy, dx)
    let hue = hueFromAngle(angle)
    let saturation = distance > 0 ? min(1.0, Double(distance / wheelRadius)) : 0
    return Color(hue: hue, saturation: saturation, brightness: 1.0)
}

private func isCursorInsideWheel(_ position: CGPoint, center: CGPoint = CGPoint(x: 0.5, y: 0.5), wheelRadius: CGFloat) -> Bool {
    let dx = position.x - center.x
    let dy = position.y - center.y
    return sqrt(dx * dx + dy * dy) <= wheelRadius
}

// MARK: - Feeling Color Picker View

struct FeelingColorPickerView: View {
    @ObservedObject var gazeManager: GazeManager
    var onComplete: () -> Void
    
    private let wheelRadiusRelative: CGFloat = 0.38
    private let dwellThreshold: TimeInterval = 3.0
    
    @State private var selectedColor: Color?
    @State private var lastHoverColor: Color = .white
    @State private var soulPulsateScale: CGFloat = 1.0
    @State private var hasTriggeredSelection = false
    
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let wheelSize = min(size.width, size.height) * 0.78
            let centerPt = CGPoint(x: size.width / 2, y: size.height / 2)
            let cursorPt = CGPoint(
                x: gazeManager.cursorRelativePosition.x * size.width,
                y: gazeManager.cursorRelativePosition.y * size.height
            )
            let rel = gazeManager.cursorRelativePosition
            let insideWheel = isCursorInsideWheel(rel, wheelRadius: wheelRadiusRelative)
            let currentColor = colorFromCursor(relative: rel, wheelRadius: wheelRadiusRelative)
            let dwellProgress = insideWheel ? min(1.0, gazeManager.dwellTime / dwellThreshold) : 0
            
            ZStack {
                Color.black
                    .ignoresSafeArea()
                
                colorWheelView(size: wheelSize)
                    .position(centerPt)
                
                soulCrystalView(
                    currentColor: selectedColor ?? (insideWheel ? currentColor : lastHoverColor),
                    isSelected: selectedColor != nil,
                    pulsateScale: soulPulsateScale
                )
                .position(centerPt)
                
                if gazeManager.selectedDecisionMethod == .dwell, insideWheel, dwellProgress > 0, selectedColor == nil {
                    dwellProgressRing(progress: dwellProgress)
                        .position(centerPt)
                }
                
                if gazeManager.isFaceDetected, selectedColor == nil {
                    gazeCursorOnWheel(position: cursorPt, center: centerPt, wheelSize: wheelSize)
                }
                
                VStack {
                    Spacer()
                    instructionText
                        .padding(.bottom, 50)
                }
            }
            .onAppear {
                gazeManager.isInDecisionSelectionPhase = true
            }
            .onDisappear {
                gazeManager.isInDecisionSelectionPhase = false
            }
            .onChange(of: gazeManager.cursorRelativePosition) { _ in
                if insideWheel { lastHoverColor = currentColor }
            }
            .onChange(of: gazeManager.didPerformDeepBlink) { newValue in
                if newValue, !hasTriggeredSelection { tryConfirmColor() }
            }
            .onChange(of: gazeManager.didPerformMouthOpenTwice) { newValue in
                if newValue, !hasTriggeredSelection { tryConfirmColor() }
            }
            .onChange(of: gazeManager.dwellTime) { _ in
                if gazeManager.selectedDecisionMethod == .dwell, insideWheel, gazeManager.dwellTime >= dwellThreshold, !hasTriggeredSelection {
                    tryConfirmColor()
                }
            }
        }
        .ignoresSafeArea()
    }
    
    private var instructionText: some View {
        Text("Look at a color, then confirm with your chosen method.")
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundColor(.white.opacity(0.7))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
    }
    
    private func colorWheelView(size: CGFloat) -> some View {
        let gradient = AngularGradient(
            colors: [
                .red, .orange, .yellow, .green, .blue,
                Color(hue: 0.75, saturation: 1, brightness: 1),
                .purple, .red
            ],
            center: .center
        )
        return ZStack {
            Circle()
                .fill(gradient)
                .frame(width: size, height: size)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.35), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: size / 2
                    )
                )
                .frame(width: size, height: size)
            Circle()
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                .frame(width: size, height: size)
        }
        .overlay(
            Circle()
                .fill(.ultraThinMaterial.opacity(0.15))
                .frame(width: size, height: size)
        )
        .frame(width: size, height: size)
    }
    
    private func soulCrystalView(currentColor: Color, isSelected: Bool, pulsateScale: CGFloat) -> some View {
        let neon = Color(red: 0.4, green: 1.0, blue: 0.6)
        return Circle()
            .fill(currentColor)
            .frame(width: 72, height: 72)
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
            .shadow(color: currentColor.opacity(0.8), radius: isSelected ? 20 : 12)
            .shadow(color: currentColor.opacity(0.4), radius: isSelected ? 32 : 20)
            .scaleEffect(pulsateScale)
    }
    
    private func dwellProgressRing(progress: Double) -> some View {
        let neon = Color(red: 0.4, green: 1.0, blue: 0.6)
        return Circle()
            .stroke(Color.white.opacity(0.2), lineWidth: 4)
            .frame(width: 88, height: 88)
            .overlay(
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(neon, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 88, height: 88)
                    .shadow(color: neon.opacity(0.8), radius: 6)
            )
            .animation(.easeInOut(duration: 0.1), value: progress)
    }
    
    private func gazeCursorOnWheel(position: CGPoint, center: CGPoint, wheelSize: CGFloat) -> some View {
        let dx = position.x - center.x
        let dy = position.y - center.y
        let dist = sqrt(dx * dx + dy * dy)
        let maxDist = wheelSize / 2
        let clampedDist = min(dist, maxDist)
        let angle = atan2(dy, dx)
        let clampedX = center.x + cos(angle) * clampedDist
        let clampedY = center.y + sin(angle) * clampedDist
        return Circle()
            .stroke(Color.white, lineWidth: 2)
            .frame(width: 24, height: 24)
            .background(Circle().fill(Color.black.opacity(0.3)))
            .position(x: clampedX, y: clampedY)
            .animation(.interactiveSpring(response: 0.25, dampingFraction: 0.7), value: position)
    }
    
    private func tryConfirmColor() {
        let rel = gazeManager.cursorRelativePosition
        let inside = isCursorInsideWheel(rel, wheelRadius: wheelRadiusRelative)
        guard inside, !hasTriggeredSelection else {
            if !inside {
                gazeManager.didPerformDeepBlink = false
                gazeManager.didPerformMouthOpenTwice = false
            }
            return
        }
        hasTriggeredSelection = true
        let colorToSet = colorFromCursor(relative: rel, wheelRadius: wheelRadiusRelative)
        selectedColor = colorToSet
        gazeManager.didPerformDeepBlink = false
        gazeManager.didPerformMouthOpenTwice = false
        
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        withAnimation(.easeInOut(duration: 0.25)) { soulPulsateScale = 1.25 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            withAnimation(.easeInOut(duration: 0.3)) { soulPulsateScale = 1.0 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            onComplete()
        }
    }
}

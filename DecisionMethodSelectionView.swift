//
//  DecisionMethodSelectionView.swift
//  EyEmote
//
//  Choose confirmation (Decision) method: Blink 3s, Open Mouth Twice, or Gaze 3s.
//

import SwiftUI
import AVKit

// MARK: - Decision Method Card Data

private struct DecisionCard: Identifiable {
    let id: DecisionMethod
    let videoAssetName: String
    let label: String
    static let all: [DecisionCard] = [
        DecisionCard(id: .deepBlink, videoAssetName: "VideoBlink", label: "Blink for 3 seconds"),
        DecisionCard(id: .mouthOpenTwice, videoAssetName: "VideoMouth", label: "Open Mouth Twice"),
        DecisionCard(id: .dwell, videoAssetName: "VideoDwell", label: "Gaze for 3 seconds")
    ]
}

// MARK: - Video Player (Placeholder-safe)

struct DecisionVideoPlayerView: View {
    let assetName: String
    
    private var videoURL: URL? {
        Bundle.main.url(forResource: assetName, withExtension: "mp4")
    }
    
    var body: some View {
        ZStack {
            VideoPlayerContainer(assetName: assetName, hasAsset: videoURL != nil)
                .aspectRatio(16/10, contentMode: .fit)
                .clipped()
                .cornerRadius(12)
            if videoURL == nil {
                Text("Video")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
            }
        }
    }
}

private struct VideoPlayerContainer: UIViewRepresentable {
    let assetName: String
    var hasAsset: Bool
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        view.layer.cornerRadius = 12
        view.clipsToBounds = true
        
        guard hasAsset, let url = Bundle.main.url(forResource: assetName, withExtension: "mp4") else {
            return view
        }
        let player = AVPlayer(url: url)
        player.isMuted = true
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspect
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        context.coordinator.player = player
        context.coordinator.layer = layer
        player.play()
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.layer?.frame = uiView.bounds
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        var player: AVPlayer?
        var layer: AVPlayerLayer?
    }
}

// MARK: - Decision Method Selection View

struct DecisionMethodSelectionView: View {
    @ObservedObject var gazeManager: GazeManager
    var onComplete: () -> Void
    
    private let dwellSelectionThreshold: TimeInterval = 3.0
    
    var body: some View {
        GeometryReader { geometry in
            let isHorizontal = geometry.size.width > geometry.size.height
            let rel = gazeManager.cursorRelativePosition
            
            ZStack {
                backgroundGradient
                
                VStack(spacing: 0) {
                    titleSection
                    Spacer(minLength: 24)
                    cardsContent(isHorizontal: isHorizontal, cursorRelative: rel)
                    Spacer(minLength: 24)
                }
            }
            .onAppear {
                gazeManager.isInDecisionSelectionPhase = true
                gazeManager.mouthOpenCount = 0
            }
            .onDisappear {
                gazeManager.isInDecisionSelectionPhase = false
            }
            .onChange(of: gazeManager.didPerformDeepBlink) { newValue in
                if newValue { trySelect(method: .deepBlink, isHorizontal: geometry.size.width > geometry.size.height) }
            }
            .onChange(of: gazeManager.didPerformMouthOpenTwice) { newValue in
                if newValue { trySelect(method: .mouthOpenTwice, isHorizontal: geometry.size.width > geometry.size.height) }
            }
        }
        .ignoresSafeArea()
    }
    
    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(white: 0.22),
                Color(white: 0.12)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    private var titleSection: some View {
        Text("Choose how to confirm")
            .font(.title2)
            .fontWeight(.semibold)
            .foregroundColor(.white.opacity(0.95))
            .padding(.top, 50)
    }
    
    private func cardsContent(isHorizontal: Bool, cursorRelative: CGPoint) -> some View {
        Group {
            if isHorizontal {
                HStack(spacing: 20) {
                    ForEach(DecisionCard.all) { card in
                        cardView(
                            card: card,
                            isHighlighted: cardUnderCursor(relative: cursorRelative, isHorizontal: true) == card.id,
                            dwellProgress: card.id == .dwell && cardUnderCursor(relative: cursorRelative, isHorizontal: true) == .dwell ? min(1.0, gazeManager.dwellTime / dwellSelectionThreshold) : nil,
                            mouthOpenCount: card.id == .mouthOpenTwice ? gazeManager.mouthOpenCount : nil
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .padding(.horizontal, 24)
            } else {
                VStack(spacing: 20) {
                    ForEach(DecisionCard.all) { card in
                        cardView(
                            card: card,
                            isHighlighted: cardUnderCursor(relative: cursorRelative, isHorizontal: false) == card.id,
                            dwellProgress: card.id == .dwell && cardUnderCursor(relative: cursorRelative, isHorizontal: false) == .dwell ? min(1.0, gazeManager.dwellTime / dwellSelectionThreshold) : nil,
                            mouthOpenCount: card.id == .mouthOpenTwice ? gazeManager.mouthOpenCount : nil
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .padding(.horizontal, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: gazeManager.dwellTime) { _ in
            checkDwellSelection(isHorizontal: isHorizontal)
        }
    }
    
    private func cardView(card: DecisionCard, isHighlighted: Bool, dwellProgress: Double?, mouthOpenCount: Int?) -> some View {
        let neonColor = Color(red: 0.4, green: 1.0, blue: 0.6)
        return VStack(spacing: 12) {
            ZStack {
                DecisionVideoPlayerView(assetName: card.videoAssetName)
                if card.id == .dwell, let progress = dwellProgress, progress > 0 {
                    dwellProgressRing(progress: progress, neonColor: neonColor)
                }
                if card.id == .mouthOpenTwice, let count = mouthOpenCount {
                    mouthCounterView(count: count, neonColor: neonColor)
                }
            }
            Text(card.label)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.white.opacity(0.9))
                .multilineTextAlignment(.center)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(isHighlighted ? neonColor : Color.white.opacity(0.15), lineWidth: isHighlighted ? 3 : 1)
                )
                .shadow(color: isHighlighted ? neonColor.opacity(0.7) : .clear, radius: isHighlighted ? 16 : 0)
                .shadow(color: isHighlighted ? neonColor.opacity(0.4) : .clear, radius: isHighlighted ? 24 : 0)
        )
        .animation(.easeOut(duration: 0.2), value: isHighlighted)
        .animation(.easeInOut(duration: 0.15), value: dwellProgress ?? 0)
        .animation(.easeInOut(duration: 0.2), value: mouthOpenCount ?? 0)
    }
    
    private func dwellProgressRing(progress: Double, neonColor: Color) -> some View {
        Circle()
            .stroke(Color.white.opacity(0.2), lineWidth: 5)
            .frame(width: 56, height: 56)
            .overlay(
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(neonColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 56, height: 56)
                    .shadow(color: neonColor.opacity(0.9), radius: 8)
                    .shadow(color: neonColor.opacity(0.5), radius: 14)
            )
    }
    
    private func mouthCounterView(count: Int, neonColor: Color) -> some View {
        HStack(spacing: 8) {
            ForEach(0..<2, id: \.self) { index in
                Circle()
                    .fill(index < count ? neonColor : Color.white.opacity(0.25))
                    .frame(width: 10, height: 10)
                    .overlay(
                        Circle()
                            .strokeBorder(index < count ? neonColor : Color.white.opacity(0.4), lineWidth: 1)
                    )
                    .shadow(color: index < count ? neonColor.opacity(0.8) : .clear, radius: 4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.black.opacity(0.35)))
    }
    
    private func cardUnderCursor(relative: CGPoint, isHorizontal: Bool) -> DecisionMethod? {
        let x = relative.x
        let y = relative.y
        if isHorizontal {
            if x < 1/3 { return .deepBlink }
            if x < 2/3 { return .mouthOpenTwice }
            return .dwell
        } else {
            if y < 1/3 { return .deepBlink }
            if y < 2/3 { return .mouthOpenTwice }
            return .dwell
        }
    }
    
    private func trySelect(method: DecisionMethod, isHorizontal: Bool) {
        let rel = gazeManager.cursorRelativePosition
        guard cardUnderCursor(relative: rel, isHorizontal: isHorizontal) == method else { return }
        gazeManager.selectedDecisionMethod = method
        if method == .deepBlink { gazeManager.didPerformDeepBlink = false }
        if method == .mouthOpenTwice { gazeManager.didPerformMouthOpenTwice = false }
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        onComplete()
    }
    
    private func checkDwellSelection(isHorizontal: Bool) {
        guard gazeManager.dwellTime >= dwellSelectionThreshold else { return }
        let rel = gazeManager.cursorRelativePosition
        guard cardUnderCursor(relative: rel, isHorizontal: isHorizontal) == .dwell else { return }
        gazeManager.selectedDecisionMethod = .dwell
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        onComplete()
    }
}

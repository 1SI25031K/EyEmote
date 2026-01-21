//
//  SwiftUIView.swift
//  EyEmote
//
//  Created by Kosei Miyamoto on 2026/01/20.
//

import SwiftUI
import AVFoundation

struct CalibrationView: View {
    @ObservedObject var gazeManager: GazeManager
    var onComplete: () -> Void
    
    // 12点キャリブレーション (Step定義は変更なし)
    enum Step {
        case ready, center, topCenter, topRight, midRight, bottomRight, bottomCenter, bottomLeft, midLeft, topLeft, innerBottomRight, innerTopLeft, centerFinal, finished
    }
    
    @State private var currentStep: Step = .ready
    @State private var progress: CGFloat = 0.0
    @State private var centerRaw: CGPoint = .zero
    @State private var showInstructionText: Bool = false
    
    private let synthesizer = AVSpeechSynthesizer()
    
    // タイミング調整
    private let moveDuration: Double = 0.5
    private let prepareDuration: Double = 0.5
    private let recordingDuration: Double = 1.5
    
    // カラー設定: ネオンライム (発光感アップ)
    private let themeColor = Color(red: 0.8, green: 1.0, blue: 0.2)
    
    var body: some View {
        ZStack {
            // 背景: 完全な黒 (Liquid Glassを目立たせるため)
            Color.black.ignoresSafeArea()
            
            // ★ Liquid Glass Instruction Text
            if showInstructionText {
                VStack {
                    Spacer()
                    Text("The viewpoint setup will begin shortly. Please follow the position of the dot inside the ring with your eyes.")
                        .font(.body)
                        .fontWeight(.medium)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.white)
                        .padding(.vertical, 16)
                        .padding(.horizontal, 24)
                        // ここがLiquid Glassの魔法
                        .background(.ultraThinMaterial) // 磨りガラス
                        .background(Color.white.opacity(0.1)) // 微かな白
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(LinearGradient(colors: [.white.opacity(0.6), .white.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.5), radius: 10, x: 0, y: 5)
                        .padding(.bottom, 50)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
                .zIndex(10)
            }
            
            if currentStep == .finished {
                finishedScreen
            }
            
            if isCalibrating() {
                // 新しいLiquid Glassターゲット
                LiquidCalibrationTarget(progress: progress, color: themeColor)
                    .position(targetPosition())
                    .animation(.easeInOut(duration: moveDuration), value: currentStep)
            }
        }
        .onAppear {
            startSequenceWithVoice()
        }
    }
    
    private func startSequenceWithVoice() {
        withAnimation(.easeOut(duration: 0.5)) { showInstructionText = true }
        
        let text = "The viewpoint setup will begin shortly. Please follow the position of the dot inside the ring with your eyes."
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.5
        synthesizer.speak(utterance)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) {
            withAnimation(.easeIn(duration: 0.5)) { showInstructionText = false }
            moveToNextStep(.center)
        }
    }
    
    var finishedScreen: some View {
        VStack {
            ZStack {
                // 完了時の演出もLiquidに
                Circle()
                    .fill(themeColor)
                    .frame(width: 80, height: 80)
                    .shadow(color: themeColor.opacity(0.6), radius: 20) // グロー
                    .scaleEffect(progress)
                
                Image(systemName: "checkmark")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(.black.opacity(0.8))
                    .scaleEffect(progress)
            }
            .position(x: UIScreen.main.bounds.width * 0.5, y: UIScreen.main.bounds.height * 0.5)
            
            Text("Setup Complete")
                .font(.title).bold().foregroundColor(.white)
                .padding(.top, 100)
                .shadow(color: .white.opacity(0.5), radius: 10)
        }
        .onAppear {
            AudioServicesPlaySystemSound(1022)
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { progress = 1.0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { onComplete() }
        }
    }
    
    // --- ロジック ---
    private func isCalibrating() -> Bool { return currentStep != .ready && currentStep != .finished }
    
    private func targetPosition() -> CGPoint {
        let w = UIScreen.main.bounds.width
        let h = UIScreen.main.bounds.height
        let inset: CGFloat = 0.1
        let inner: CGFloat = 0.35
        
        switch currentStep {
        case .center: return CGPoint(x: w*0.5, y: h*0.5)
        case .topCenter: return CGPoint(x: w*0.5, y: h*inset)
        case .topRight: return CGPoint(x: w*(1-inset), y: h*inset)
        case .midRight: return CGPoint(x: w*(1-inset), y: h*0.5)
        case .bottomRight: return CGPoint(x: w*(1-inset), y: h*(1-inset))
        case .bottomCenter: return CGPoint(x: w*0.5, y: h*(1-inset))
        case .bottomLeft: return CGPoint(x: w*inset, y: h*(1-inset))
        case .midLeft: return CGPoint(x: w*inset, y: h*0.5)
        case .topLeft: return CGPoint(x: w*inset, y: h*inset)
        case .innerBottomRight: return CGPoint(x: w*(1-inner), y: h*(1-inner))
        case .innerTopLeft: return CGPoint(x: w*inner, y: h*inner)
        case .centerFinal: return CGPoint(x: w*0.5, y: h*0.5)
        default: return CGPoint(x: w*0.5, y: h*0.5)
        }
    }
    
    private func moveToNextStep(_ nextStep: Step) {
        withAnimation(.easeInOut(duration: moveDuration)) { currentStep = nextStep }
        DispatchQueue.main.asyncAfter(deadline: .now() + moveDuration + prepareDuration) { startCalibrationPhase() }
    }
    
    private func startCalibrationPhase() {
        progress = 0.0
        withAnimation(.linear(duration: recordingDuration)) { progress = 1.0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + recordingDuration) {
            AudioServicesPlaySystemSound(1057) // Tock (Loud)
            recordData()
            determineNextStep()
        }
    }
    
    private func recordData() {
        let inset: CGFloat = 0.1
        let inner: CGFloat = 0.35
        switch currentStep {
        case .center: gazeManager.calibrateCenter(); self.centerRaw = gazeManager.getCurrentRaw()
        case .topCenter: gazeManager.calibrateSensitivity(lookingAt: CGPoint(x: 0.5, y: inset), centerRaw: centerRaw)
        case .topRight: gazeManager.calibrateSensitivity(lookingAt: CGPoint(x: 1-inset, y: inset), centerRaw: centerRaw)
        case .midRight: gazeManager.calibrateSensitivity(lookingAt: CGPoint(x: 1-inset, y: 0.5), centerRaw: centerRaw)
        case .bottomRight: gazeManager.calibrateSensitivity(lookingAt: CGPoint(x: 1-inset, y: 1-inset), centerRaw: centerRaw)
        case .bottomCenter: gazeManager.calibrateSensitivity(lookingAt: CGPoint(x: 0.5, y: 1-inset), centerRaw: centerRaw)
        case .bottomLeft: gazeManager.calibrateSensitivity(lookingAt: CGPoint(x: inset, y: 1-inset), centerRaw: centerRaw)
        case .midLeft: gazeManager.calibrateSensitivity(lookingAt: CGPoint(x: inset, y: 0.5), centerRaw: centerRaw)
        case .topLeft: gazeManager.calibrateSensitivity(lookingAt: CGPoint(x: inset, y: inset), centerRaw: centerRaw)
        case .innerBottomRight: gazeManager.calibrateSensitivity(lookingAt: CGPoint(x: 1-inner, y: 1-inner), centerRaw: centerRaw)
        case .innerTopLeft: gazeManager.calibrateSensitivity(lookingAt: CGPoint(x: inner, y: inner), centerRaw: centerRaw)
        case .centerFinal: gazeManager.calibrateCenter()
        default: break
        }
    }
    
    private func determineNextStep() {
        var next: Step = .finished
        switch currentStep {
        case .ready: next = .center
        case .center: next = .topCenter
        case .topCenter: next = .topRight
        case .topRight: next = .midRight
        case .midRight: next = .bottomRight
        case .bottomRight: next = .bottomCenter
        case .bottomCenter: next = .bottomLeft
        case .bottomLeft: next = .midLeft
        case .midLeft: next = .topLeft
        case .topLeft: next = .innerBottomRight
        case .innerBottomRight: next = .innerTopLeft
        case .innerTopLeft: next = .centerFinal
        case .centerFinal: next = .finished
        case .finished: break
        }
        if next == .finished { currentStep = .finished } else { moveToNextStep(next) }
    }
}

// ★ 新しい Liquid Glass Design のターゲット
struct LiquidCalibrationTarget: View {
    var progress: CGFloat
    var color: Color
    
    var body: some View {
        ZStack {
            // 1. フロストガラスの軌道 (Frosted Track)
            // 単なる白線ではなく、半透明のガラスリングにする
            Circle()
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 6) // ベース
                .background(
                    Circle()
                        .stroke(Color.white.opacity(0.1), lineWidth: 8)
                        .blur(radius: 2) // 光の滲み
                )
                .frame(width: 60, height: 60)
            
            // 2. 白いハイライト (Glass Edge)
            // ガラスの縁に光が当たっている表現
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.8), .clear, .white.opacity(0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
                .frame(width: 64, height: 64)
            
            // 3. 進行リング (Neon Liquid)
            // ネオン管のように強く発光させる
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 60, height: 60)
                .shadow(color: color, radius: 10) // 強いグロー
                .shadow(color: color.opacity(0.5), radius: 20) // 広がる光
            
            // 4. 中心点 (Glass Bead)
            // 平面的な白丸ではなく、球体のようなガラスビーズ
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [.white, .white.opacity(0.8), .gray.opacity(0.3)]),
                        center: .topLeading,
                        startRadius: 1,
                        endRadius: 10
                    )
                )
                .frame(width: 12, height: 12)
                .shadow(color: .black.opacity(0.3), radius: 2, x: 1, y: 1)
        }
    }
}

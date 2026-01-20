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
    
    // 12点キャリブレーション
    enum Step {
        case ready
        case center
        case topCenter, topRight
        case midRight, bottomRight
        case bottomCenter, bottomLeft
        case midLeft, topLeft
        case innerBottomRight, innerTopLeft
        case centerFinal
        case finished
    }
    
    @State private var currentStep: Step = .ready
    @State private var progress: CGFloat = 0.0
    @State private var centerRaw: CGPoint = .zero
    
    // ★追加: ガイダンス字幕の表示フラグ
    @State private var showInstructionText: Bool = false
    
    private let synthesizer = AVSpeechSynthesizer()
    
    // タイミング調整
    private let moveDuration: Double = 0.5
    private let prepareDuration: Double = 0.5
    private let recordingDuration: Double = 1.5
    
    // カラー設定: ライムグリーン
    private let themeColor = Color(red: 0.75, green: 1.0, blue: 0.0)
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // ★追加: 音声ガイダンスの字幕
            if showInstructionText {
                VStack {
                    Spacer()
                    Text("The viewpoint setup will begin shortly.\nWhen the ring appears, follow its position with your eyes.")
                        .font(.title3)
                        .fontWeight(.medium)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.white)
                        .padding(20)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(12)
                        .transition(.opacity)
                    Spacer()
                }
                .zIndex(10) // リングより手前に表示
            }
            
            if currentStep == .finished {
                finishedScreen
            }
            
            if isCalibrating() {
                CalibrationTarget(progress: progress, color: themeColor)
                    .position(targetPosition())
                    .animation(.easeInOut(duration: moveDuration), value: currentStep)
            }
        }
        .onAppear {
            startSequenceWithVoice()
        }
    }
    
    private func startSequenceWithVoice() {
        // 1. 字幕を表示
        withAnimation { showInstructionText = true }
        
        // 2. 音声読み上げ
        let text = "The viewpoint setup will begin shortly. When the ring appears, follow its position with your eyes."
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.5
        synthesizer.speak(utterance)
        
        // 3. 読み上げ終了想定時間(6秒)後に字幕を消してリング開始
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) {
            withAnimation { showInstructionText = false } // 字幕オフ
            moveToNextStep(.center)
        }
    }
    
    var finishedScreen: some View {
        VStack {
            ZStack {
                Circle()
                    .fill(themeColor)
                    .frame(width: 80, height: 80)
                    .scaleEffect(progress)
                
                Image(systemName: "checkmark")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(.black)
                    .scaleEffect(progress)
            }
            .shadow(color: themeColor.opacity(0.6), radius: 20)
            .position(x: UIScreen.main.bounds.width * 0.5, y: UIScreen.main.bounds.height * 0.5)
            
            Text("Setup Complete")
                .font(.title).bold().foregroundColor(.white)
                .padding(.top, 100)
        }
        .onAppear {
            // 完了音 (Chime)
            AudioServicesPlaySystemSound(1022)
            
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                progress = 1.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { onComplete() }
        }
    }
    
    // --- ロジック ---
    
    private func isCalibrating() -> Bool {
        return currentStep != .ready && currentStep != .finished
    }
    
    private func targetPosition() -> CGPoint {
        let w = UIScreen.main.bounds.width
        let h = UIScreen.main.bounds.height
        let inset: CGFloat = 0.1
        let inner: CGFloat = 0.35
        
        switch currentStep {
        case .center:       return CGPoint(x: w * 0.5, y: h * 0.5)
        case .topCenter:    return CGPoint(x: w * 0.5, y: h * inset)
        case .topRight:     return CGPoint(x: w * (1-inset), y: h * inset)
        case .midRight:     return CGPoint(x: w * (1-inset), y: h * 0.5)
        case .bottomRight:  return CGPoint(x: w * (1-inset), y: h * (1-inset))
        case .bottomCenter: return CGPoint(x: w * 0.5, y: h * (1-inset))
        case .bottomLeft:   return CGPoint(x: w * inset, y: h * (1-inset))
        case .midLeft:      return CGPoint(x: w * inset, y: h * 0.5)
        case .topLeft:      return CGPoint(x: w * inset, y: h * inset)
        case .innerBottomRight: return CGPoint(x: w * (1-inner), y: h * (1-inner))
        case .innerTopLeft:     return CGPoint(x: w * inner, y: h * inner)
        case .centerFinal:  return CGPoint(x: w * 0.5, y: h * 0.5)
        default:            return CGPoint(x: w * 0.5, y: h * 0.5)
        }
    }
    
    private func moveToNextStep(_ nextStep: Step) {
        withAnimation(.easeInOut(duration: moveDuration)) {
            currentStep = nextStep
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + moveDuration + prepareDuration) {
            startCalibrationPhase()
        }
    }
    
    private func startCalibrationPhase() {
        progress = 0.0
        withAnimation(.linear(duration: recordingDuration)) {
            progress = 1.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + recordingDuration) {
            // ★修正: 音をもっと大きく (1057: Tink/Pin)
            AudioServicesPlaySystemSound(1057)
            
            recordData()
            determineNextStep()
        }
    }
    
    private func recordData() {
        let inset: CGFloat = 0.1
        let inner: CGFloat = 0.35
        
        switch currentStep {
        case .center:
            gazeManager.calibrateCenter()
            self.centerRaw = gazeManager.getCurrentRaw()
            
        case .topCenter:    gazeManager.calibrateSensitivity(lookingAt: CGPoint(x: 0.5, y: inset), centerRaw: centerRaw)
        case .topRight:     gazeManager.calibrateSensitivity(lookingAt: CGPoint(x: 1-inset, y: inset), centerRaw: centerRaw)
        case .midRight:     gazeManager.calibrateSensitivity(lookingAt: CGPoint(x: 1-inset, y: 0.5), centerRaw: centerRaw)
        case .bottomRight:  gazeManager.calibrateSensitivity(lookingAt: CGPoint(x: 1-inset, y: 1-inset), centerRaw: centerRaw)
        case .bottomCenter: gazeManager.calibrateSensitivity(lookingAt: CGPoint(x: 0.5, y: 1-inset), centerRaw: centerRaw)
        case .bottomLeft:   gazeManager.calibrateSensitivity(lookingAt: CGPoint(x: inset, y: 1-inset), centerRaw: centerRaw)
        case .midLeft:      gazeManager.calibrateSensitivity(lookingAt: CGPoint(x: inset, y: 0.5), centerRaw: centerRaw)
        case .topLeft:      gazeManager.calibrateSensitivity(lookingAt: CGPoint(x: inset, y: inset), centerRaw: centerRaw)
        case .innerBottomRight: gazeManager.calibrateSensitivity(lookingAt: CGPoint(x: 1-inner, y: 1-inner), centerRaw: centerRaw)
        case .innerTopLeft:     gazeManager.calibrateSensitivity(lookingAt: CGPoint(x: inner, y: inner), centerRaw: centerRaw)
        case .centerFinal:  gazeManager.calibrateCenter()
        default: break
        }
    }
    
    private func determineNextStep() {
        var next: Step = .finished
        switch currentStep {
        case .ready:        next = .center
        case .center:       next = .topCenter
        case .topCenter:    next = .topRight
        case .topRight:     next = .midRight
        case .midRight:     next = .bottomRight
        case .bottomRight:  next = .bottomCenter
        case .bottomCenter: next = .bottomLeft
        case .bottomLeft:   next = .midLeft
        case .midLeft:      next = .topLeft
        case .topLeft:      next = .innerBottomRight
        case .innerBottomRight: next = .innerTopLeft
        case .innerTopLeft: next = .centerFinal
        case .centerFinal:  next = .finished
        case .finished: break
        }
        
        if next == .finished {
            currentStep = .finished
        } else {
            moveToNextStep(next)
        }
    }
}

// ターゲットView
struct CalibrationTarget: View {
    var progress: CGFloat
    var color: Color
    
    var body: some View {
        ZStack {
            // ★修正: 灰色の部分を「白 (不透明)」に変更
            Circle()
                .stroke(Color.white, lineWidth: 4) // opacity(0.3)を削除
                .frame(width: 60, height: 60)
            
            // 進行リング (ライムグリーン)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 60, height: 60)
                .shadow(color: color.opacity(0.8), radius: 8)
            
            // 中心点
            Circle()
                .fill(Color.white)
                .frame(width: 8, height: 8)
        }
    }
}

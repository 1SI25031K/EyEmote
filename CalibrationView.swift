//
//  SwiftUIView.swift
//  EyEmote
//
//  Created by Kosei Miyamoto on 2026/01/20.
//

import SwiftUI

struct CalibrationView: View {
    @ObservedObject var gazeManager: GazeManager
    var onComplete: () -> Void
    
    // 8点キャリブレーション
    enum Step {
        case ready
        case center
        case topLeft
        case topRight
        case midLeft
        case midRight
        case bottomRight
        case bottomLeft
        case centerFinal
        case finished
    }
    
    @State private var currentStep: Step = .ready
    @State private var progress: CGFloat = 0.0
    @State private var centerRaw: CGPoint = .zero
    
    // ★タイミング調整用の定数
    // 移動にかける時間
    private let moveDuration: Double = 0.8
    // 移動してから計測開始までの「タメ」（目が追いつく時間）
    private let prepareDuration: Double = 0.2
    // 計測（リングが溜まる）時間 ← これを長くして余裕を持たせる
    private let recordingDuration: Double = 2.0
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.8).ignoresSafeArea()
            
            if currentStep == .finished {
                finishedScreen
            }
            
            // ターゲット表示
            if isCalibrating() {
                CalibrationTarget(progress: progress)
                    .position(targetPosition())
                    // 移動アニメーション (moveDurationと合わせる)
                    .animation(.easeInOut(duration: moveDuration), value: currentStep)
            }
        }
        .onAppear {
            startSequence()
        }
    }
    
    private func startSequence() {
        // 最初の表示までの少しの間
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            moveToNextStep(.center)
        }
    }
    
    var finishedScreen: some View {
        VStack {
            ZStack {
                Circle()
                    .fill(Color.green)
                    .frame(width: 80, height: 80)
                    .scaleEffect(progress)
                
                Image(systemName: "checkmark")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(.white)
                    .scaleEffect(progress)
            }
            .shadow(color: .green.opacity(0.5), radius: 20)
            .position(x: UIScreen.main.bounds.width * 0.5, y: UIScreen.main.bounds.height * 0.5)
            
            Text("準備完了")
                .font(.title).bold().foregroundColor(.white)
                .padding(.top, 100)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                progress = 1.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { onComplete() }
        }
    }
    
    // --- ロジック ---
    
    private func isCalibrating() -> Bool {
        return currentStep != .ready && currentStep != .finished
    }
    
    private func targetPosition() -> CGPoint {
        let w = UIScreen.main.bounds.width
        let h = UIScreen.main.bounds.height
        let inset: CGFloat = 0.15
        
        switch currentStep {
        case .center: return CGPoint(x: w * 0.5, y: h * 0.5)
        case .topLeft: return CGPoint(x: w * inset, y: h * inset)
        case .topRight: return CGPoint(x: w * (1 - inset), y: h * inset)
        case .midLeft: return CGPoint(x: w * inset, y: h * 0.5)
        case .midRight: return CGPoint(x: w * (1 - inset), y: h * 0.5)
        case .bottomRight: return CGPoint(x: w * (1 - inset), y: h * (1 - inset))
        case .bottomLeft: return CGPoint(x: w * inset, y: h * (1 - inset))
        case .centerFinal: return CGPoint(x: w * 0.5, y: h * 0.5)
        default: return CGPoint(x: w * 0.5, y: h * 0.5)
        }
    }
    
    // ★キモとなる処理：移動と計測を分ける
    private func moveToNextStep(_ nextStep: Step) {
        // 1. まずターゲットを移動させる
        withAnimation(.easeInOut(duration: moveDuration)) {
            currentStep = nextStep
        }
        
        // 2. 移動アニメーションが終わり、かつ一呼吸置いてから計測開始
        DispatchQueue.main.asyncAfter(deadline: .now() + moveDuration + prepareDuration) {
            startCalibrationPhase()
        }
    }
    
    private func startCalibrationPhase() {
        // プログレスを0にしてからアニメーション開始
        progress = 0.0
        
        // 3. ゆっくりリングを満たす
        withAnimation(.linear(duration: recordingDuration)) {
            progress = 1.0
        }
        
        // 4. リングが満ちたらデータを記録して次へ
        DispatchQueue.main.asyncAfter(deadline: .now() + recordingDuration) {
            recordData()
            determineNextStep()
        }
    }
    
    private func recordData() {
        let inset: CGFloat = 0.15
        switch currentStep {
        case .center:
            gazeManager.calibrateCenter()
            self.centerRaw = gazeManager.getCurrentRaw()
        case .topLeft:
            gazeManager.calibrateSensitivity(lookingAt: CGPoint(x: inset, y: inset), centerRaw: centerRaw)
        case .topRight:
            gazeManager.calibrateSensitivity(lookingAt: CGPoint(x: 1-inset, y: inset), centerRaw: centerRaw)
        case .midLeft:
            gazeManager.calibrateSensitivity(lookingAt: CGPoint(x: inset, y: 0.5), centerRaw: centerRaw)
        case .midRight:
            gazeManager.calibrateSensitivity(lookingAt: CGPoint(x: 1-inset, y: 0.5), centerRaw: centerRaw)
        case .bottomRight:
            gazeManager.calibrateSensitivity(lookingAt: CGPoint(x: 1-inset, y: 1-inset), centerRaw: centerRaw)
        case .bottomLeft:
            gazeManager.calibrateSensitivity(lookingAt: CGPoint(x: inset, y: 1-inset), centerRaw: centerRaw)
        case .centerFinal:
            gazeManager.calibrateCenter()
        default: break
        }
    }
    
    private func determineNextStep() {
        // 次のステップを決めて移動開始関数を呼ぶ
        var next: Step = .finished
        
        switch currentStep {
        case .ready: next = .center
        case .center: next = .topLeft
        case .topLeft: next = .topRight
        case .topRight: next = .midLeft
        case .midLeft: next = .midRight
        case .midRight: next = .bottomRight
        case .bottomRight: next = .bottomLeft
        case .bottomLeft: next = .centerFinal
        case .centerFinal: next = .finished
        case .finished: break
        }
        
        if next == .finished {
            // 完了時はアニメーションなしですぐ遷移
            currentStep = .finished
        } else {
            // 通常時は移動フローへ
            moveToNextStep(next)
        }
    }
}

struct CalibrationTarget: View {
    var progress: CGFloat
    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.3), lineWidth: 4).frame(width: 60, height: 60)
            Circle().trim(from: 0, to: progress)
                .stroke(Color.blue, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 60, height: 60)
            Circle().fill(Color.white).frame(width: 10, height: 10)
        }
    }
}

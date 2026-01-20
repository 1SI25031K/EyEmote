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
    
    // ★ 7点キャリブレーションに変更
    enum Step {
        case start
        case center
        case topLeft
        case topRight
        case midLeft  // 追加
        case midRight // 追加
        case bottomRight
        case bottomLeft
        case finished
    }
    
    @State private var currentStep: Step = .start
    @State private var progress: CGFloat = 0.0
    @State private var centerRaw: CGPoint = .zero
    @State private var countdown: Int = 10
    @State private var timer: Timer?
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.95).ignoresSafeArea()
            
            VStack {
                if currentStep == .start {
                    startScreen
                } else if currentStep == .finished {
                    finishedScreen
                }
            }
            
            if isCalibrating() {
                CalibrationTarget(progress: progress)
                    .position(targetPosition())
                    .onAppear { startCalibrationPhase() }
                    .animation(Animation.easeInOut(duration: 0.6), value: currentStep)
            }
        }
    }
    
    // UI部品を切り出して見やすくしました
    var startScreen: some View {
        VStack(spacing: 30) {
            Image(systemName: "eye.fill")
                .font(.system(size: 70))
                .foregroundColor(.blue)
            
            Text("視線入力の調整")
                .font(.largeTitle).bold()
                .foregroundColor(.white)
            
            VStack(spacing: 15) {
                Text("7つのポイントを見つめて精度を高めます。\n位置がズレた場合は、口を大きく開けると\nいつでも補正できます。")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.gray)
                
                HStack {
                    Image(systemName: "mouth")
                    Text("口を開けてリセット機能搭載")
                }
                .font(.caption)
                .padding()
                .background(Color.orange.opacity(0.2))
                .cornerRadius(8)
                .foregroundColor(.orange)
            }
            .padding()
            
            Button(action: { startCalibration() }) {
                Text("今すぐ開始")
                    .font(.title3.bold())
                    .padding(.horizontal, 40)
                    .padding(.vertical, 16)
                    .background(Color.blue)
                    .cornerRadius(30)
                    .foregroundColor(.white)
            }
            
            Text("\(countdown)秒後に開始...")
                .foregroundColor(.gray)
                .onAppear { startCountdown() }
        }
    }
    
    var finishedScreen: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)
            Text("完了")
                .font(.title).bold().foregroundColor(.white)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { onComplete() }
        }
    }
    
    // ロジック部分
    private func startCountdown() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if countdown > 1 { countdown -= 1 } else { startCalibration() }
        }
    }
    
    private func startCalibration() {
        timer?.invalidate()
        withAnimation { currentStep = .center }
    }
    
    private func isCalibrating() -> Bool {
        return currentStep != .start && currentStep != .finished
    }
    
    // ★ 7点の座標定義
    private func targetPosition() -> CGPoint {
        let w = UIScreen.main.bounds.width
        let h = UIScreen.main.bounds.height
        let inset: CGFloat = 0.15
        
        switch currentStep {
        case .center: return CGPoint(x: w * 0.5, y: h * 0.5)
        case .topLeft: return CGPoint(x: w * inset, y: h * inset)
        case .topRight: return CGPoint(x: w * (1 - inset), y: h * inset)
        case .midLeft: return CGPoint(x: w * inset, y: h * 0.5)      // 追加
        case .midRight: return CGPoint(x: w * (1 - inset), y: h * 0.5) // 追加
        case .bottomRight: return CGPoint(x: w * (1 - inset), y: h * (1 - inset))
        case .bottomLeft: return CGPoint(x: w * inset, y: h * (1 - inset))
        default: return CGPoint(x: w * 0.5, y: h * 0.5)
        }
    }
    
    private func startCalibrationPhase() {
        progress = 0.0
        withAnimation(.linear(duration: 1.5)) { progress = 1.0 } // 少しテンポアップ(1.5秒)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            recordData()
            advanceStep()
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
        default: break
        }
    }
    
    private func advanceStep() {
        withAnimation {
            switch currentStep {
            case .center: currentStep = .topLeft
            case .topLeft: currentStep = .topRight
            case .topRight: currentStep = .midLeft
            case .midLeft: currentStep = .midRight
            case .midRight: currentStep = .bottomRight
            case .bottomRight: currentStep = .bottomLeft
            case .bottomLeft: currentStep = .finished
            default: break
            }
        }
        if isCalibrating() { startCalibrationPhase() }
    }
}

// ターゲット表示用 (以前と同じですが念の為)
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

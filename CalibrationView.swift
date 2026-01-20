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
    
    // ★ 8点キャリブレーション
    enum Step {
        case ready        // 準備（Splashからの遷移直後）
        case center
        case topLeft
        case topRight
        case midLeft
        case midRight
        case bottomRight
        case bottomLeft
        case centerFinal  // ★8点目：最後の中央
        case finished     // 完了画面
    }
    
    @State private var currentStep: Step = .ready
    @State private var progress: CGFloat = 0.0
    @State private var centerRaw: CGPoint = .zero
    
    var body: some View {
        ZStack {
            // 背景は少し透過させて、裏でカメラが動いていることを示唆しても良いが、
            // 集中させるために黒背景のままにします
            Color.black.opacity(0.8).ignoresSafeArea()
            
            // 完了画面
            if currentStep == .finished {
                finishedScreen
            }
            
            // ターゲット表示
            // .readyの時は表示せず、.centerになった瞬間に表示開始
            if isCalibrating() {
                CalibrationTarget(progress: progress)
                    .position(targetPosition())
                    // 位置移動のアニメーション
                    .animation(.easeInOut(duration: 0.6), value: currentStep)
            }
        }
        .onAppear {
            // 画面が表示されたらすぐに計測シーケンスを開始
            startSequence()
        }
    }
    
    // シーケンス開始：少しだけ待ってからCenterへ
    private func startSequence() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation { currentStep = .center }
            startCalibrationPhase()
        }
    }
    
    // 完了画面
    var finishedScreen: some View {
        VStack {
            ZStack {
                // ターゲットと同じサイズ・位置から出現させる演出
                Circle()
                    .fill(Color.green)
                    .frame(width: 80, height: 80)
                    .scaleEffect(progress) // ポップアップ
                
                Image(systemName: "checkmark")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(.white)
                    .scaleEffect(progress)
            }
            .shadow(color: .green.opacity(0.5), radius: 20)
            // 画面中央（centerFinalの位置と同じ）
            .position(x: UIScreen.main.bounds.width * 0.5, y: UIScreen.main.bounds.height * 0.5)
            
            Text("準備完了")
                .font(.title).bold().foregroundColor(.white)
                .padding(.top, 100) // アイコンとかぶらないように
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
    
    // ターゲット座標
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
        case .centerFinal: return CGPoint(x: w * 0.5, y: h * 0.5) // ★最後に戻る
        default: return CGPoint(x: w * 0.5, y: h * 0.5)
        }
    }
    
    private func startCalibrationPhase() {
        progress = 0.0
        // 1点あたり1.2秒
        withAnimation(.linear(duration: 1.2)) { progress = 1.0 }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
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
        case .centerFinal:
            // ★最後の仕上げ：もう一度中心を見て、オフセットを最終調整
            gazeManager.calibrateCenter()
        default: break
        }
    }
    
    private func advanceStep() {
        withAnimation {
            switch currentStep {
            case .ready: currentStep = .center
            case .center: currentStep = .topLeft
            case .topLeft: currentStep = .topRight
            case .topRight: currentStep = .midLeft
            case .midLeft: currentStep = .midRight
            case .midRight: currentStep = .bottomRight
            case .bottomRight: currentStep = .bottomLeft
            case .bottomLeft: currentStep = .centerFinal // ★8点目
            case .centerFinal: currentStep = .finished   // ★完了
            case .finished: break
            }
        }
        if isCalibrating() { startCalibrationPhase() }
    }
}

// ターゲットView (変更なし)
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

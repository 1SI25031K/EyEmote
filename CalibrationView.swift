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
    
    // ★ 8点キャリブレーションに変更 (最後にもう一度センター)
    enum Step {
        case start
        case center
        case topLeft
        case topRight
        case midLeft
        case midRight
        case bottomRight
        case bottomLeft
        case centerFinal // ★追加: 完了アニメーションへ繋ぐための点
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
            
            // 計測中のターゲット表示
            if isCalibrating() {
                CalibrationTarget(progress: progress)
                    .position(targetPosition())
                    .onAppear { startCalibrationPhase() }
                    // アニメーションを少し滑らかに
                    .animation(Animation.easeInOut(duration: 0.6), value: currentStep)
            }
        }
    }
    
    // 開始画面 (変更なし)
    var startScreen: some View {
        VStack(spacing: 30) {
            Image(systemName: "eye.fill")
                .font(.system(size: 70))
                .foregroundColor(.blue)
            Text("視線入力の調整")
                .font(.largeTitle).bold().foregroundColor(.white)
            VStack(spacing: 15) {
                Text("8つのポイントを見つめて精度を高めます。") // 文言変更
                    .font(.title3).foregroundColor(.white)
                Text("体の位置がずれても大丈夫。\nAIがずれを検知して、自動で再調整します。")
                    .multilineTextAlignment(.center).foregroundColor(.gray).padding(.top, 4)
                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.2.circlepath.camera.fill")
                            .foregroundColor(.orange)
                        Text("位置ズレ自動補正 ON")
                            .font(.caption).fontWeight(.bold).foregroundColor(.orange)
                    }
                    .padding(8).background(Color.orange.opacity(0.15)).cornerRadius(8)
                    HStack(spacing: 8) {
                        Image(systemName: "eye.slash.fill").foregroundColor(.green)
                        Text("3秒閉じて開けるとリセット")
                            .font(.caption).fontWeight(.bold).foregroundColor(.green)
                    }
                    .padding(8).background(Color.green.opacity(0.15)).cornerRadius(8)
                }
            }
            .padding()
            Button(action: { startCalibration() }) {
                Text("今すぐ開始")
                    .font(.title3.bold())
                    .padding(.horizontal, 40).padding(.vertical, 16)
                    .background(Color.blue).cornerRadius(30).foregroundColor(.white)
            }
            Text("\(countdown)秒後に開始...").foregroundColor(.gray)
                .onAppear { startCountdown() }
        }
    }
    
    // 完了画面
    // ★ポイント: 直前の centerFinal と同じ位置にアイコンを出すことで、
    // ターゲットがチェックマークに変化したように見せる
    var finishedScreen: some View {
        VStack {
            // 画面中央に配置
            ZStack {
                Circle()
                    .fill(Color.green)
                    .frame(width: 80, height: 80)
                    .scaleEffect(progress) // ポップアップアニメーション
                
                Image(systemName: "checkmark")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(.white)
                    .scaleEffect(progress)
            }
            .shadow(color: .green.opacity(0.5), radius: 20)
            
            Text("準備完了")
                .font(.title).bold().foregroundColor(.white)
                .padding(.top, 20)
                .opacity(progress)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                progress = 1.0
            }
            // 1.5秒後にメイン画面へ
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { onComplete() }
        }
    }
    
    // --- ロジック ---
    
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
        case .centerFinal: return CGPoint(x: w * 0.5, y: h * 0.5) // ★最後に戻ってくる
        default: return CGPoint(x: w * 0.5, y: h * 0.5)
        }
    }
    
    private func startCalibrationPhase() {
        progress = 0.0
        // 各ステップ1.2秒 (少しテンポアップ)
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
            // ★最後にもう一度「中心」を基準として再設定する（仕上げ）
            gazeManager.calibrateCenter()
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
            case .bottomLeft: currentStep = .centerFinal // ★ 8点目へ
            case .centerFinal: currentStep = .finished   // ★ 完了画面へ
            default: break
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

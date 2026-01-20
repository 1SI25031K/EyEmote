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
    
    // 5点キャリブレーションのステップ
    enum Step {
        case start
        case center
        case topLeft
        case topRight
        case bottomRight
        case bottomLeft
        case finished
    }
    
    @State private var currentStep: Step = .start
    @State private var progress: CGFloat = 0.0
    @State private var centerRaw: CGPoint = .zero
    
    // カウントダウン用
    @State private var countdown: Int = 10
    @State private var timer: Timer?
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.95).ignoresSafeArea()
            
            VStack {
                if currentStep == .start {
                    VStack(spacing: 30) {
                        Image(systemName: "eye.fill")
                            .font(.system(size: 70))
                            .foregroundColor(.blue)
                            .shadow(color: .blue.opacity(0.5), radius: 10)
                        
                        Text("視線入力の調整")
                            .font(.largeTitle).bold()
                            .foregroundColor(.white)
                        
                        VStack(spacing: 15) {
                            Text("画面に表示される円を順番に見つめてください。\nあなたの目の動きに合わせて、AIが感度を自動学習します。")
                                .multilineTextAlignment(.center)
                                .foregroundColor(.gray)
                            
                            // プライバシーに関する重要な注釈
                            HStack(spacing: 8) {
                                Image(systemName: "lock.shield.fill")
                                    .foregroundColor(.green)
                                Text("すべての視線データはこのiPad内で安全に処理されます。")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                            .padding()
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(8)
                        }
                        .padding(.horizontal)
                        
                        Spacer().frame(height: 20)
                        
                        // カウントダウン付きボタン
                        Button(action: { startCalibration() }) {
                            HStack {
                                Text("今すぐ開始")
                                Image(systemName: "arrow.right")
                            }
                            .font(.title3.bold())
                            .padding(.horizontal, 40)
                            .padding(.vertical, 16)
                            .background(Color.blue)
                            .cornerRadius(30)
                            .foregroundColor(.white)
                        }
                        
                        Text("\(countdown)秒後に自動で開始します...")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .onAppear { startCountdown() }
                    }
                    .padding()
                } else if currentStep == .finished {
                    VStack(spacing: 20) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 80))
                            .foregroundColor(.green)
                            .scaleEffect(progress)
                            .animation(.spring(), value: progress)
                        
                        Text("セットアップ完了")
                            .font(.title).bold()
                            .foregroundColor(.white)
                    }
                    .onAppear {
                        progress = 1.0
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            onComplete()
                        }
                    }
                }
            }
            
            // ターゲット表示
            if isCalibrating() {
                CalibrationTarget(progress: progress)
                    .position(targetPosition())
                    .onAppear {
                        startCalibrationPhase()
                    }
                    // アニメーションの指定を明示的にAnimation型にする
                    .animation(Animation.easeInOut(duration: 0.6), value: currentStep)
            }
        }
    }
    
    private func startCountdown() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if countdown > 1 {
                countdown -= 1
            } else {
                startCalibration()
            }
        }
    }
    
    private func startCalibration() {
        timer?.invalidate()
        withAnimation { currentStep = .center }
    }
    
    private func isCalibrating() -> Bool {
        return currentStep != .start && currentStep != .finished
    }
    
    private func targetPosition() -> CGPoint {
        let w = UIScreen.main.bounds.width
        let h = UIScreen.main.bounds.height
        let inset: CGFloat = 0.15
        
        switch currentStep {
        case .center: return CGPoint(x: w * 0.5, y: h * 0.5)
        case .topLeft: return CGPoint(x: w * inset, y: h * inset)
        case .topRight: return CGPoint(x: w * (1 - inset), y: h * inset)
        case .bottomRight: return CGPoint(x: w * (1 - inset), y: h * (1 - inset))
        case .bottomLeft: return CGPoint(x: w * inset, y: h * (1 - inset))
        default: return CGPoint(x: w * 0.5, y: h * 0.5)
        }
    }
    
    private func startCalibrationPhase() {
        progress = 0.0
        withAnimation(.linear(duration: 2.0)) {
            progress = 1.0
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
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
            case .topRight: currentStep = .bottomRight
            case .bottomRight: currentStep = .bottomLeft
            case .bottomLeft: currentStep = .finished
            default: break
            }
        }
        
        if isCalibrating() {
            startCalibrationPhase()
        }
    }
}

// ▼ 前回忘れていた重要なパーツです！ここに含まれています ▼
struct CalibrationTarget: View {
    var progress: CGFloat
    
    var body: some View {
        ZStack {
            // 外枠
            Circle()
                .stroke(Color.white.opacity(0.3), lineWidth: 4)
                .frame(width: 60, height: 60)
            
            // 進行状況（Siriのようなエフェクト）
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.blue, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 60, height: 60)
            
            // 中心点
            Circle()
                .fill(Color.white)
                .frame(width: 10, height: 10)
        }
    }
}

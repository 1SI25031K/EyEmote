//
//  SwiftUIView.swift
//  EyEmote
//
//  Created by Kosei Miyamoto on 2026/01/21.
//

import SwiftUI

// 体験のフェーズ定義
enum SoulPhase {
    case colorSelection // 0-45s: 色の海
    case rhythm         // 45-90s: 波紋の鼓動
    case manifestation  // 90-120s: 結実（Deep Blink待ち）
    case finished       // 完了
}

@available(iOS 17.0, *)
struct FluidSoulView: View {
    @ObservedObject var gazeManager: GazeManager
    var onExperienceFinished: () -> Void
    
    @State private var phase: SoulPhase = .colorSelection
    @State private var timeElapsed: TimeInterval = 0
    @State private var particles: [SoulParticle] = []
    @State private var isCrystallized: Bool = false
    @State private var showFinalMessage: Bool = false
    
    // タイマー
    let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ZStack {
            // 背景色 (現在の感情カラーを反映してじわじわ変わる)
            LinearGradient(
                colors: [getBackgroundColor().opacity(0.8), .black],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 2.0), value: particles.last?.color)
            
            // --- Liquid Glass Canvas ---
            TimelineView(.animation) { context in
                Canvas { ctx, size in
                    // パーティクル描画
                    for particle in particles {
                        let rect = CGRect(
                            x: particle.position.x * size.width - particle.size/2,
                            y: particle.position.y * size.height - particle.size/2,
                            width: particle.size,
                            height: particle.size
                        )
                        ctx.fill(Circle().path(in: rect), with: .color(particle.color))
                    }
                }
                // ★ Liquid Effect Magic
                // Blurでぼかして、alphaThresholdで境界をパキッとさせることで「液体」に見せる
                .blur(radius: isCrystallized ? 0 : 30) // 結晶化するとBlurが消えて硬質になる
                .colorMultiply(isCrystallized ? .white : .white.opacity(0.8))
                .layerEffect(
                    ShaderLibrary.default.thresholdAlpha(), // カスタムシェーダーがなければ標準ブレンドで代用可能だが、今回は標準機能で
                    maxSampleOffset: .zero
                )
            }
            // Blurの閾値処理をSwiftUI標準機能で簡易再現するレイヤー
            .drawingGroup() // Metalでの描画を強制
            
            // --- UI Layer (Material) ---
            VStack {
                // ガイドメッセージ
                if phase != .finished {
                    Text(getPhaseMessage())
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundColor(.white.opacity(0.8))
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .padding(.top, 40)
                        .transition(.opacity)
                }
                
                Spacer()
                
                // フェーズインジケーター (控えめに)
                if !isCrystallized {
                    HStack(spacing: 4) {
                        Capsule().fill(phase == .colorSelection ? Color.white : Color.gray.opacity(0.3)).frame(width: 20, height: 4)
                        Capsule().fill(phase == .rhythm ? Color.white : Color.gray.opacity(0.3)).frame(width: 20, height: 4)
                        Capsule().fill(phase == .manifestation ? Color.white : Color.gray.opacity(0.3)).frame(width: 20, height: 4)
                    }
                    .padding(.bottom, 20)
                }
            }
            
            // --- Final Message ---
            if showFinalMessage {
                VStack(spacing: 20) {
                    Text("This is your feeling right now.")
                        .font(.largeTitle).bold()
                        .foregroundColor(.white)
                        .shadow(color: .white, radius: 10)
                    
                    Text("Created by your eyes.")
                        .font(.title2)
                        .foregroundColor(.white.opacity(0.8))
                    
                    Button(action: onExperienceFinished) {
                        Text("Return to Home")
                            .font(.headline)
                            .padding(.horizontal, 30)
                            .padding(.vertical, 12)
                            .background(Color.white)
                            .foregroundColor(.black)
                            .cornerRadius(30)
                    }
                    .padding(.top, 30)
                }
                .transition(.opacity.combined(with: .scale))
            }
        }
        .onReceive(timer) { _ in
            updateLoop()
        }
        .onAppear {
            // Deep Blinkをこのビュー専用のアクションに上書き
            gazeManager.onDeepBlinkDetected = {
                if phase == .manifestation {
                    triggerCrystallization()
                }
            }
        }
    }
    
    // --- ロジック ---
    
    private func updateLoop() {
        if isCrystallized { return }
        
        // 1. 時間経過管理
        timeElapsed += 0.05
        
        if timeElapsed < 45 {
            phase = .colorSelection
        } else if timeElapsed < 90 {
            phase = .rhythm
        } else {
            phase = .manifestation
        }
        
        // 2. 視線に応じたパーティクル生成
        let gazePos = gazeManager.cursorRelativePosition
        let velocity = gazeManager.gazeVelocity
        
        // 現在の感情色を決定
        let currentColor = determineColor(pos: gazePos)
        
        // フェーズごとの挙動変化
        var size: CGFloat = 80
        if phase == .rhythm {
            // リズムフェーズでは速度に応じてサイズと生成数が変わる
            size = 80 + (velocity * 100) // 速いと大きくなる
        }
        
        // パーティクル追加 (上限を設けてパフォーマンス維持)
        let particle = SoulParticle(
            position: gazePos,
            color: currentColor,
            size: size,
            createdAt: Date()
        )
        particles.append(particle)
        
        if particles.count > 150 {
            particles.removeFirst()
        }
        
        // Haptics (色が大きく変わった時などにフィードバックを入れると良いが、ここではシンプルに強い動きの時)
        if velocity > 0.8 && phase == .rhythm {
             let generator = UIImpactFeedbackGenerator(style: .light)
             generator.impactOccurred(intensity: 0.5)
        }
    }
    
    private func determineColor(pos: CGPoint) -> Color {
        // エリアによる色の変化
        // 左上: 赤(情熱) 右上: オレンジ(喜び)
        // 左下: 青(静寂) 右下: 紫(神秘)
        // 中央: 緑(調和)
        
        let r = Double(1.0 - pos.y) // 上に行くほど赤要素
        let b = Double(pos.y)       // 下に行くほど青要素
        let g = Double(1.0 - abs(pos.x - 0.5) * 2) // 中央ほど緑
        
        // X軸で微調整
        let xBias = Double(pos.x) // 右に行くほど明るく/黄色っぽく
        
        return Color(
            red: r + (xBias * 0.2),
            green: g * 0.8,
            blue: b + ((1.0-xBias) * 0.2)
        )
    }
    
    private func getBackgroundColor() -> Color {
        // パーティクルの平均色を背景にする
        guard let last = particles.last else { return .black }
        return last.color
    }
    
    private func getPhaseMessage() -> String {
        switch phase {
        case .colorSelection: return "Swim in the sea of colors..."
        case .rhythm: return "Express the rhythm of your soul..."
        case .manifestation: return "Close your eyes for 3 seconds to manifest..."
        case .finished: return ""
        }
    }
    
    private func triggerCrystallization() {
        guard !isCrystallized else { return }
        
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        withAnimation(.easeInOut(duration: 3.0)) {
            isCrystallized = true
            phase = .finished
        }
        
        // クリスタル化の後にメッセージ
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            withAnimation {
                showFinalMessage = true
            }
        }
    }
}

// パーティクルデータモデル
struct SoulParticle: Identifiable {
    let id = UUID()
    let position: CGPoint
    let color: Color
    let size: CGFloat
    let createdAt: Date
}

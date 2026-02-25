//
//  SwiftUIView.swift
//  EyEmote
//
//  Created by Kosei Miyamoto on 2026/01/21.
//
import SwiftUI

@available(iOS 17.0, *)
struct FluidSoulExperienceView: View {
    @ObservedObject var gazeManager: GazeManager
    var onComplete: () -> Void
    
    // Timeline Management
    @State private var startTime: Date?
    @State private var elapsedTime: TimeInterval = 0
    @State private var experiencePhase: ExperiencePhase = .tracking
    
    // Ripple Effect (Deep Blink Feedback)
    @State private var rippleScale: CGFloat = 0.0
    @State private var rippleOpacity: Double = 0.0
    
    enum ExperiencePhase {
        case tracking, exploration, manifestation, completion
    }
    
    let timer = Timer.publish(every: 1/60, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ZStack {
            // Layer 1: Emotion Map
            EmotionBackgroundView(gazePoint: gazeManager.cursorRelativePosition)
                .ignoresSafeArea()
            
            // Layer 2: Liquid Glass Shader & Gaze Feedback
            LiquidGlassCanvas(
                gazePoint: gazeManager.cursorRelativePosition,
                dwellTime: gazeManager.dwellTime,
                phase: experiencePhase
            )
            .ignoresSafeArea()
            .blendMode(.hardLight)
            
            // Layer 3: Ripple (Deep Blink Feedback)
            Circle()
                .stroke(Color.white.opacity(0.8), lineWidth: 4)
                .scaleEffect(rippleScale)
                .opacity(rippleOpacity)
                .ignoresSafeArea()
            
            // Layer 4: UI & Messages
            VStack {
                // Status Message (Auto Correction / Deep Blink)
                // 自動補正時のメッセージはここに表示されます
                if !gazeManager.statusMessage.isEmpty {
                    Text(gazeManager.statusMessage)
                        .font(.caption)
                        .fontWeight(.bold)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .background(Color.black.opacity(0.4)) // 視認性向上のための背景
                        .clipShape(Capsule())
                        .shadow(radius: 4)
                        .padding(.top, 50) // Safe Area回避
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .animation(.easeInOut, value: gazeManager.statusMessage)
                }
                
                Spacer()
                
                // Storytelling Text (Bottom)
                if let text = phaseText {
                    Text(text)
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundColor(.white.opacity(0.9))
                        .shadow(radius: 10)
                        .padding(.bottom, 60)
                        .transition(.opacity)
                        .animation(.easeInOut, value: text)
                }
            }
        }
        .onAppear {
            // ★修正: 独自UIなしで即座にセッション開始
            startTime = Date()
            gazeManager.startSession()
        }
        .onReceive(timer) { _ in
            guard let start = startTime else { return }
            updateTimeline(start: start)
        }
        .onChange(of: gazeManager.triggerRipple) { _ in
            triggerRippleAnimation()
        }
    }
    
    private func updateTimeline(start: Date) {
        elapsedTime = Date().timeIntervalSince(start)
        if elapsedTime < 30 { experiencePhase = .tracking }
        else if elapsedTime < 90 { experiencePhase = .exploration }
        else if elapsedTime < 150 { experiencePhase = .manifestation }
        else if elapsedTime < 180 { experiencePhase = .completion }
        else { onComplete() }
    }
    
    private func triggerRippleAnimation() {
        rippleScale = 0.0; rippleOpacity = 1.0
        withAnimation(.easeOut(duration: 1.5)) { rippleScale = 2.0; rippleOpacity = 0.0 }
    }
    
    private var phaseText: String? {
        switch experiencePhase {
        case .tracking: return "Follow the light with your eyes."
        case .exploration: return "Paint the canvas with your emotions."
        case .manifestation: return "Stare to deepen the texture.\nClose eyes (3s) to reset."
        case .completion: return "Silence is not empty. It is full of answers."
        }
    }
}

// Subviews (EmotionBackgroundView, LiquidGlassCanvas) は変更なしのため省略
// 先ほどのコードと同じものを使用してください

// MARK: - Subviews

struct EmotionBackgroundView: View {
    let gazePoint: CGPoint
    let cTopLeft = Color.red
    let cTopRight = Color.orange
    let cBottomLeft = Color.purple
    let cBottomRight = Color.blue
    let cCenter = Color.white
    
    var body: some View {
        GeometryReader { geometry in
            let x = min(max(gazePoint.x, 0), 1)
            let y = min(max(gazePoint.y, 0), 1)
            ZStack {
                cCenter
                cTopLeft.opacity((1-x) * (1-y))
                cTopRight.opacity(x * (1-y))
                cBottomLeft.opacity((1-x) * y)
                cBottomRight.opacity(x * y)
            }
            .animation(.linear(duration: 0.5), value: gazePoint)
        }
    }
}

// MARK: - Liquid Glass Canvas (Updated)

@available(iOS 17.0, *)
struct LiquidGlassCanvas: View {
    let gazePoint: CGPoint
    let dwellTime: TimeInterval
    let phase: FluidSoulExperienceView.ExperiencePhase
    
    var body: some View {
        TimelineView(.animation) { context in
            Canvas { ctx, size in
                let time = context.date.timeIntervalSince1970
                let w = size.width
                let h = size.height
                
                let cx = gazePoint.x * w
                let cy = gazePoint.y * h
                
                // ★ここを修正: ホワイトカーソルを「Liquid」に変更
                // 複数の円を重ねて、Blurで溶け合わせることで液体表現を作る
                
                // 1. ベースの液滴 (大きく動く)
                // 注視(Dwell)すると大きくなる
                let baseRadius = 50.0 + (dwellTime * 30.0)
                
                // 2. 周囲に分離する小さな液滴 (Metaballs)
                // 3つの衛星のような液滴が、視線の周りを有機的に回る
                for i in 0..<3 {
                    let speed = 3.0
                    let angle = (time * speed) + (Double(i) * 2.0 * .pi / 3.0)
                    
                    // 注視しているときは震え(Wobble)が大きくなる
                    let wobble = sin(time * 5.0) * (5.0 + dwellTime * 10.0)
                    
                    let radiusOffset = 25.0 + wobble
                    let offsetX = cos(angle) * radiusOffset
                    let offsetY = sin(angle) * radiusOffset
                    
                    let blobRect = CGRect(
                        x: cx + offsetX - (baseRadius * 0.6),
                        y: cy + offsetY - (baseRadius * 0.6),
                        width: baseRadius * 1.2,
                        height: baseRadius * 1.2
                    )
                    
                    // 白の不透明度を下げて、重ね合わせ効果を狙う
                    ctx.fill(Circle().path(in: blobRect), with: .color(.white.opacity(0.5)))
                }
                
                // 3. 中心のコア (ユーザーの視点の芯)
                let coreRect = CGRect(
                    x: cx - (baseRadius * 0.5),
                    y: cy - (baseRadius * 0.5),
                    width: baseRadius,
                    height: baseRadius
                )
                ctx.fill(Circle().path(in: coreRect), with: .color(.white.opacity(0.8)))
                
                // 4. ガラス質のハイライト (Specular)
                let highlightRect = CGRect(x: cx - 15, y: cy - 25, width: 25, height: 15)
                ctx.fill(Ellipse().path(in: highlightRect), with: .color(.white.opacity(0.9)))
                
            }
            // ★重要: Blurをかけることで、バラバラの円が「くっついて」見える (Metaball効果)
            .blur(radius: 20)
            // ColorMatrixでアルファ値を強調し、輪郭をはっきりさせる
            // (SwiftUI標準機能だけで簡易的な閾値処理を行う)
            .colorMultiply(.white)
        }
    }
}

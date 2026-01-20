//
//  SwiftUIView.swift
//  EyEmote
//
//  Created by Kosei Miyamoto on 2026/01/20.
//

import SwiftUI

struct SplashView: View {
    var onFinished: () -> Void
    
    // 7秒カウントダウン
    @State private var timeRemaining: CGFloat = 7.0
    @State private var opacity: Double = 0.0
    @State private var barProgress: CGFloat = 1.0
    
    var body: some View {
        ZStack {
            // 背景: Liquid Glassが映えるディープ・ブルーブラック
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.1),
                    Color(red: 0.1, green: 0.1, blue: 0.3)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack {
                Spacer()
                
                // メインコンテンツ (光彩効果を追加)
                VStack(spacing: 40) {
                    ZStack {
                        // アイコンの背後に光のオーラ
                        Circle()
                            .fill(Color.blue.opacity(0.3))
                            .frame(width: 120, height: 120)
                            .blur(radius: 20)
                        
                        Image(systemName: "eye.fill")
                            .font(.system(size: 80))
                            .foregroundColor(.white.opacity(0.9))
                            // ガラスのような質感を与えるオーバーレイ
                            .overlay(
                                LinearGradient(colors: [.white.opacity(0.8), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
                                    .mask(Image(systemName: "eye.fill").font(.system(size: 80)))
                            )
                            .shadow(color: .blue.opacity(0.8), radius: 10)
                    }
                    .scaleEffect(opacity > 0 ? 1.0 : 0.8)
                    .animation(.easeOut(duration: 1.0), value: opacity)
                    
                    VStack(spacing: 24) {
                        Text("EyEmote")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .shadow(color: .blue.opacity(0.5), radius: 10)
                        
                        Text("このアプリは、ALS患者の方などが\n視線だけで世界と繋がれるように設計されました。")
                            .font(.title3)
                            .fontWeight(.medium)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.white.opacity(0.9))
                            .lineSpacing(8)
                        
                        Text("あなたの目の動きを学習しています...\nリラックスして画面を見つめてください。")
                            .font(.body)
                            .foregroundColor(.white.opacity(0.6))
                            .padding(.top, 20)
                    }
                    .opacity(opacity)
                    .offset(y: opacity > 0 ? 0 : 20)
                    .animation(.easeOut(duration: 1.0).delay(0.5), value: opacity)
                }
                
                Spacer()
                
                // ★ Liquid Glass Progress Bar
                GeometryReader { geometry in
                    VStack {
                        Spacer()
                        ZStack(alignment: .center) { // 中央揃えで短くしていく
                            // 1. ガラスの容器 (Glass Container)
                            Capsule()
                                .fill(.ultraThinMaterial) // すりガラス
                                .frame(height: 8)
                                .overlay(
                                    Capsule().stroke(Color.white.opacity(0.3), lineWidth: 1)
                                )
                                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                            
                            // 2. 液体 (Liquid Light)
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [Color.cyan, Color.blue]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geometry.size.width * barProgress, height: 8)
                                // グロー効果（発光）
                                .shadow(color: .blue.opacity(0.8), radius: 8)
                                .animation(.linear(duration: 7.0), value: barProgress)
                        }
                    }
                }
                .frame(height: 20)
                .padding(.horizontal, 40) // 横幅に余白を持たせる
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            withAnimation { opacity = 1.0 }
            startTimer()
        }
    }
    
    private func startTimer() {
        // バーが中央に向かって消えていく
        withAnimation(.linear(duration: 7.0)) {
            barProgress = 0.0
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 7.0) {
            withAnimation(.easeInOut(duration: 0.5)) {
                onFinished()
            }
        }
    }
}

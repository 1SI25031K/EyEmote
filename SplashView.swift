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
    // バーの進捗 (1.0 -> 0.0)
    @State private var barProgress: CGFloat = 1.0
    
    var body: some View {
        ZStack {
            // 背景グラデーション
            LinearGradient(
                gradient: Gradient(colors: [Color.black, Color(red: 0.1, green: 0.1, blue: 0.3)]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack {
                Spacer()
                
                // メインコンテンツ
                VStack(spacing: 40) {
                    Image(systemName: "eye.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.blue)
                        .shadow(color: .blue.opacity(0.8), radius: 20)
                        .scaleEffect(opacity > 0 ? 1.0 : 0.8)
                        .animation(.easeOut(duration: 1.0), value: opacity)
                    
                    VStack(spacing: 24) {
                        Text("EyEmote")
                            .font(.largeTitle).bold()
                            .foregroundColor(.white)
                        
                        Text("このアプリは、ALS患者の方などが\n視線だけで世界と繋がれるように設計されました。")
                            .font(.title3)
                            .fontWeight(.medium)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.white.opacity(0.9))
                            .lineSpacing(8)
                        
                        Text("あなたの目の動きを学習しています...\nリラックスして画面を見つめてください。")
                            .font(.body)
                            .foregroundColor(.gray)
                            .padding(.top, 20)
                    }
                    .opacity(opacity)
                    .offset(y: opacity > 0 ? 0 : 20)
                    .animation(.easeOut(duration: 1.0).delay(0.5), value: opacity)
                }
                
                Spacer()
                
                // ★修正: カウントダウンバー
                // 画面下部に配置し、幅が短くなっていくアニメーション
                GeometryReader { geometry in
                    VStack {
                        Spacer()
                        ZStack(alignment: .leading) {
                            // 背景バー (薄い白)
                            Rectangle()
                                .fill(Color.white.opacity(0.2))
                                .frame(height: 4)
                            
                            // 進行バー (青) - 中央に向かって短くなる、あるいは左から短くなる
                            // ここでは「時間が減っていく」表現として、幅を減らします
                            Rectangle()
                                .fill(Color.blue)
                                .frame(width: geometry.size.width * barProgress, height: 4)
                                .shadow(color: .blue, radius: 4)
                        }
                    }
                }
                .frame(height: 10) // 領域確保
                .padding(.bottom, 20) // 下端からの余白
            }
            .padding()
        }
        .onAppear {
            withAnimation { opacity = 1.0 }
            startTimer()
        }
    }
    
    private func startTimer() {
        // バーのアニメーション開始 (7秒かけて 1.0 -> 0.0)
        withAnimation(.linear(duration: 7.0)) {
            barProgress = 0.0
        }
        
        // 7秒後に完了コールバック
        DispatchQueue.main.asyncAfter(deadline: .now() + 7.0) {
            withAnimation(.easeInOut(duration: 0.5)) {
                onFinished()
            }
        }
    }
}

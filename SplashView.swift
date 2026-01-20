//
//  SwiftUIView.swift
//  EyEmote
//
//  Created by Kosei Miyamoto on 2026/01/20.
//

import SwiftUI

struct SplashView: View {
    var onFinished: () -> Void
    
    // ★修正: 10秒 -> 8秒に変更
    @State private var timeRemaining: Int = 7
    @State private var opacity: Double = 0.0
    
    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [Color.black, Color(red: 0.1, green: 0.1, blue: 0.3)]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
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
                
                Spacer()
                
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.1), lineWidth: 6)
                        .frame(width: 60, height: 60)
                    
                    // ★修正: 分母を 10.0 -> 8.0 に変更
                    Circle()
                        .trim(from: 0, to: CGFloat(timeRemaining) / 8.0)
                        .stroke(Color.blue, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 60, height: 60)
                        .animation(.linear(duration: 1.0), value: timeRemaining)
                    
                    Text("\(timeRemaining)")
                        .font(.headline)
                        .foregroundColor(.white)
                        .contentTransition(.numericText())
                }
                .padding(.bottom, 50)
            }
            .padding()
        }
        .onAppear {
            withAnimation { opacity = 1.0 }
            startTimer()
        }
    }
    
    private func startTimer() {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            if timeRemaining > 0 {
                timeRemaining -= 1
            } else {
                timer.invalidate()
                withAnimation(.easeInOut(duration: 0.5)) {
                    onFinished()
                }
            }
        }
    }
}

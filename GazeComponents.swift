//
//  GazeComponents.swift
//  EyEmote
//
//  Created by Kosei Miyamoto on 2026/01/20.
//
import SwiftUI

// カーソルView
struct GazeCursorView: View {
    var position: CGPoint
    
    var body: some View {
        Circle()
            .fill(Color.blue.opacity(0.5))
            .frame(width: 30, height: 30)
            .overlay(Circle().stroke(Color.white, lineWidth: 2))
            .shadow(radius: 4)
            .position(position)
            .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.7), value: position)
            .allowsHitTesting(false)
    }
}

// 視線ボタン
struct GazeButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    
    // 親Viewから計算済みの座標をもらう
    var cursorPosition: CGPoint
    
    @State private var isHovering = false
    @State private var progress: CGFloat = 0.0
    private let dwellTime: TimeInterval = 1.5
    
    @State private var frame: CGRect = .zero
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(isHovering ? Color.blue.opacity(0.1) : Color(.secondarySystemBackground))
                
                if isHovering {
                    RoundedRectangle(cornerRadius: 16)
                        .trim(from: 0, to: progress)
                        .stroke(Color.blue, lineWidth: 4)
                }
                
                VStack {
                    Image(systemName: icon)
                        .font(.system(size: 30))
                        .foregroundColor(.blue)
                    Text(title)
                        .font(.headline)
                        .padding(.top, 4)
                }
            }
            .onAppear { self.frame = geo.frame(in: .global) }
            // 【修正1】iOS 16以前の書き方に変更（引数を1つにする）
            .onChange(of: geo.frame(in: .global)) { newFrame in
                self.frame = newFrame
            }
            // 【修正2】iOS 16以前の書き方に変更（引数を1つにする）
            .onChange(of: cursorPosition) { newPos in
                isHovering = frame.contains(newPos)
            }
            .task(id: isHovering) {
                if isHovering {
                    let startTime = Date.now
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .milliseconds(50))
                        
                        let elapsed = Date.now.timeIntervalSince(startTime)
                        withAnimation(.linear(duration: 0.05)) {
                            progress = elapsed / dwellTime
                        }
                        
                        if progress >= 1.0 {
                            triggerAction()
                            break
                        }
                    }
                } else {
                    withAnimation { progress = 0 }
                }
            }
        }
        .frame(height: 120)
    }
    
    private func triggerAction() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        action()
        progress = 0
        isHovering = false
    }
}

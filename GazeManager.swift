//
//  GazeManager.swift
//  EyEmote
//
//  Created by Kosei Miyamoto on 2026/01/20.
//

import SwiftUI
import ARKit
import Combine

@MainActor
class GazeManager: NSObject, ObservableObject, ARSessionDelegate {
    // ... (既存のプロパティはそのまま) ...
    @Published var cursorRelativePosition: CGPoint = CGPoint(x: 0.5, y: 0.5)
    @Published var isFaceDetected: Bool = false
    @Published var statusMessage: String = "起動中..."
    
    // 設定値
    @Published var sensitivityX: CGFloat = 2.0
    @Published var sensitivityY: CGFloat = 2.0
    @Published var xOffset: CGFloat = 0.0
    @Published var yOffset: CGFloat = 0.0
    
    // ジェスチャーリセット用
    @Published var isResetting: Bool = false // リセット動作中か
    private var gestureHoldTime: TimeInterval = 0
    private let gestureThreshold: Float = 0.6 // 口の開き具合(0.0-1.0)
    
    // スムージング係数
    @Published var smoothing: CGFloat = 0.1
    
    var arSession = ARSession()
    private var rawLookAtPoint: CGPoint = .zero
    private var accumulatedSensX: [CGFloat] = []
    private var accumulatedSensY: [CGFloat] = []
    
    override init() {
        super.init()
        setupAR()
    }
    
    private func setupAR() {
        guard ARFaceTrackingConfiguration.isSupported else {
            statusMessage = "❌ 非対応機種です"
            return
        }
        let configuration = ARFaceTrackingConfiguration()
        configuration.isLightEstimationEnabled = true
        arSession.delegate = self
        arSession.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }
    
    nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        guard let faceAnchor = anchors.first as? ARFaceAnchor else { return }
        Task { @MainActor in
            self.isFaceDetected = true
            self.updateGaze(faceAnchor: faceAnchor)
            self.checkFacialGesture(faceAnchor: faceAnchor) // ジェスチャー監視
        }
    }
    
    // ★追加: フェイシャルジェスチャーでのリセット機能
    private func checkFacialGesture(faceAnchor: ARFaceAnchor) {
        // "jawOpen" (口を開ける動作) の値を取得 (0.0 〜 1.0)
        let jawOpenValue = faceAnchor.blendShapes[.jawOpen]?.floatValue ?? 0.0
        
        if jawOpenValue > gestureThreshold {
            // 閾値を超えていたらカウントアップ
            gestureHoldTime += 0.02 // 約60fps想定で加算
            
            if gestureHoldTime > 1.5 { // 1.5秒維持したらリセット発動
                triggerEmergencyReset()
                gestureHoldTime = 0 // 連続発動防止
            }
        } else {
            gestureHoldTime = 0
            if isResetting { isResetting = false }
        }
    }
    
    private func triggerEmergencyReset() {
        // フィードバック
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        // 現在の視線を「中央」として強制リセット
        calibrateCenter()
        
        // ユーザーへの通知フラグ
        self.isResetting = true
        self.statusMessage = "✅ 位置ズレを補正しました"
        
        // 数秒後にメッセージを戻す
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            self.statusMessage = "稼働中"
            self.isResetting = false
        }
    }
    
    private func updateGaze(faceAnchor: ARFaceAnchor) {
        let lookAtPoint = faceAnchor.lookAtPoint
        self.rawLookAtPoint = CGPoint(x: CGFloat(lookAtPoint.x), y: CGFloat(lookAtPoint.y))
        
        // 計算ロジック（変更なし）
        let rawX = CGFloat(lookAtPoint.x)
        let rawY = CGFloat(lookAtPoint.y)
        
        let targetX = (rawX * sensitivityX) + xOffset + 0.5
        let targetY = -(rawY * sensitivityY) + yOffset + 0.5
        
        let currentX = cursorRelativePosition.x
        let currentY = cursorRelativePosition.y
        let smoothedX = currentX + (targetX - currentX) * smoothing
        let smoothedY = currentY + (targetY - currentY) * smoothing
        
        self.cursorRelativePosition = CGPoint(x: smoothedX, y: smoothedY)
    }
    
    // --- 以下、キャリブレーションロジック (既存と同じ) ---
    
    func getCurrentRaw() -> CGPoint { return rawLookAtPoint }
    
    func calibrateCenter() {
        accumulatedSensX = []
        accumulatedSensY = []
        self.xOffset = -(rawLookAtPoint.x * sensitivityX)
        self.yOffset = (rawLookAtPoint.y * sensitivityY)
    }
    
    func calibrateSensitivity(lookingAt targetPoint: CGPoint, centerRaw: CGPoint) {
        let screenDeltaX = targetPoint.x - 0.5
        let screenDeltaY = targetPoint.y - 0.5
        let rawDeltaX = rawLookAtPoint.x - centerRaw.x
        let rawDeltaY = rawLookAtPoint.y - centerRaw.y
        
        if abs(rawDeltaX) > 0.01 {
            let newSensX = abs(screenDeltaX / rawDeltaX)
            accumulatedSensX.append(newSensX)
        }
        if abs(rawDeltaY) > 0.01 {
            let newSensY = abs(screenDeltaY / rawDeltaY)
            accumulatedSensY.append(newSensY)
        }
        
        if !accumulatedSensX.isEmpty {
            self.sensitivityX = accumulatedSensX.reduce(0, +) / CGFloat(accumulatedSensX.count)
        }
        if !accumulatedSensY.isEmpty {
            self.sensitivityY = accumulatedSensY.reduce(0, +) / CGFloat(accumulatedSensY.count)
        }
        
        self.xOffset = -(centerRaw.x * sensitivityX)
        self.yOffset = (centerRaw.y * sensitivityY)
    }
}

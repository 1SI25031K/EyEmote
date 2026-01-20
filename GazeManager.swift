//
//  GazeManager.swift
//  EyEmote
//
//  Created by Kosei Miyamoto on 2026/01/20.
//

import SwiftUI
import ARKit
import Combine
import simd

@MainActor
class GazeManager: NSObject, ObservableObject, ARSessionDelegate {
    // 公開プロパティ
    @Published var cursorRelativePosition: CGPoint = CGPoint(x: 0.5, y: 0.5)
    @Published var isFaceDetected: Bool = false
    @Published var statusMessage: String = "稼働中" // 初期値を変更
    
    // 設定値
    @Published var sensitivityX: CGFloat = 2.0
    @Published var sensitivityY: CGFloat = 2.0
    @Published var xOffset: CGFloat = 0.0
    @Published var yOffset: CGFloat = 0.0
    
    // 補正中フラグ
    @Published var isAutoCorrecting: Bool = false
    
    // 自動補正用変数
    private var lastCalibratedHeadPosition: SIMD3<Float>? = nil
    private let movementThreshold: Float = 0.05 // 5cm
    
    // 閉眼ジェスチャー用変数
    private var eyesClosedStartTime: Date? = nil
    // ★修正: 閾値を0.5に下げて、少し閉じただけでも反応しやすくする
    private let blinkThreshold: Float = 0.5
    private let requiredClosedDuration: TimeInterval = 3.0
    
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
            // 先にGazeを更新して最新の座標を持っておく
            self.updateGaze(faceAnchor: faceAnchor)
            self.checkHeadMovement(faceAnchor: faceAnchor)
            self.checkEyeGesture(faceAnchor: faceAnchor)
        }
    }
    
    // -----------------------------------------------------------
    // MARK: - 閉眼ジェスチャー (手動補正)
    // -----------------------------------------------------------
    
    private func checkEyeGesture(faceAnchor: ARFaceAnchor) {
        let leftBlink = faceAnchor.blendShapes[.eyeBlinkLeft]?.floatValue ?? 0.0
        let rightBlink = faceAnchor.blendShapes[.eyeBlinkRight]?.floatValue ?? 0.0
        
        // 両目が閉じているか
        let isEyesClosed = (leftBlink > blinkThreshold && rightBlink > blinkThreshold)
        
        if isEyesClosed {
            if eyesClosedStartTime == nil {
                eyesClosedStartTime = Date()
            }
        } else {
            // 目が開いた
            if let startTime = eyesClosedStartTime {
                let duration = Date().timeIntervalSince(startTime)
                
                // 3秒以上閉じていた場合
                if duration >= requiredClosedDuration {
                    performManualReset()
                }
                eyesClosedStartTime = nil
            }
        }
    }
    
    private func performManualReset() {
        if isAutoCorrecting { return }
        isAutoCorrecting = true
        
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        // 手動リセット時は「ユーザーが正面を見ている」と仮定してキャリブレーション実行
        calibrateCenter()
        
        // ★ユーザー指定メッセージ
        self.statusMessage = "３秒以上目を閉じていたため、自動補正しました。"
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            if self.statusMessage.contains("３秒以上") {
                self.statusMessage = "稼働中"
                self.isAutoCorrecting = false
            }
        }
    }
    
    // -----------------------------------------------------------
    // MARK: - 頭の位置ズレ検知 (自動補正)
    // -----------------------------------------------------------
    
    private func checkHeadMovement(faceAnchor: ARFaceAnchor) {
        let currentPosition = SIMD3<Float>(
            faceAnchor.transform.columns.3.x,
            faceAnchor.transform.columns.3.y,
            faceAnchor.transform.columns.3.z
        )
        
        if lastCalibratedHeadPosition == nil {
            lastCalibratedHeadPosition = currentPosition
            return
        }
        
        guard let lastPos = lastCalibratedHeadPosition else { return }
        let distance = simd_distance(currentPosition, lastPos)
        
        if distance > movementThreshold && !isAutoCorrecting {
            performAutoCorrection(newPosition: currentPosition)
        }
    }
    
    private func performAutoCorrection(newPosition: SIMD3<Float>) {
        isAutoCorrecting = true
        
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
        
        // ★重要修正: ここで calibrateCenter() を呼ぶと、
        // ユーザーがどこを見ているか分からないのに中央設定してしまい、操作不能になります。
        // そのため、「頭の基準位置」だけを更新し、視線オフセットはいじらないようにします。
        lastCalibratedHeadPosition = newPosition
        
        // ★ユーザー指定メッセージ
        self.statusMessage = "顔の位置ずれを検知し、自動補正しました。"
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            if self.statusMessage.contains("位置ずれ") {
                self.statusMessage = "稼働中"
                self.isAutoCorrecting = false
            }
        }
    }
    
    // -----------------------------------------------------------
    // MARK: - 視線計算 & 共通処理
    // -----------------------------------------------------------
    
    private func updateGaze(faceAnchor: ARFaceAnchor) {
        let lookAtPoint = faceAnchor.lookAtPoint
        self.rawLookAtPoint = CGPoint(x: CGFloat(lookAtPoint.x), y: CGFloat(lookAtPoint.y))
        
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
    
    func calibrateCenter() {
        accumulatedSensX = []
        accumulatedSensY = []
        self.xOffset = -(rawLookAtPoint.x * sensitivityX)
        self.yOffset = (rawLookAtPoint.y * sensitivityY)
        
        // 頭の位置も更新しておく
        if let currentFrame = arSession.currentFrame,
           let anchor = currentFrame.anchors.first(where: { $0 is ARFaceAnchor }) {
            let transform = anchor.transform.columns.3
            self.lastCalibratedHeadPosition = SIMD3<Float>(transform.x, transform.y, transform.z)
        }
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
    
    func getCurrentRaw() -> CGPoint { return rawLookAtPoint }
}

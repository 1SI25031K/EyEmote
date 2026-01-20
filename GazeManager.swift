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
    @Published var statusMessage: String = "" // 初期値は空に（通知がない時は表示しない）
    
    // 設定値
    @Published var sensitivityX: CGFloat = 2.0
    @Published var sensitivityY: CGFloat = 2.0
    @Published var xOffset: CGFloat = 0.0
    @Published var yOffset: CGFloat = 0.0
    
    // 補正中フラグ
    @Published var isAutoCorrecting: Bool = false
    
    // --- 自動補正・静止検知用変数 ---
    private var lastCalibratedHeadPosition: SIMD3<Float>? = nil
    private var lastHeadPosition: SIMD3<Float>? = nil
    private var lastMovementTime: Date = Date() // 最後に動いた時間
    private let movementThreshold: Float = 0.05 // 5cm以上のズレで「移動」とみなす
    private let stabilityDuration: TimeInterval = 5.0 // 5秒間静止
    private var isWaitingForStability: Bool = false   // 静止待ち状態か
    
    // 閉眼ジェスチャー用変数
    private var eyesClosedStartTime: Date? = nil
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
            self.updateGaze(faceAnchor: faceAnchor)
            self.checkHeadStability(faceAnchor: faceAnchor) // 静止検知 & 自動補正
            self.checkEyeGesture(faceAnchor: faceAnchor)    // 手動補正(閉眼)
        }
    }
    
    // -----------------------------------------------------------
    // MARK: - 頭の位置ズレ & 静止検知ロジック
    // -----------------------------------------------------------
    
    private func checkHeadStability(faceAnchor: ARFaceAnchor) {
        let currentPosition = SIMD3<Float>(
            faceAnchor.transform.columns.3.x,
            faceAnchor.transform.columns.3.y,
            faceAnchor.transform.columns.3.z
        )
        
        // 初回基準点設定
        if lastCalibratedHeadPosition == nil {
            lastCalibratedHeadPosition = currentPosition
            lastHeadPosition = currentPosition
            return
        }
        
        guard let calibratedPos = lastCalibratedHeadPosition else { return }
        
        // 1. 基準点からのズレをチェック
        let distFromCalibrated = simd_distance(currentPosition, calibratedPos)
        
        if distFromCalibrated > movementThreshold {
            // 大きくズレている状態。ここから「静止」の監視を始める
            isWaitingForStability = true
            
            // 直前のフレームからの動きもチェック（現在動いている最中か？）
            if let lastFramePos = lastHeadPosition {
                let distFromLastFrame = simd_distance(currentPosition, lastFramePos)
                
                // フレーム間でほとんど動いていなければ「静止中」とみなして時間を進める
                // 動いていればタイマーリセット
                if distFromLastFrame > 0.005 { // 5mm以上の動きでリセット
                    lastMovementTime = Date()
                }
            }
        } else {
            // ズレていない（元の位置に戻った）なら監視解除
            isWaitingForStability = false
            lastMovementTime = Date()
        }
        
        // 2. 静止時間の判定
        if isWaitingForStability {
            let timeSinceMove = Date().timeIntervalSince(lastMovementTime)
            
            if timeSinceMove >= stabilityDuration {
                // 5秒間静止した！ -> 補正実行
                performAutoCorrection(newPosition: currentPosition)
                isWaitingForStability = false // 監視終了
                lastMovementTime = Date()     // タイマーリセット
            }
        }
        
        lastHeadPosition = currentPosition
    }
    
    private func performAutoCorrection(newPosition: SIMD3<Float>) {
        if isAutoCorrecting { return }
        isAutoCorrecting = true
        
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        // 補正実行（現在見ている位置を中心とする）
        calibrateCenter()
        
        // 基準位置を更新（これで「ズレ」状態が解消される）
        lastCalibratedHeadPosition = newPosition
        
        // 控えめな通知メッセージ
        self.statusMessage = "姿勢の変化に合わせて補正しました"
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            if self.statusMessage == "姿勢の変化に合わせて補正しました" {
                self.statusMessage = "" // 非表示にする
                self.isAutoCorrecting = false
            }
        }
    }
    
    // -----------------------------------------------------------
    // MARK: - 閉眼ジェスチャー (手動補正)
    // -----------------------------------------------------------
    
    private func checkEyeGesture(faceAnchor: ARFaceAnchor) {
        let leftBlink = faceAnchor.blendShapes[.eyeBlinkLeft]?.floatValue ?? 0.0
        let rightBlink = faceAnchor.blendShapes[.eyeBlinkRight]?.floatValue ?? 0.0
        
        let isEyesClosed = (leftBlink > blinkThreshold && rightBlink > blinkThreshold)
        
        if isEyesClosed {
            if eyesClosedStartTime == nil { eyesClosedStartTime = Date() }
        } else {
            if let startTime = eyesClosedStartTime {
                let duration = Date().timeIntervalSince(startTime)
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
        
        calibrateCenter()
        
        // 手動時のメッセージ
        self.statusMessage = "補正完了"
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            if self.statusMessage == "補正完了" {
                self.statusMessage = ""
                self.isAutoCorrecting = false
            }
        }
    }
    
    // -----------------------------------------------------------
    // MARK: - 視線計算 & 共通処理 (変更なし)
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

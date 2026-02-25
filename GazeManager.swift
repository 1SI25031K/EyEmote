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

/// 確認（決定）方法: 視線で選んだ後にどのジェスチャーで確定するか
enum DecisionMethod: String, CaseIterable {
    case deepBlink = "Blink for 3 seconds"
    case mouthOpenTwice = "Open Mouth Twice"
    case dwell = "Gaze for 3 seconds"
}

@MainActor
class GazeManager: NSObject, ObservableObject, ARSessionDelegate {
    
    // MARK: - Published Properties
    
    /// 画面上の視線位置 (0.0 - 1.0)
    @Published var cursorRelativePosition: CGPoint = CGPoint(x: 0.5, y: 0.5)
    
    /// 顔認識中かどうか
    @Published var isFaceDetected: Bool = false
    
    /// ステータスメッセージ
    @Published var statusMessage: String = ""
    
    // --- Fluid Soul Features ---
    @Published var dwellTime: TimeInterval = 0.0
    @Published var triggerRipple: Bool = false
    @Published var isAutoCorrecting: Bool = false
    
    // --- Decision Method Selection ---
    /// ユーザーが選択した決定方法（未選択時は nil）
    @Published var selectedDecisionMethod: DecisionMethod?
    /// 決定方法選択画面にいる間 true。この間は Deep Blink でキャリブレーションリセットせず、選択として扱う
    @Published var isInDecisionSelectionPhase: Bool = false
    /// Deep Blink（3秒閉眼）が直前に発生したことを通知。ビューで消費したら false に戻す
    @Published var didPerformDeepBlink: Bool = false
    /// 口を2回開けたジェスチャーが直前に発生したことを通知。ビューで消費したら false に戻す
    @Published var didPerformMouthOpenTwice: Bool = false
    /// 口を開けた回数（0, 1, 2）。5秒以内に2回開けないとリセット。UIのカウンター表示用
    @Published var mouthOpenCount: Int = 0
    
    // --- Sensitivity Settings ---
    @Published var sensitivityX: CGFloat = 2.0
    @Published var sensitivityY: CGFloat = 2.0
    @Published var xOffset: CGFloat = 0.0
    @Published var yOffset: CGFloat = 0.0
    @Published var smoothing: CGFloat = 0.1
    
    // MARK: - Internal Logic Properties
    
    var arSession = ARSession()
    private var rawLookAtPoint: CGPoint = .zero
    
    // For Calibration Calculation
    private var accumulatedSensX: [CGFloat] = []
    private var accumulatedSensY: [CGFloat] = []
    
    // --- 1. Deep Blink (閉眼リセット) ---
    private var eyesClosedStartTime: Date? = nil
    private let blinkThreshold: Float = 0.9
    // ★修正: 3秒に変更
    private let deepBlinkDuration: TimeInterval = 3.0
    
    // --- 2. Head Stability (姿勢自動補正) ---
    private var lastCalibratedHeadPosition: SIMD3<Float>? = nil
    private var lastHeadPosition: SIMD3<Float>? = nil
    private var lastMovementTime: Date = Date()
    private let movementThreshold: Float = 0.05 // 5cm以上のズレで検知開始
    // ★修正: 3秒静止で発動
    private let stabilityDuration: TimeInterval = 3.0
    private var isWaitingForStability: Bool = false
    
    // --- 3. Dwell Detection ---
    private var lastDwellCheckPosition: CGPoint = .zero
    private let dwellDistanceThreshold: CGFloat = 0.05
    
    // --- 4. Mouth Open (2回開けて決定) ---
    private let jawOpenThreshold: Float = 0.25
    private var wasMouthOpen: Bool = false
    private var lastMouthOpenCountIncrementTime: Date = Date()
    private let mouthOpenSequenceTimeout: TimeInterval = 5.0
    
    override init() {
        super.init()
    }
    
    // MARK: - Session Management
    
    func startSession() {
        guard ARFaceTrackingConfiguration.isSupported else {
            statusMessage = "❌ Device not supported"
            return
        }
        let configuration = ARFaceTrackingConfiguration()
        configuration.isLightEstimationEnabled = true
        
        arSession.delegate = self
        arSession.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }
    
    func pauseSession() {
        arSession.pause()
    }
    
    // MARK: - ARSessionDelegate
    
    nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        guard let faceAnchor = anchors.first as? ARFaceAnchor else { return }
        
        Task { @MainActor in
            self.isFaceDetected = true
            
            self.updateGaze(faceAnchor: faceAnchor)
            self.checkHeadStability(faceAnchor: faceAnchor)
            self.detectDeepBlink(faceAnchor: faceAnchor)
            self.detectMouthOpenTwice(faceAnchor: faceAnchor)
        }
    }
    
    // MARK: - 1. Gaze & Dwell Logic (Freeze when eyes closed)
    
    private func updateGaze(faceAnchor: ARFaceAnchor) {
        let leftBlink = faceAnchor.blendShapes[.eyeBlinkLeft]?.floatValue ?? 0.0
        let rightBlink = faceAnchor.blendShapes[.eyeBlinkRight]?.floatValue ?? 0.0
        let isEyesClosed = (leftBlink > blinkThreshold && rightBlink > blinkThreshold)
        
        if isEyesClosed {
            return
        }
        
        let lookAtPoint = faceAnchor.lookAtPoint
        let rawX = CGFloat(lookAtPoint.x)
        let rawY = CGFloat(lookAtPoint.y)
        self.rawLookAtPoint = CGPoint(x: rawX, y: rawY)
        
        let targetX = (rawX * sensitivityX) + xOffset + 0.5
        let targetY = -(rawY * sensitivityY) + yOffset + 0.5
        
        let currentX = cursorRelativePosition.x
        let currentY = cursorRelativePosition.y
        let smoothedX = currentX + (targetX - currentX) * smoothing
        let smoothedY = currentY + (targetY - currentY) * smoothing
        
        let newPos = CGPoint(x: smoothedX, y: smoothedY)
        self.cursorRelativePosition = newPos
        
        let dx = newPos.x - lastDwellCheckPosition.x
        let dy = newPos.y - lastDwellCheckPosition.y
        let distance = sqrt(dx*dx + dy*dy)
        
        if distance < dwellDistanceThreshold {
            self.dwellTime += 0.016
        } else {
            self.dwellTime = 0.0
            self.lastDwellCheckPosition = newPos
        }
    }
    
    // MARK: - 2. Head Stability Logic (姿勢自動補正)
    
    private func checkHeadStability(faceAnchor: ARFaceAnchor) {
        let currentPosition = SIMD3<Float>(
            faceAnchor.transform.columns.3.x,
            faceAnchor.transform.columns.3.y,
            faceAnchor.transform.columns.3.z
        )
        
        // 初回位置記憶
        if lastCalibratedHeadPosition == nil {
            lastCalibratedHeadPosition = currentPosition
            lastHeadPosition = currentPosition
            return
        }
        
        guard let calibratedPos = lastCalibratedHeadPosition else { return }
        let distFromCalibrated = simd_distance(currentPosition, calibratedPos)
        
        // 基準点から大きく(5cm以上)ズレているか？
        if distFromCalibrated > movementThreshold {
            isWaitingForStability = true
            
            // 直前のフレームからも動いているか？（現在進行形で動いているか）
            if let lastFramePos = lastHeadPosition {
                let distFromLastFrame = simd_distance(currentPosition, lastFramePos)
                // 5mm以上動いていれば「まだ動いている」とみなしてタイマーリセット
                if distFromLastFrame > 0.005 {
                    lastMovementTime = Date()
                }
            }
        } else {
            // 元の位置に戻った、あるいはズレていない
            isWaitingForStability = false
            lastMovementTime = Date()
        }
        
        // 静止時間の判定
        if isWaitingForStability {
            let timeSinceMove = Date().timeIntervalSince(lastMovementTime)
            
            // 3秒間静止したら補正実行
            if timeSinceMove >= stabilityDuration {
                performAutoCorrection(newHeadPosition: currentPosition)
                isWaitingForStability = false
                lastMovementTime = Date()
            }
        }
        
        lastHeadPosition = currentPosition
    }
    
    private func performAutoCorrection(newHeadPosition: SIMD3<Float>) {
        if isAutoCorrecting { return }
        isAutoCorrecting = true
        
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
        
        // ※ここでは視線の中心リセット(calibrateCenter)は行わず、
        // 「頭の基準位置」だけを更新する（ソフト補正）
        // ユーザーがどこを見ているか不明なため、視線オフセットまでいじると危険なため。
        lastCalibratedHeadPosition = newHeadPosition
        
        self.statusMessage = "Adjusted for posture change"
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            if self.statusMessage == "Adjusted for posture change" {
                self.statusMessage = ""
                self.isAutoCorrecting = false
            }
        }
    }
    
    // MARK: - 3. Deep Blink Logic (3秒閉眼リセット)
    
    private func detectDeepBlink(faceAnchor: ARFaceAnchor) {
        let leftBlink = faceAnchor.blendShapes[.eyeBlinkLeft]?.floatValue ?? 0.0
        let rightBlink = faceAnchor.blendShapes[.eyeBlinkRight]?.floatValue ?? 0.0
        
        let isEyesClosed = (leftBlink > blinkThreshold && rightBlink > blinkThreshold)
        
        if isEyesClosed {
            if eyesClosedStartTime == nil { eyesClosedStartTime = Date() }
        } else {
            if let start = eyesClosedStartTime {
                let duration = Date().timeIntervalSince(start)
                if duration >= deepBlinkDuration {
                    if isInDecisionSelectionPhase {
                        didPerformDeepBlink = true
                    } else {
                        performManualReset()
                    }
                }
                eyesClosedStartTime = nil
            }
        }
    }
    
    // MARK: - 4. Mouth Open Twice (5s timeout after first open)
    
    private func detectMouthOpenTwice(faceAnchor: ARFaceAnchor) {
        if mouthOpenCount >= 1 && Date().timeIntervalSince(lastMouthOpenCountIncrementTime) > mouthOpenSequenceTimeout {
            mouthOpenCount = 0
        }
        
        let jawOpen = faceAnchor.blendShapes[.jawOpen]?.floatValue ?? 0.0
        let isMouthOpen = jawOpen > jawOpenThreshold
        
        if isMouthOpen {
            wasMouthOpen = true
        } else {
            if wasMouthOpen {
                mouthOpenCount += 1
                lastMouthOpenCountIncrementTime = Date()
                if mouthOpenCount >= 2 {
                    didPerformMouthOpenTwice = true
                    mouthOpenCount = 0
                }
            }
            wasMouthOpen = false
        }
    }
    
    private func performManualReset() {
        if isAutoCorrecting { return }
        isAutoCorrecting = true
        
        // 中心リセット実行
        calibrateCenter()
        
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        self.statusMessage = "Recalibrated via Deep Blink"
        withAnimation { self.triggerRipple.toggle() }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            if self.statusMessage == "Recalibrated via Deep Blink" {
                self.statusMessage = ""
                self.isAutoCorrecting = false
            }
        }
    }
    
    // MARK: - Calibration Helpers
    
    func getCurrentRaw() -> CGPoint { return rawLookAtPoint }
    
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
        
        if abs(rawDeltaX) > 0.01 { accumulatedSensX.append(abs(screenDeltaX / rawDeltaX)) }
        if abs(rawDeltaY) > 0.01 { accumulatedSensY.append(abs(screenDeltaY / rawDeltaY)) }
        
        if !accumulatedSensX.isEmpty { self.sensitivityX = accumulatedSensX.reduce(0, +) / CGFloat(accumulatedSensX.count) }
        if !accumulatedSensY.isEmpty { self.sensitivityY = accumulatedSensY.reduce(0, +) / CGFloat(accumulatedSensY.count) }
        
        self.xOffset = -(centerRaw.x * sensitivityX)
        self.yOffset = (centerRaw.y * sensitivityY)
    }
}

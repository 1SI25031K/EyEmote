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

/// How to confirm a selection: which gesture commits the choice made by gaze.
enum DecisionMethod: String, CaseIterable {
    case deepBlink = "Blink for 3 seconds"
    case mouthOpenTwice = "Open Mouth Twice"
    case dwell = "Gaze for 3 seconds"
}

/// Visual material of the Soul Shape chosen in TextureSelectionView.
enum SoulTexture: String, CaseIterable {
    case glossy = "Glossy"
    case frosted = "Frosted"
    case metallic = "Metallic"
    case pearlescent = "Pearlescent"
    case iridescent = "Iridescent"
    case deepLiquid = "Deep Liquid"
}

/// Geometry of the Soul Shape chosen in ShapeSelectionView.
enum SoulShape: String, CaseIterable {
    case circle = "Circle"
    case squircle = "Squircle"
    case softBlob = "Soft Blob"
    case capsule = "Capsule"
    case diamond = "Diamond"
    case flowerStar = "Flower"
}

@MainActor
class GazeManager: NSObject, ObservableObject, ARSessionDelegate {
    
    // MARK: - Published Properties
    
    /// Cursor position on screen in relative coordinates (0.0 - 1.0).
    @Published var cursorRelativePosition: CGPoint = CGPoint(x: 0.5, y: 0.5)
    
    /// Whether a face is currently detected.
    @Published var isFaceDetected: Bool = false
    
    /// Status message for Liquid Glass feedback.
    @Published var statusMessage: String = ""
    
    // --- Fluid Soul Features ---
    @Published var dwellTime: TimeInterval = 0.0
    @Published var triggerRipple: Bool = false
    @Published var isAutoCorrecting: Bool = false
    
    // --- Decision Method Selection ---
    /// User-selected decision method (nil when not yet chosen).
    @Published var selectedDecisionMethod: DecisionMethod?
    /// True while on decision-method selection screen; Deep Blink is treated as selection, not calibration reset.
    @Published var isInDecisionSelectionPhase: Bool = false
    /// Set when a Deep Blink (3 s eyes closed) just occurred; views consume and reset to false.
    @Published var didPerformDeepBlink: Bool = false
    /// Set when mouth-open-twice gesture just occurred; views consume and reset to false.
    @Published var didPerformMouthOpenTwice: Bool = false
    /// Mouth-open count (0, 1, 2); resets if second open is not within 5 s. Used for UI counter.
    @Published var mouthOpenCount: Int = 0
    
    /// Color chosen in EyEPencil selection (or previous feeling picker). Set when user confirms a pencil.
    @Published var decidedColor: Color?
    
    /// Opacity (alpha) chosen in OpacitySelectionView. Range 0...1. Set when user confirms a tile.
    @Published var selectedAlpha: Double = 1.0
    
    /// Texture (material) chosen in TextureSelectionView.
    @Published var selectedTexture: SoulTexture = .glossy
    
    /// Geometry chosen in ShapeSelectionView.
    @Published var selectedShape: SoulShape = .circle
    
    // --- Sensitivity Settings ---
    @Published var sensitivityX: CGFloat = 2.0
    @Published var sensitivityY: CGFloat = 2.0
    @Published var xOffset: CGFloat = 0.0
    @Published var yOffset: CGFloat = 0.0
    @Published var smoothing: CGFloat = 0.1
    
    /// When true (e.g. during EyE Shape Sculpting), heavier smoothing is applied for a stable, less jittery cursor.
    @Published var isSculptingMode: Bool = false
    
    /// Smoothing factor used in Sculpting mode (lower = heavier, more stable cursor).
    private let sculptingSmoothing: CGFloat = 0.045
    
    // MARK: - Internal Logic Properties
    
    var arSession = ARSession()
    private var rawLookAtPoint: CGPoint = .zero
    
    // For Calibration Calculation
    private var accumulatedSensX: [CGFloat] = []
    private var accumulatedSensY: [CGFloat] = []
    
    // --- 1. Deep Blink (eyes-closed reset) ---
    private var eyesClosedStartTime: Date? = nil
    private let blinkThreshold: Float = 0.9
    private let deepBlinkDuration: TimeInterval = 3.0
    
    // --- 2. Head Stability (posture auto-correction) ---
    private var lastCalibratedHeadPosition: SIMD3<Float>? = nil
    private var lastHeadPosition: SIMD3<Float>? = nil
    private var lastMovementTime: Date = Date()
    /// Head must move beyond this distance (meters) from calibrated position to start waiting for stability.
    private let movementThreshold: Float = 0.05  // 5 cm
    /// Frame-to-frame movement above this (meters) resets the stability timer during the waiting period.
    private let movementResetThreshold: Float = 0.005  // 5 mm
    /// Uninterrupted stability duration (seconds) required before triggering auto-correction.
    private let stabilityDuration: TimeInterval = 3.0
    private var isWaitingForStability: Bool = false
    
    // --- 3. Dwell Detection ---
    private var lastDwellCheckPosition: CGPoint = .zero
    private let dwellDistanceThreshold: CGFloat = 0.05
    
    // --- 4. Mouth Open (open twice to confirm) ---
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
    
    /// Heavier smoothing in Sculpting mode for a stable cursor and less jitter during shape sculpting.
    private var effectiveSmoothing: CGFloat { isSculptingMode ? sculptingSmoothing : smoothing }
    
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
        let smooth = effectiveSmoothing
        let smoothedX = currentX + (targetX - currentX) * smooth
        let smoothedY = currentY + (targetY - currentY) * smooth
        
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
    
    // MARK: - 2. Head Stability Logic (posture auto-correction)
    
    /// When head moves beyond `movementThreshold` (5 cm) from the calibrated position and then
    /// remains stable (frame-to-frame movement < 5 mm) for a full `stabilityDuration` (3 s),
    /// triggers a soft auto-correction so the app adapts to the new posture (closing the inclusion gap).
    private func checkHeadStability(faceAnchor: ARFaceAnchor) {
        let currentPosition = SIMD3<Float>(
            faceAnchor.transform.columns.3.x,
            faceAnchor.transform.columns.3.y,
            faceAnchor.transform.columns.3.z
        )
        
        if lastCalibratedHeadPosition == nil {
            lastCalibratedHeadPosition = currentPosition
            lastHeadPosition = currentPosition
            return
        }
        
        guard let calibratedPos = lastCalibratedHeadPosition else { return }
        let distFromCalibrated = simd_distance(currentPosition, calibratedPos)
        
        if distFromCalibrated > movementThreshold {
            isWaitingForStability = true
            
            if let lastFramePos = lastHeadPosition {
                let distFromLastFrame = simd_distance(currentPosition, lastFramePos)
                if distFromLastFrame > movementResetThreshold {
                    lastMovementTime = Date()
                }
            } else {
                lastMovementTime = Date()
            }
        } else {
            isWaitingForStability = false
            lastMovementTime = Date()
        }
        
        if isWaitingForStability {
            let timeSinceMove = Date().timeIntervalSince(lastMovementTime)
            if timeSinceMove >= stabilityDuration {
                performAutoCorrection(newHeadPosition: currentPosition)
                isWaitingForStability = false
                lastMovementTime = Date()
            }
        }
        
        lastHeadPosition = currentPosition
    }
    
    /// Updates the calibrated head reference to the current position (soft correction).
    /// Does not change gaze offset, so cursor mapping remains safe.
    private func performAutoCorrection(newHeadPosition: SIMD3<Float>) {
        if isAutoCorrecting { return }
        isAutoCorrecting = true
        
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
        
        lastCalibratedHeadPosition = newHeadPosition
        
        self.statusMessage = "Adjusted for posture change"
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            if self.statusMessage == "Adjusted for posture change" {
                self.statusMessage = ""
                self.isAutoCorrecting = false
            }
        }
    }
    
    // MARK: - 3. Deep Blink Logic (3 s eyes-closed reset)
    
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
        
        if let currentFrame = arSession.currentFrame,
           let anchor = currentFrame.anchors.first(where: { $0 is ARFaceAnchor }) {
            let transform = anchor.transform.columns.3
            self.lastCalibratedHeadPosition = SIMD3<Float>(transform.x, transform.y, transform.z)
        }
    }
    
    /// Updates sensitivity and offset from one 12-point calibration sample.
    /// Maps ARKit lookAtPoint (face-relative) to screen space (0–1): target = (raw * sensitivity) + offset + 0.5 (Y negated).
    /// Uses trimmed mean over accumulated samples to reduce impact of outliers.
    func calibrateSensitivity(lookingAt targetPoint: CGPoint, centerRaw: CGPoint) {
        let screenDeltaX = targetPoint.x - 0.5
        let screenDeltaY = targetPoint.y - 0.5
        let rawDeltaX = rawLookAtPoint.x - centerRaw.x
        let rawDeltaY = rawLookAtPoint.y - centerRaw.y
        
        let minRawDelta: CGFloat = 0.01
        if abs(rawDeltaX) > minRawDelta {
            accumulatedSensX.append(abs(screenDeltaX / rawDeltaX))
        }
        if abs(rawDeltaY) > minRawDelta {
            accumulatedSensY.append(abs(screenDeltaY / rawDeltaY))
        }
        
        if !accumulatedSensX.isEmpty {
            self.sensitivityX = trimmedMean(accumulatedSensX, trimRatio: 0.25)
        }
        if !accumulatedSensY.isEmpty {
            self.sensitivityY = trimmedMean(accumulatedSensY, trimRatio: 0.25)
        }
        
        self.xOffset = -(centerRaw.x * sensitivityX)
        self.yOffset = (centerRaw.y * sensitivityY)
    }
    
    /// Trimmed mean: sort, drop top and bottom `trimRatio` fraction, average the middle. Reduces outlier impact.
    private func trimmedMean(_ values: [CGFloat], trimRatio: CGFloat) -> CGFloat {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let count = sorted.count
        let drop = Int(CGFloat(count) * trimRatio)
        let start = min(drop, count - 1)
        let end = max(count - drop, start + 1)
        let slice = sorted[start..<end]
        return slice.reduce(0, +) / CGFloat(slice.count)
    }
}

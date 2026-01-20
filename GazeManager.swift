//
//  GazeManager.swift
//  EyEmote
//
//  Created by Kosei Miyamoto on 2026/01/20.
//

import SwiftUI
import ARKit
import Combine

@MainActor // UIに関連するクラスであることを明示
class GazeManager: NSObject, ObservableObject, ARSessionDelegate {
    // 0.0〜1.0 の相対座標で保持する (画面サイズに依存させない)
    @Published var cursorRelativePosition: CGPoint = CGPoint(x: 0.5, y: 0.5)
    @Published var isFaceDetected: Bool = false
    
    private var arSession = ARSession()
    private let smoothingFactor: CGFloat = 0.1
    
    override init() {
        super.init()
        setupAR()
    }
    
    private func setupAR() {
        guard ARFaceTrackingConfiguration.isSupported else { return }
        let configuration = ARFaceTrackingConfiguration()
        configuration.isLightEstimationEnabled = true
        
        arSession.delegate = self
        arSession.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }
    
    // ARKitからの呼び出しはバックグラウンドで来る可能性があるため 'nonisolated' にする
    nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        guard let faceAnchor = anchors.first as? ARFaceAnchor else { return }
        
        // データを受け取ったら、メインスレッドに戻って処理する
        Task { @MainActor in
            self.isFaceDetected = true
            self.updateGaze(faceAnchor: faceAnchor)
        }
    }
    
    private func updateGaze(faceAnchor: ARFaceAnchor) {
        let lookAtPoint = faceAnchor.lookAtPoint
        
        // 感度調整 (値を大きくすると少しの動きで端まで届く)
        let sensitivity: CGFloat = 4.0
        let x = CGFloat(lookAtPoint.x) * sensitivity
        let y = CGFloat(-lookAtPoint.y) * sensitivity
        
        // 0.0 〜 1.0 の範囲に正規化
        let targetX = (x + 0.5)
        let targetY = (y + 0.5)
        
        // スムージング処理
        let currentX = cursorRelativePosition.x
        let currentY = cursorRelativePosition.y
        
        let smoothedX = currentX + (targetX - currentX) * smoothingFactor
        let smoothedY = currentY + (targetY - currentY) * smoothingFactor
        
        self.cursorRelativePosition = CGPoint(x: smoothedX, y: smoothedY)
    }
}

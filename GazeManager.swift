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
    // 画面上の相対位置 (0.0〜1.0)
    @Published var cursorRelativePosition: CGPoint = CGPoint(x: 0.5, y: 0.5)
    @Published var isFaceDetected: Bool = false
    @Published var statusMessage: String = "起動中..."
    
    // --- 設定・キャリブレーション用パラメータ ---
    @Published var sensitivity: CGFloat = 2.5     // 感度 (高いほど少しの目の動きで大きく動く)
    @Published var xOffset: CGFloat = 0.0         // X軸のズレ補正
    @Published var yOffset: CGFloat = 0.0         // Y軸のズレ補正
    @Published var swapAxes: Bool = false         // 縦横の軸を入れ替えるか (横持ち対策)
    @Published var invertX: Bool = false          // X軸を反転するか
    @Published var invertY: Bool = false          // Y軸を反転するか
    @Published var smoothing: CGFloat = 0.1       // スムージング係数
    
    var arSession = ARSession()
    
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
    
    // 現在見ている位置を「画面中央」として設定する
    func calibrateCenter() {
        // 現在の「生の視線データ」をオフセットとして保存することで、
        // (生データ - オフセット) = 0 (つまり中央) になるようにする
        // ※ここでは簡易的に現在のカーソル位置をリセットするロジック
        // 本来は生のlookAtPointを保存すべきですが、簡易実装としてオフセットを調整します
        xOffset = -lastRawX
        yOffset = -lastRawY
    }
    
    // 内部計算用の生データ保持
    private var lastRawX: CGFloat = 0
    private var lastRawY: CGFloat = 0
    
    nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        guard let faceAnchor = anchors.first as? ARFaceAnchor else { return }
        Task { @MainActor in
            self.isFaceDetected = true
            self.updateGaze(faceAnchor: faceAnchor)
        }
    }
    
    private func updateGaze(faceAnchor: ARFaceAnchor) {
        // ARKitの視線ベクトル (顔正面がZ+, 右がX+, 上がY+)
        let lookAtPoint = faceAnchor.lookAtPoint
        
        // 1. 基本の座標変換
        var rawX = CGFloat(lookAtPoint.x)
        var rawY = CGFloat(lookAtPoint.y)
        
        // 2. 軸の入れ替え (iPadの向き対策)
        if swapAxes {
            let temp = rawX
            rawX = rawY
            rawY = temp
        }
        
        // 3. 反転処理
        if invertX { rawX = -rawX }
        if invertY { rawY = -rawY }
        
        // 生データを保存 (キャリブレーション用)
        // ※感度を掛ける前の値だと小さすぎるので、感度考慮前の「方向」として扱うか、
        // ここではシンプルに感度適用後の値を基準にオフセット計算させます
        self.lastRawX = rawX * sensitivity
        self.lastRawY = rawY * sensitivity // Yは通常ARKitでは上がプラス
        
        // 4. 感度とオフセットの適用
        // ARKitの座標系: Yが上。画面座標系: Yが下。なのでYはマイナスを掛けるのが基本
        let finalX = (rawX * sensitivity) + xOffset
        let finalY = -(rawY * sensitivity) + yOffset // ここでY軸反転が標準
        
        // 5. 画面中央 (0.5) を基準にマッピング
        let targetX = finalX + 0.5
        let targetY = finalY + 0.5
        
        // 6. スムージング (手ぶれ補正)
        let currentX = cursorRelativePosition.x
        let currentY = cursorRelativePosition.y
        let smoothedX = currentX + (targetX - currentX) * smoothing
        let smoothedY = currentY + (targetY - currentY) * smoothing
        
        self.cursorRelativePosition = CGPoint(x: smoothedX, y: smoothedY)
    }
}

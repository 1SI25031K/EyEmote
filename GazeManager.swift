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
    // -----------------------------------------------------------
    // MARK: - 公開プロパティ (Published Properties)
    // -----------------------------------------------------------
    
    // 画面上のカーソル位置 (0.0〜1.0 の相対座標)
    @Published var cursorRelativePosition: CGPoint = CGPoint(x: 0.5, y: 0.5)
    
    // 顔が認識されているか
    @Published var isFaceDetected: Bool = false
    
    // デバッグ・ステータス表示用メッセージ
    @Published var statusMessage: String = "起動中..."
    
    // --- 設定値 (自動計算されますが、手動変更も可能) ---
    @Published var sensitivityX: CGFloat = 2.0 // X軸感度
    @Published var sensitivityY: CGFloat = 2.0 // Y軸感度
    @Published var xOffset: CGFloat = 0.0      // X軸中心ズレ補正
    @Published var yOffset: CGFloat = 0.0      // Y軸中心ズレ補正
    
    // --- 手動調整用オプション (必要に応じて使用) ---
    @Published var swapAxes: Bool = false      // 縦横の軸を入れ替えるか
    @Published var invertX: Bool = false       // X軸を反転するか
    @Published var invertY: Bool = false       // Y軸を反転するか
    
    // --- 挙動設定 ---
    @Published var smoothing: CGFloat = 0.1    // スムージング係数 (0.01〜1.0, 小さいほど滑らかだが遅延する)
    
    // -----------------------------------------------------------
    // MARK: - 内部プロパティ
    // -----------------------------------------------------------
    
    var arSession = ARSession()
    
    // 生データ保持用 (キャリブレーション計算に使用)
    private var rawLookAtPoint: CGPoint = .zero
    
    // 感度平均化のための蓄積配列
    private var accumulatedSensX: [CGFloat] = []
    private var accumulatedSensY: [CGFloat] = []
    
    // -----------------------------------------------------------
    // MARK: - 初期化 & ARセットアップ
    // -----------------------------------------------------------
    
    override init() {
        super.init()
        setupAR()
    }
    
    private func setupAR() {
        guard ARFaceTrackingConfiguration.isSupported else {
            statusMessage = "❌ このデバイスはFace ID(視線追跡)に対応していません"
            return
        }
        
        let configuration = ARFaceTrackingConfiguration()
        configuration.isLightEstimationEnabled = true
        
        // 既存のアンカーを削除してクリーンスタート
        arSession.delegate = self
        arSession.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        statusMessage = "カメラ起動完了"
    }
    
    // -----------------------------------------------------------
    // MARK: - ARSessionDelegate (更新ループ)
    // -----------------------------------------------------------
    
    // ARKitはバックグラウンドスレッドで呼ばれるため nonisolated
    nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        guard let faceAnchor = anchors.first as? ARFaceAnchor else { return }
        
        // UI更新のためにMainActorへ戻す
        Task { @MainActor in
            self.isFaceDetected = true
            self.updateGaze(faceAnchor: faceAnchor)
        }
    }
    
    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        Task { @MainActor in
            self.statusMessage = "エラー: \(error.localizedDescription)"
        }
    }
    
    // -----------------------------------------------------------
    // MARK: - 視線計算ロジック
    // -----------------------------------------------------------
    
    private func updateGaze(faceAnchor: ARFaceAnchor) {
        // 1. ARKitからの視線ベクトル取得 (右手がX+, 頭上がY+)
        let lookAtPoint = faceAnchor.lookAtPoint
        
        // 2. 基本変換 & 軸操作 (iPadの向き対策)
        var rawX = CGFloat(lookAtPoint.x)
        var rawY = CGFloat(lookAtPoint.y)
        
        if swapAxes {
            let temp = rawX
            rawX = rawY
            rawY = temp
        }
        
        if invertX { rawX = -rawX }
        if invertY { rawY = -rawY }
        
        // 生データを保存 (キャリブレーション計算用)
        self.rawLookAtPoint = CGPoint(x: rawX, y: rawY)
        
        // 3. 感度とオフセットの適用
        // 変換式: Target = (Raw * Sensitivity) + Offset + 0.5(画面中央)
        // ※ Y軸はARKit(上+)と画面座標(下+)で逆なので、Y感度適用時にマイナスをかけるのが基本
        let targetX = (rawX * sensitivityX) + xOffset + 0.5
        let targetY = -(rawY * sensitivityY) + yOffset + 0.5
        
        // 4. スムージング (手ブレ補正)
        // 現在位置から目標位置へ少しずつ近づける (線形補間)
        let currentX = cursorRelativePosition.x
        let currentY = cursorRelativePosition.y
        
        let smoothedX = currentX + (targetX - currentX) * smoothing
        let smoothedY = currentY + (targetY - currentY) * smoothing
        
        // 5. 反映
        self.cursorRelativePosition = CGPoint(x: smoothedX, y: smoothedY)
    }
    
    // -----------------------------------------------------------
    // MARK: - 自動キャリブレーション機能
    // -----------------------------------------------------------
    
    // 外部から現在の生データを取得するヘルパー
    func getCurrentRaw() -> CGPoint {
        return rawLookAtPoint
    }
    
    // ステップ1: 中央を見た時の値を記録（オフセット計算）
    func calibrateCenter() {
        // 中央設定時は、以前の蓄積データをクリアしてリセット
        accumulatedSensX = []
        accumulatedSensY = []
        
        // 現在の生データが「画面中央(0.0)」になるようにオフセットを設定
        // 0 = (Raw * Sens) + Offset  =>  Offset = -(Raw * Sens)
        self.xOffset = -(rawLookAtPoint.x * sensitivityX)
        // Y軸は反転しているので符号に注意: 0 = -(Raw * Sens) + Offset => Offset = (Raw * Sens)
        self.yOffset = (rawLookAtPoint.y * sensitivityY)
    }
    
    // ステップ2〜5: 四隅を見た時の値から感度を計算し、平均をとる
    // targetPoint: 画面上の目標座標 (0.0〜1.0)
    // centerRaw: ステップ1で記録した中央の生データ
    func calibrateSensitivity(lookingAt targetPoint: CGPoint, centerRaw: CGPoint) {
        // 画面上の移動距離 (例: 中央0.5 から 左上0.1 への距離 = -0.4)
        let screenDeltaX = targetPoint.x - 0.5
        let screenDeltaY = targetPoint.y - 0.5
        
        // 生データ上の移動距離
        let rawDeltaX = rawLookAtPoint.x - centerRaw.x
        let rawDeltaY = rawLookAtPoint.y - centerRaw.y
        
        // X軸の感度計算 (移動量が少なすぎる場合はノイズとして無視)
        if abs(rawDeltaX) > 0.01 {
            // 感度 = 画面移動量 / 生データ移動量 (絶対値)
            let newSensX = abs(screenDeltaX / rawDeltaX)
            accumulatedSensX.append(newSensX)
        }
        
        // Y軸の感度計算
        if abs(rawDeltaY) > 0.01 {
            // Y軸は反転しているので絶対値で大きさだけを見る
            let newSensY = abs(screenDeltaY / rawDeltaY)
            accumulatedSensY.append(newSensY)
        }
        
        // 平均値を適用 (これにより、1回の誤検出で極端な感度になるのを防ぐ)
        if !accumulatedSensX.isEmpty {
            let avgX = accumulatedSensX.reduce(0, +) / CGFloat(accumulatedSensX.count)
            self.sensitivityX = avgX
        }
        
        if !accumulatedSensY.isEmpty {
            let avgY = accumulatedSensY.reduce(0, +) / CGFloat(accumulatedSensY.count)
            self.sensitivityY = avgY
        }
        
        // 重要: 感度(Sensitivity)が変わると、基準点(Offset)の計算結果も変わるため再計算する
        // Offset = -(RawCenter * NewSens)
        self.xOffset = -(centerRaw.x * sensitivityX)
        self.yOffset = (centerRaw.y * sensitivityY)
    }
}

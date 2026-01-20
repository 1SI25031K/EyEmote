import SwiftUI
import ARKit

struct ContentView: View {
    @StateObject private var gazeManager = GazeManager()
    @State private var showSettings = false // 設定画面の表示フラグ
    @State private var selectedItem: String = "準備完了"
    
    let columns = [GridItem(.flexible()), GridItem(.flexible())]
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 背景カメラ
                ARCameraView(session: gazeManager.arSession)
                    .ignoresSafeArea()
                    .opacity(0.3)
                
                VStack {
                    // --- ヘッダー & 設定ボタン ---
                    HStack {
                        Button(action: { showSettings.toggle() }) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.title)
                                .padding()
                                .background(.thinMaterial)
                                .clipShape(Circle())
                        }
                        Spacer()
                        Text("Eye Control")
                            .font(.headline)
                            .foregroundColor(.white)
                        Spacer()
                        // リセット（キャリブレーション）ボタン
                        Button(action: { gazeManager.calibrateCenter() }) {
                            Image(systemName: "scope")
                                .font(.title)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .clipShape(Circle())
                        }
                    }
                    .padding()
                    
                    Spacer()
                    
                    // --- メインコンテンツ ---
                    if showSettings {
                        // 設定パネル（操作しづらい時はここを開いて調整）
                        SettingsView(manager: gazeManager)
                            .frame(maxWidth: 400)
                            .background(.ultraThinMaterial)
                            .cornerRadius(20)
                            .padding()
                    } else {
                        // 通常のボタンエリア
                        LazyVGrid(columns: columns, spacing: 30) {
                            let cursor = CGPoint(
                                x: gazeManager.cursorRelativePosition.x * geometry.size.width,
                                y: gazeManager.cursorRelativePosition.y * geometry.size.height
                            )
                            
                            GazeButton(title: "Like", icon: "hand.thumbsup.fill", action: { selectedItem = "いいね！" }, cursorPosition: cursor)
                            GazeButton(title: "Play", icon: "play.circle.fill", action: { selectedItem = "再生中" }, cursorPosition: cursor)
                            GazeButton(title: "Next", icon: "forward.fill", action: { selectedItem = "次へ" }, cursorPosition: cursor)
                            GazeButton(title: "Menu", icon: "list.bullet", action: { selectedItem = "メニュー" }, cursorPosition: cursor)
                        }
                        .padding(40)
                    }
                    
                    Spacer()
                    
                    Text(selectedItem)
                        .font(.largeTitle)
                        .bold()
                        .foregroundColor(.white)
                        .padding()
                }
                
                // --- カーソル ---
                if gazeManager.isFaceDetected {
                    GazeCursorView(
                        position: CGPoint(
                            x: gazeManager.cursorRelativePosition.x * geometry.size.width,
                            y: gazeManager.cursorRelativePosition.y * geometry.size.height
                        )
                    )
                }
            }
        }
    }
}

// 設定調整用のサブビュー
struct SettingsView: View {
    @ObservedObject var manager: GazeManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("調整設定 (Calibration)").font(.headline)
            
            VStack(alignment: .leading) {
                Text("感度 (Sensitivity): \(String(format: "%.1f", manager.sensitivity))")
                Slider(value: $manager.sensitivity, in: 1.0...10.0)
            }
            
            VStack(alignment: .leading) {
                Text("滑らかさ (Smoothing): \(String(format: "%.2f", manager.smoothing))")
                Slider(value: $manager.smoothing, in: 0.01...0.3)
            }
            
            Divider()
            
            Toggle("軸の入れ替え (iPad横向き用)", isOn: $manager.swapAxes)
            Toggle("X軸反転 (左右)", isOn: $manager.invertX)
            Toggle("Y軸反転 (上下)", isOn: $manager.invertY)
            
            Divider()
            
            Text("使い方:")
                .font(.caption)
            Text("1. 画面中央の青い的を見て、右上の「スコープボタン」を押すとズレが直ります。\n2. カーソルの動きが変な場合は「軸の入れ替え」や「反転」を試してください。")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

// カメラ表示用のコンポーネント（変更なしなら以前のままでOKですが再掲）
struct ARCameraView: UIViewRepresentable {
    let session: ARSession
    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.session = session
        view.automaticallyUpdatesLighting = true
        return view
    }
    func updateUIView(_ uiView: ARSCNView, context: Context) {}
}

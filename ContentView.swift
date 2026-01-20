import SwiftUI
import ARKit

struct ContentView: View {
    @StateObject private var gazeManager = GazeManager()
    @State private var selectedItem: String = "準備完了"
    @State private var needsCalibration: Bool = true // 初回キャリブレーションフラグ
    
    let columns = [GridItem(.flexible()), GridItem(.flexible())]
    
    var body: some View {
        ZStack {
            // メインアプリ画面
            GeometryReader { geometry in
                ZStack {
                    ARCameraView(session: gazeManager.arSession)
                        .ignoresSafeArea()
                        .opacity(0.3)
                    
                    VStack {
                        // ヘッダー
                        HStack {
                            // 再調整ボタン
                            Button(action: { needsCalibration = true }) {
                                Image(systemName: "scope")
                                    .padding()
                                    .background(.thinMaterial)
                                    .clipShape(Circle())
                            }
                            Spacer()
                            Text(selectedItem)
                                .font(.title2).bold().foregroundColor(.white)
                            Spacer()
                        }
                        .padding()
                        
                        Spacer()
                        
                        // コンテンツグリッド
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
                        
                        Spacer()
                    }
                    
                    // カーソル
                    if gazeManager.isFaceDetected && !needsCalibration {
                        GazeCursorView(
                            position: CGPoint(
                                x: gazeManager.cursorRelativePosition.x * geometry.size.width,
                                y: gazeManager.cursorRelativePosition.y * geometry.size.height
                            )
                        )
                    }
                }
            }
            
            // キャリブレーション画面を最前面にオーバーレイ
            if needsCalibration {
                CalibrationView(gazeManager: gazeManager) {
                    // 完了時のコールバック
                    withAnimation {
                        needsCalibration = false
                    }
                }
                .transition(.opacity)
                .zIndex(100)
            }
        }
    }
}

// ContentView structの閉じカッコ「}」の外側に追加してください

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

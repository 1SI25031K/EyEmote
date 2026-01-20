import SwiftUI
import ARKit

struct ContentView: View {
    @StateObject private var gazeManager = GazeManager()
    @State private var selectedItem: String = "準備完了"
    
    // 状態管理フラグ
    @State private var isSplashing: Bool = true // 起動画面
    @State private var needsCalibration: Bool = false // キャリブレーション
    
    let columns = [GridItem(.flexible()), GridItem(.flexible())]
    
    var body: some View {
        ZStack {
            GeometryReader { geometry in
                ZStack {
                    // ARカメラ映像
                    // Splash中は非表示にして、文章に集中させる
                    if !isSplashing {
                        ARCameraView(session: gazeManager.arSession)
                            .ignoresSafeArea()
                            .opacity(0.3)
                            .transition(.opacity) // ふわっと表示
                    }
                    
                    VStack {
                        // メインアプリのヘッダー
                        HStack {
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
                        .padding(.top, 40)
                        
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
                    if gazeManager.isFaceDetected && !needsCalibration && !isSplashing {
                        GazeCursorView(
                            position: CGPoint(
                                x: gazeManager.cursorRelativePosition.x * geometry.size.width,
                                y: gazeManager.cursorRelativePosition.y * geometry.size.height
                            )
                        )
                    }
                }
            }
            // 通知バナー (Overlay)
            .overlay(alignment: .bottom) {
                if !gazeManager.statusMessage.isEmpty && !isSplashing {
                    Text(gazeManager.statusMessage)
                        .font(.subheadline).fontWeight(.medium)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(.ultraThinMaterial).background(Color.black.opacity(0.4))
                        .foregroundColor(.white).clipShape(Capsule()).shadow(radius: 4)
                        .padding(.bottom, 50)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                        .animation(.easeInOut, value: gazeManager.statusMessage)
                }
            }
            
            // 2. キャリブレーション画面
            if needsCalibration {
                CalibrationView(gazeManager: gazeManager) {
                    withAnimation { needsCalibration = false }
                }
                .transition(.opacity)
                .zIndex(100)
            }
            
            // 1. 起動画面 (Splash) - 最前面
            if isSplashing {
                SplashView {
                    // 10秒経過後
                    withAnimation(.easeOut(duration: 1.0)) {
                        isSplashing = false
                        needsCalibration = true // 次はキャリブレーションへ
                    }
                }
                .zIndex(200)
                .transition(.opacity)
            }
        }
    }
}

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

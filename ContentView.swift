import SwiftUI
import ARKit

struct ContentView: View {
    @StateObject private var gazeManager = GazeManager()
    @State private var selectedItem: String = "準備完了"
    @State private var needsCalibration: Bool = true
    
    let columns = [GridItem(.flexible()), GridItem(.flexible())]
    
    var body: some View {
        ZStack {
            GeometryReader { geometry in
                ZStack {
                    ARCameraView(session: gazeManager.arSession)
                        .ignoresSafeArea()
                        .opacity(0.3)
                    
                    VStack {
                        // ヘッダー (レイアウトシフトしない固定配置)
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
            // ★修正: 通知を「画面下部」に「控えめ」に表示 (Overlay)
            .overlay(alignment: .bottom) {
                if !gazeManager.statusMessage.isEmpty {
                    Text(gazeManager.statusMessage)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial) // すりガラス風
                        .background(Color.black.opacity(0.4))
                        .foregroundColor(.white)
                        .clipShape(Capsule()) // 角丸のカプセル型
                        .shadow(radius: 4)
                        .padding(.bottom, 50) // 下から少し浮かせる
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                        .animation(.easeInOut, value: gazeManager.statusMessage)
                }
            }
            
            // キャリブレーション画面
            if needsCalibration {
                CalibrationView(gazeManager: gazeManager) {
                    withAnimation { needsCalibration = false }
                }
                .transition(.opacity)
                .zIndex(100)
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

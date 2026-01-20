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
                        // ヘッダー (通知バーはここから削除し、Overlayへ移動)
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
                        .padding(.top, 60) // 通知バーとかぶらないように少し下げる
                        
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
            .overlay(alignment: .top) {
                // ★修正: ここに通知を置くことで、画面レイアウトを崩さずに上に乗せることができます
                if gazeManager.statusMessage != "稼働中" {
                    Text(gazeManager.statusMessage)
                        .font(.headline)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(
                            gazeManager.statusMessage.contains("位置ずれ") ? Color.orange :
                            gazeManager.statusMessage.contains("自動補正") ? Color.green : Color.black.opacity(0.7)
                        )
                        .foregroundColor(.white)
                        .transition(.move(edge: .top))
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

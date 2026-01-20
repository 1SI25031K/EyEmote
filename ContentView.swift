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
                        // ★【追加】ステータス通知バナー
                        // 「稼働中」以外のメッセージ（つまり補正時）は目立つように表示
                        if gazeManager.statusMessage != "稼働中" {
                            Text(gazeManager.statusMessage)
                                .font(.headline)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(
                                    // 自動補正ならオレンジ、手動なら緑、それ以外はグレー
                                    gazeManager.statusMessage.contains("検知") ? Color.orange :
                                    gazeManager.statusMessage.contains("自動補正") ? Color.green : Color.black.opacity(0.7)
                                )
                                .foregroundColor(.white)
                                .transition(.move(edge: .top))
                                .animation(.easeInOut, value: gazeManager.statusMessage)
                        }
                        
                        // ヘッダー (既存)
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
                        
                        Spacer()
                        
                        // コンテンツグリッド (既存)
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
                    
                    // カーソル (既存)
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
            
            // キャリブレーション画面 (既存)
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

// 忘れずにこれもファイルの末尾に残しておいてください
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

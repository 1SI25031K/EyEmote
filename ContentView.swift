import SwiftUI

struct ContentView: View {
    @StateObject private var gazeManager = GazeManager()
    @State private var selectedItem: String = "Look at Screen"
    
    let columns = [GridItem(.flexible()), GridItem(.flexible())]
    
    var body: some View {
        GeometryReader { geometry in // 画面サイズを取得
            ZStack {
                Color(.systemBackground).ignoresSafeArea()
                
                VStack(spacing: 30) {
                    // ... (ヘッダー部分は同じ) ...
                    Text("Eye Tracking Demo")
                        .font(.largeTitle)
                        .bold()
                    Text(selectedItem)
                    
                    Spacer()
                    
                    LazyVGrid(columns: columns, spacing: 20) {
                        // 座標を計算して渡す
                        let currentPoint = CGPoint(
                            x: gazeManager.cursorRelativePosition.x * geometry.size.width,
                            y: gazeManager.cursorRelativePosition.y * geometry.size.height
                        )
                        
                        GazeButton(
                            title: "Star",
                            icon: "star.fill",
                            action: { selectedItem = "Star!" },
                            cursorPosition: currentPoint // 渡す
                        )
                        
                        // ... 他のボタンも同様に currentPoint を渡す ...
                         GazeButton(
                            title: "Play",
                            icon: "play.fill",
                            action: { selectedItem = "Play!" },
                            cursorPosition: currentPoint
                        )
                    }
                    .padding(.horizontal, 40)
                    
                    Spacer()
                }
                
                if gazeManager.isFaceDetected {
                    // カーソル表示もここで計算
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

import SwiftUI
import ARKit

@available(iOS 17.0, *)
struct ContentView: View {
    @StateObject private var gazeManager = GazeManager()
    @State private var selectedItem: String = "Ready"
    
    // フロー管理
    enum AppState {
        case splash
        case calibration
        case decisionMethod
        case feelingColorPicker
        case opacitySelection
        case fluidSoul
        case eyeShapeSculpting
        case mainApp
    }
    
    @State private var appState: AppState = .splash
    
    let columns = [GridItem(.flexible()), GridItem(.flexible())]
    
    var body: some View {
        ZStack {
            // 背景レイヤー (メインアプリ用)
            if appState == .mainApp {
                GeometryReader { geometry in
                    ZStack {
                        ARCameraView(session: gazeManager.arSession)
                            .ignoresSafeArea()
                            .opacity(0.3)
                        
                        VStack {
                            // Header
                            HStack {
                                Button(action: { appState = .calibration }) {
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
                            .padding().padding(.top, 40)
                            
                            Spacer()
                            
                            // Buttons Grid
                            LazyVGrid(columns: columns, spacing: 30) {
                                let cursor = CGPoint(
                                    x: gazeManager.cursorRelativePosition.x * geometry.size.width,
                                    y: gazeManager.cursorRelativePosition.y * geometry.size.height
                                )
                                GazeButton(title: "Like", icon: "hand.thumbsup.fill", action: { selectedItem = "Liked" }, cursorPosition: cursor)
                                GazeButton(title: "Play", icon: "play.circle.fill", action: { selectedItem = "Playing" }, cursorPosition: cursor)
                                GazeButton(title: "Next", icon: "forward.fill", action: { selectedItem = "Next" }, cursorPosition: cursor)
                                GazeButton(title: "Menu", icon: "list.bullet", action: { selectedItem = "Menu" }, cursorPosition: cursor)
                            }
                            .padding(40)
                            Spacer()
                        }
                        
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
                .overlay(alignment: .bottom) {
                    // 通知バー
                    if !gazeManager.statusMessage.isEmpty {
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
            }
            
            // --- 各フェーズのビュー遷移 ---
            
            // 3. Fluid Soul Experience (Artistic)
            if appState == .fluidSoul {
                FluidSoulExperienceView(gazeManager: gazeManager) {
                    withAnimation { appState = .eyeShapeSculpting }
                }
                .transition(.opacity)
                .zIndex(150)
            }
            
            // 3.5 EyE Shape Sculpting (Organic area-based sculpting)
            if appState == .eyeShapeSculpting {
                EyEShapeSculptingView(gazeManager: gazeManager) {
                    withAnimation { appState = .mainApp }
                }
                .transition(.opacity)
                .zIndex(155)
            }
            
            // 2. Calibration
            if appState == .calibration {
                CalibrationView(gazeManager: gazeManager) {
                    withAnimation { appState = .decisionMethod }
                }
                .transition(.opacity)
                .zIndex(100)
            }
            
            // 2.5 Decision Method Selection
            if appState == .decisionMethod {
                DecisionMethodSelectionView(gazeManager: gazeManager) {
                    withAnimation { appState = .feelingColorPicker }
                }
                .transition(.opacity)
                .zIndex(120)
            }
            
            // 2.6 EyEPencil Selection (discrete pencil grid, replaces gradient wheel)
            if appState == .feelingColorPicker {
                EyEPencilSelectionView(gazeManager: gazeManager) {
                    withAnimation(.interactiveSpring(response: 0.5, dampingFraction: 0.8)) { appState = .opacitySelection }
                }
                .transition(.opacity)
                .zIndex(125)
            }
            
            // 2.7 Opacity Selection (transparency of decidedColor; cell-division transition)
            if appState == .opacitySelection {
                OpacitySelectionView(gazeManager: gazeManager) {
                    withAnimation { appState = .fluidSoul }
                }
                .transition(.opacity)
                .zIndex(127)
            }
            
            // 1. Splash
            if appState == .splash {
                SplashView {
                    withAnimation(.easeOut(duration: 1.0)) {
                        appState = .calibration
                    }
                }
                .zIndex(200)
                .transition(.opacity)
            }
        }
    }
}

// ARCameraView (維持)
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

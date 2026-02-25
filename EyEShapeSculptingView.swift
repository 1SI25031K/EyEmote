//
//  EyEShapeSculptingView.swift
//  EyEmote
//
//  Organic area-based sculpting for high accessibility: magnetic snap,
//  influence radius, pulse (bulge) and dent (dwell valley), with Liquid Glass feedback.
//

import SwiftUI

@available(iOS 17.0, *)
struct EyEShapeSculptingView: View {
    @ObservedObject var gazeManager: GazeManager
    var onComplete: () -> Void
    
    // Shape: circle with N vertices; each vertex has a displacement for deformation
    private let vertexCount = 64
    private let baseRadius: CGFloat = 120
    private let magneticSnapDistance: CGFloat = 50
    private let influenceRadius: CGFloat = 80
    private let dentDwellThreshold: TimeInterval = 0.6
    private let pulseStrength: CGFloat = 0.6
    private let dentStrength: CGFloat = 0.5
    private let relaxationFactor: CGFloat = 0.96
    
    @State private var vertexDisplacements: [CGPoint] = []
    @State private var viewSize: CGSize = .zero
    
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let cursorRel = gazeManager.cursorRelativePosition
            let cursorPt = CGPoint(x: cursorRel.x * size.width, y: cursorRel.y * size.height)
            let centerPt = CGPoint(x: size.width / 2, y: size.height / 2)
            
            ZStack {
                // Background
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                
                // EyE Shape (deformable)
                EyEShapePath(
                    center: centerPt,
                    baseRadius: baseRadius,
                    vertexCount: vertexCount,
                    displacements: vertexDisplacements
                )
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.5),
                            Color.white.opacity(0.2)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    EyEShapePath(
                        center: centerPt,
                        baseRadius: baseRadius,
                        vertexCount: vertexCount,
                        displacements: vertexDisplacements
                    )
                    .stroke(Color.white.opacity(0.6), lineWidth: 2)
                )
                .blur(radius: 2)
                .shadow(color: .white.opacity(0.3), radius: 20)
                
                // Influence Ring (when cursor is near the shape)
                if showInfluenceRing(cursorPt: cursorPt, centerPt: centerPt) {
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.8),
                                    Color.cyan.opacity(0.5)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 3
                        )
                        .frame(width: influenceRadius * 2, height: influenceRadius * 2)
                        .blur(radius: 4)
                        .position(cursorPt)
                        .allowsHitTesting(false)
                }
                
                // Cursor
                Circle()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 24, height: 24)
                    .overlay(Circle().stroke(Color.cyan.opacity(0.8), lineWidth: 2))
                    .shadow(color: .black.opacity(0.3), radius: 8)
                    .position(cursorPt)
                    .allowsHitTesting(false)
                
                // Status
                VStack {
                    if !gazeManager.statusMessage.isEmpty {
                        Text(gazeManager.statusMessage)
                            .font(.caption)
                            .fontWeight(.bold)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                            .padding(.top, 50)
                    }
                    Spacer()
                    Text("Move your eyes to shape. Stare to make a dent. Blink to confirm.")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))
                        .shadow(radius: 4)
                        .padding(.bottom, 50)
                    Button("Done") {
                        gazeManager.isSculptingMode = false
                        onComplete()
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.bottom, 30)
                }
            }
            .onAppear {
                viewSize = size
                if vertexDisplacements.isEmpty {
                    vertexDisplacements = (0..<vertexCount).map { _ in .zero }
                }
                gazeManager.isSculptingMode = true
            }
            .onChange(of: size.width) { _ in viewSize = size }
            .onChange(of: size.height) { _ in viewSize = size }
            .onDisappear {
                gazeManager.isSculptingMode = false
            }
            .onReceive(Timer.publish(every: 1/60, on: .main, in: .common).autoconnect()) { _ in
                let w = viewSize.width
                let h = viewSize.height
                guard w > 0, h > 0 else { return }
                let pt = CGPoint(x: gazeManager.cursorRelativePosition.x * w, y: gazeManager.cursorRelativePosition.y * h)
                let cen = CGPoint(x: w / 2, y: h / 2)
                applySculpting(cursorPt: pt, centerPt: cen, dwellTime: gazeManager.dwellTime)
            }
        }
    }
    
    private func showInfluenceRing(cursorPt: CGPoint, centerPt: CGPoint) -> Bool {
        let distToCenter = hypot(cursorPt.x - centerPt.x, cursorPt.y - centerPt.y)
        return distToCenter <= baseRadius + magneticSnapDistance + influenceRadius
    }
    
    private func applySculpting(cursorPt: CGPoint, centerPt: CGPoint, dwellTime: TimeInterval) {
        guard vertexDisplacements.count == vertexCount else { return }
        
        let vertices: [CGPoint] = (0..<vertexCount).map { i in
            let angle = (CGFloat(i) / CGFloat(vertexCount)) * 2 * .pi - .pi / 2
            let base = CGPoint(
                x: centerPt.x + baseRadius * cos(angle),
                y: centerPt.y + baseRadius * sin(angle)
            )
            return CGPoint(x: base.x + vertexDisplacements[i].x, y: base.y + vertexDisplacements[i].y)
        }
        
        // Magnetic snap: find nearest segment and attachment point
        var attachmentPt = cursorPt
        var distToShape = CGFloat.greatestFiniteMagnitude
        for i in 0..<vertexCount {
            let a = vertices[i]
            let b = vertices[(i + 1) % vertexCount]
            let (d, nearest) = distanceFromPointToSegment(point: cursorPt, segStart: a, segEnd: b)
            if d < distToShape {
                distToShape = d
                attachmentPt = nearest
            }
        }
        
        let isNearShape = distToShape <= magneticSnapDistance
        let directionFromCenter = CGPoint(
            x: attachmentPt.x - centerPt.x,
            y: attachmentPt.y - centerPt.y
        )
        let dirLen = hypot(directionFromCenter.x, directionFromCenter.y)
        let unitOutward = dirLen > 0.01 ? CGPoint(x: directionFromCenter.x / dirLen, y: directionFromCenter.y / dirLen) : CGPoint(x: 1, y: 0)
        
        // Relaxation: pull displacements back toward zero
        for i in 0..<vertexCount {
            vertexDisplacements[i].x *= relaxationFactor
            vertexDisplacements[i].y *= relaxationFactor
        }
        
        if isNearShape {
            for i in 0..<vertexCount {
                let baseAngle = (CGFloat(i) / CGFloat(vertexCount)) * 2 * .pi - .pi / 2
                let basePt = CGPoint(
                    x: centerPt.x + baseRadius * cos(baseAngle),
                    y: centerPt.y + baseRadius * sin(baseAngle)
                )
                let toVertex = CGPoint(x: basePt.x - attachmentPt.x, y: basePt.y - attachmentPt.y)
                let distToAttachment = hypot(toVertex.x, toVertex.y)
                
                if distToAttachment > influenceRadius { continue }
                
                let influence = 1.0 - (distToAttachment / influenceRadius) * 0.5
                
                // Pulse: bulge outward in direction of gaze
                let outward = CGPoint(x: unitOutward.x * pulseStrength * influence * 2, y: unitOutward.y * pulseStrength * influence * 2)
                vertexDisplacements[i].x += outward.x
                vertexDisplacements[i].y += outward.y
                
                // Dent: dwell creates a broad valley (vertices pulled toward attachment point)
                if dwellTime >= dentDwellThreshold {
                    let dentAmount = dentStrength * influence * min(1.2, (dwellTime - dentDwellThreshold) * 0.6)
                    let toward = CGPoint(x: -toVertex.x * dentAmount / max(distToAttachment, 1), y: -toVertex.y * dentAmount / max(distToAttachment, 1))
                    vertexDisplacements[i].x += toward.x * 50
                    vertexDisplacements[i].y += toward.y * 50
                }
            }
        }
    }
    
    private func distanceFromPointToSegment(point: CGPoint, segStart: CGPoint, segEnd: CGPoint) -> (CGFloat, CGPoint) {
        let dx = segEnd.x - segStart.x
        let dy = segEnd.y - segStart.y
        let len2 = dx * dx + dy * dy
        if len2 < 1e-10 {
            let d = hypot(point.x - segStart.x, point.y - segStart.y)
            return (d, segStart)
        }
        var t = ((point.x - segStart.x) * dx + (point.y - segStart.y) * dy) / len2
        t = max(0, min(1, t))
        let nearest = CGPoint(x: segStart.x + t * dx, y: segStart.y + t * dy)
        let d = hypot(point.x - nearest.x, point.y - nearest.y)
        return (d, nearest)
    }
}

private struct EyEShapePath: Shape {
    var center: CGPoint
    var baseRadius: CGFloat
    var vertexCount: Int
    var displacements: [CGPoint]
    
    func path(in rect: CGRect) -> Path {
        guard displacements.count == vertexCount else { return Path(ellipseIn: CGRect(x: center.x - baseRadius, y: center.y - baseRadius, width: baseRadius * 2, height: baseRadius * 2)) }
        var path = Path()
        for i in 0..<vertexCount {
            let angle = (CGFloat(i) / CGFloat(vertexCount)) * 2 * .pi - .pi / 2
            let x = center.x + baseRadius * cos(angle) + displacements[i].x
            let y = center.y + baseRadius * sin(angle) + displacements[i].y
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        path.closeSubpath()
        return path
    }
}

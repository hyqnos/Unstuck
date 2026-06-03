import SwiftUI
import SceneKit
import UIKit

/// The companion's 3D "art" — a stylised low-poly creature (lion-ish: round body,
/// head, ears, a little mane, snout) built ENTIRELY in code from SceneKit
/// primitives, so there's no external model file to ship or license. It idles
/// like it's alive (breathes, bobs, looks around, blinks) and reacts (a hop +
/// spin on a win), recolouring to the brain mode. A real rigged USDZ could
/// replace `Coordinator.build` later — but this is genuine native 3D, today.
struct Companion3D: View {
    private let mood = MoodDetector.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var celebrateTick = 0

    private var uiTint: UIColor {
        switch mood.mode {
        case .ready:      return UIColor(red: 0.30, green: 0.85, blue: 0.60, alpha: 1)
        case .hyperfocus: return UIColor(red: 0.45, green: 0.50, blue: 1.00, alpha: 1)
        case .lowBattery: return UIColor(red: 1.00, green: 0.60, blue: 0.40, alpha: 1)
        case .overwhelm:  return UIColor(red: 0.60, green: 0.66, blue: 0.78, alpha: 1)
        }
    }

    var body: some View {
        CompanionSceneView(tint: uiTint, animate: !reduceMotion, celebrateTick: celebrateTick)
            .frame(width: 66, height: 66)
            .onReceive(NotificationCenter.default.publisher(for: .taskCompleted)) { _ in
                if !AppSettings.shared.calmMode { celebrateTick &+= 1 }
            }
            .accessibilityLabel(Text("Your companion"))
            .accessibilityHint(Text("A friendly 3D presence."))
    }
}

private struct CompanionSceneView: UIViewRepresentable {
    let tint: UIColor
    let animate: Bool
    let celebrateTick: Int

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let v = SCNView()
        v.backgroundColor = .clear
        v.antialiasingMode = .multisampling2X
        v.isUserInteractionEnabled = false
        v.preferredFramesPerSecond = 30   // it's tiny — half the framerate, ~half the GPU/battery
        let scene = SCNScene()
        v.scene = scene
        context.coordinator.build(in: scene, tint: tint, animate: animate)
        return v
    }

    func updateUIView(_ v: SCNView, context: Context) {
        context.coordinator.applyTint(tint)
        if celebrateTick != context.coordinator.lastCelebrate {
            context.coordinator.lastCelebrate = celebrateTick
            context.coordinator.celebrate()
        }
    }

    static func dismantleUIView(_ v: SCNView, coordinator: Coordinator) {
        coordinator.timer?.invalidate()
    }

    final class Coordinator {
        let root = SCNNode()
        let head = SCNNode()
        let bodyMat = SCNMaterial()
        let headMat = SCNMaterial()
        let maneMat = SCNMaterial()
        let snoutMat = SCNMaterial()
        var leftEye = SCNNode()
        var rightEye = SCNNode()
        var lastCelebrate = 0
        var timer: Timer?

        func build(in scene: SCNScene, tint: UIColor, animate: Bool) {
            // Camera
            let cam = SCNNode()
            cam.camera = SCNCamera()
            cam.camera?.fieldOfView = 38
            cam.position = SCNVector3(0, 0.2, 6.4)
            scene.rootNode.addChildNode(cam)

            // Lights
            let omni = SCNNode()
            omni.light = SCNLight(); omni.light?.type = .omni
            omni.light?.intensity = 850
            omni.position = SCNVector3(3, 5, 6)
            scene.rootNode.addChildNode(omni)
            let amb = SCNNode()
            amb.light = SCNLight(); amb.light?.type = .ambient
            amb.light?.intensity = 480; amb.light?.color = UIColor.white
            scene.rootNode.addChildNode(amb)

            // Materials
            for m in [bodyMat, headMat, maneMat, snoutMat] { m.lightingModel = .blinn }
            bodyMat.diffuse.contents = tint
            headMat.diffuse.contents = tint
            maneMat.diffuse.contents = tint.adjust(0.65)
            snoutMat.diffuse.contents = tint.adjust(1.3)

            // Body
            let body = SCNNode(geometry: SCNSphere(radius: 1.0))
            body.geometry?.firstMaterial = bodyMat
            body.scale = SCNVector3(1.0, 0.9, 0.9)
            body.position = SCNVector3(0, -0.6, 0)
            root.addChildNode(body)

            // Head
            let headGeo = SCNSphere(radius: 0.78)
            headGeo.firstMaterial = headMat
            head.geometry = headGeo
            head.position = SCNVector3(0, 0.78, 0)
            root.addChildNode(head)

            // Mane (lion cue) — a torus ringing the head
            let mane = SCNNode(geometry: SCNTorus(ringRadius: 0.86, pipeRadius: 0.22))
            mane.geometry?.firstMaterial = maneMat
            mane.position = SCNVector3(0, 0, -0.12)
            head.addChildNode(mane)

            // Ears
            for sx in [Float(-1), Float(1)] {
                let ear = SCNNode(geometry: SCNCone(topRadius: 0, bottomRadius: 0.26, height: 0.5))
                ear.geometry?.firstMaterial = headMat
                ear.position = SCNVector3(sx * 0.45, 0.72, 0)
                ear.eulerAngles = SCNVector3(0, 0, -sx * 0.3)
                head.addChildNode(ear)
            }

            // Eyes (white + dark pupil)
            for sx in [Float(-1), Float(1)] {
                let white = SCNMaterial(); white.diffuse.contents = UIColor.white
                let eye = SCNNode(geometry: SCNSphere(radius: 0.17))
                eye.geometry?.firstMaterial = white
                eye.position = SCNVector3(sx * 0.3, 0.06, 0.66)
                let pmat = SCNMaterial(); pmat.diffuse.contents = UIColor.black
                let pupil = SCNNode(geometry: SCNSphere(radius: 0.085))
                pupil.geometry?.firstMaterial = pmat
                pupil.position = SCNVector3(0, 0, 0.12)
                eye.addChildNode(pupil)
                head.addChildNode(eye)
                if sx < 0 { leftEye = eye } else { rightEye = eye }
            }

            // Snout
            let snout = SCNNode(geometry: SCNSphere(radius: 0.3))
            snout.geometry?.firstMaterial = snoutMat
            snout.scale = SCNVector3(1, 0.8, 0.8)
            snout.position = SCNVector3(0, -0.28, 0.62)
            head.addChildNode(snout)

            scene.rootNode.addChildNode(root)
            if animate { startIdle() }
        }

        private func startIdle() {
            let up = SCNAction.scale(to: 1.04, duration: 1.3); up.timingMode = .easeInEaseOut
            let down = SCNAction.scale(to: 1.0, duration: 1.3); down.timingMode = .easeInEaseOut
            root.runAction(.repeatForever(.sequence([up, down])))

            let bobUp = SCNAction.moveBy(x: 0, y: 0.07, z: 0, duration: 1.6); bobUp.timingMode = .easeInEaseOut
            let bobDown = SCNAction.moveBy(x: 0, y: -0.07, z: 0, duration: 1.6); bobDown.timingMode = .easeInEaseOut
            root.runAction(.repeatForever(.sequence([bobUp, bobDown])))

            timer = Timer.scheduledTimer(withTimeInterval: 1.1, repeats: true) { [weak self] _ in
                guard let self else { return }
                if Double.random(in: 0...1) < 0.35 { self.lookAround() }
                if Double.random(in: 0...1) < 0.30 { self.blink() }
            }
        }

        private func lookAround() {
            let yaw = CGFloat.random(in: -0.4...0.4)
            let pitch = CGFloat.random(in: -0.2...0.2)
            let look = SCNAction.rotateTo(x: pitch, y: yaw, z: 0, duration: 0.5, usesShortestUnitArc: true)
            look.timingMode = .easeInEaseOut
            let hold = SCNAction.wait(duration: Double.random(in: 0.6...1.6))
            let back = SCNAction.rotateTo(x: 0, y: 0, z: 0, duration: 0.5, usesShortestUnitArc: true)
            back.timingMode = .easeInEaseOut
            head.runAction(.sequence([look, hold, back]))
        }

        private func blink() {
            for eye in [leftEye, rightEye] {
                SCNTransaction.begin(); SCNTransaction.animationDuration = 0.07
                eye.scale = SCNVector3(1, 0.1, 1)
                SCNTransaction.commit()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    SCNTransaction.begin(); SCNTransaction.animationDuration = 0.10
                    eye.scale = SCNVector3(1, 1, 1)
                    SCNTransaction.commit()
                }
            }
        }

        func celebrate() {
            let up = SCNAction.moveBy(x: 0, y: 0.5, z: 0, duration: 0.18); up.timingMode = .easeOut
            let down = SCNAction.moveBy(x: 0, y: -0.5, z: 0, duration: 0.30); down.timingMode = .easeIn
            let spin = SCNAction.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 0.55)
            root.runAction(.group([.sequence([up, down]), spin]))
        }

        func applyTint(_ tint: UIColor) {
            bodyMat.diffuse.contents = tint
            headMat.diffuse.contents = tint
            maneMat.diffuse.contents = tint.adjust(0.65)
            snoutMat.diffuse.contents = tint.adjust(1.3)
        }
    }
}

private extension UIColor {
    /// Multiply RGB by a factor (clamped) — darker (<1) or lighter (>1).
    func adjust(_ f: CGFloat) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(red: min(r * f, 1), green: min(g * f, 1), blue: min(b * f, 1), alpha: a)
    }
}

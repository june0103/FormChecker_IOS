import PoseEngine
import SwiftUI

/// 스켈레톤 오버레이.
///
/// 관절점은 라임, 연결선은 라임 50% — **그라데이션 금지**.
/// `mirrored`는 전면 카메라처럼 프리뷰가 좌우 반전돼 보일 때 켠다. 🔴 **추론은 반전 없이**
/// 하고 여기서만 뒤집는다 — 입력을 반전하면 모델의 좌/우 라벨이 바뀐다.
struct SkeletonOverlay: View {

    let pose: Pose?
    let mirrored: Bool
    var minConfidence: Float = Pose.minConfidence

    /// Halpe26 뼈대. 발 6개가 이 모델을 쓰는 이유다.
    private static let bones: [(KeypointType, KeypointType)] = [
        (.nose, .neck), (.neck, .leftShoulder), (.neck, .rightShoulder),
        (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
        (.leftShoulder, .leftHip), (.rightShoulder, .rightHip), (.leftHip, .rightHip),
        (.leftHip, .leftKnee), (.leftKnee, .leftAnkle),
        (.rightHip, .rightKnee), (.rightKnee, .rightAnkle),
        (.leftAnkle, .leftHeel), (.leftHeel, .leftBigToe), (.leftHeel, .leftSmallToe),
        (.rightAnkle, .rightHeel), (.rightHeel, .rightBigToe), (.rightHeel, .rightSmallToe),
    ]

    /// 겹쳐 보여 표시하지 않는 점들.
    private static let hidden: Set<KeypointType> = [.head, .hipCenter, .leftEye, .rightEye,
                                                    .leftEar, .rightEar]

    var body: some View {
        Canvas { context, size in
            guard let pose else { return }

            func point(_ type: KeypointType) -> CGPoint? {
                guard pose.isReliable(type, minConfidence: minConfidence) else { return nil }
                let kp = pose[type]
                let x = mirrored ? 1 - kp.x : kp.x
                return CGPoint(x: CGFloat(x) * size.width, y: CGFloat(kp.y) * size.height)
            }

            for (a, b) in Self.bones {
                guard let p1 = point(a), let p2 = point(b) else { continue }
                var path = Path()
                path.move(to: p1)
                path.addLine(to: p2)
                context.stroke(path, with: .color(Palette.lime.opacity(0.5)), lineWidth: 3)
            }

            for type in KeypointType.allCases where !Self.hidden.contains(type) {
                guard let p = point(type) else { continue }
                let radius: CGFloat = type.rawValue >= KeypointType.leftBigToe.rawValue ? 3.5 : 5
                context.fill(
                    Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius,
                                           width: radius * 2, height: radius * 2)),
                    with: .color(Palette.lime)
                )
            }
        }
        .allowsHitTesting(false)
    }
}

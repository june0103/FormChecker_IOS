import Foundation
import XCTest
@testable import PoseEngine

/// **PRD §8의 "고정 입력 주입기"** — 카메라도 화면도 없이 파이프라인을 끝까지 돌린다.
///
/// ## 왜 이게 있어야 하나
/// 단위 테스트 316개는 **함수 하나하나**가 Android와 같은 답을 내는지만 본다. 그런데
/// `PosePipeline`은 그 함수들을 **순서대로 엮는** 코드고, 엮는 자리에서 틀리면 함수는
/// 전부 맞으면서 **횟수만 빗나간다.** 기준 자세가 언제 끝나는지, 언제부터 세기 시작하는지,
/// 스무딩이 몇 프레임 뒤처지는지는 함수 단위로 증명되지 않는다.
///
/// 이 파일은 그 엮임을 처음으로 테스트한다. 동시에 **G1(rep 카운팅 동등성)의 iOS 쪽
/// 절반**이다 — Android가 같은 입력에서 센 수가 생기면 여기에 붙여 비교하면 된다.
///
/// 🔴 **파이프라인을 복제하지 않는다.** `PosePipeline.process(pose:…)`는 운동 화면이
///    타는 바로 그 코드다. 여기서 사본을 만들면 테스트가 통과해도 앱은 다를 수 있다.
final class PosePipelineSequenceTests: XCTestCase {

    // ── 입력 만들기 ──────────────────────────────────────────

    /// 무릎 각도를 지정해 만든 **정면** 자세.
    ///
    /// 발목과 무릎을 고정하고 **엉덩이만** 무릎 둘레로 돌린다. 각도를 숫자로 통제할 수
    /// 있어야 "몇 도에서 rep이 되는가"를 테스트가 말할 수 있다. 상체는 엉덩이를 따라
    /// 같이 내려간다 — 어깨를 고정하면 앉을수록 몸통이 짧아져 없던 경고가 생긴다.
    ///
    /// 🔴 **한 발의 발목·발뒤꿈치·발끝·무릎을 전부 같은 쪽에 둔다.**
    ///    `ReadyPostureTests`의 배치는 `leftAnkle`이 0.40인데 `leftHeel`은 0.60이다 —
    ///    거기서는 좌우 대칭과 간격만 보므로 문제가 없지만, 무릎 정렬은
    ///    `(무릎 x − 발끝 x) / 발목 간격`으로 **부호를 보는** 판정이라 그대로 베끼면
    ///    모든 rep에 없는 `kneeValgus`가 붙는다. 실제로 한 번 그렇게 나왔다.
    ///
    /// - Parameter kneeInward: 무릎을 안쪽으로 당기는 양(정규화 좌표). 0이면 무릎이
    ///   발끝 위에 그대로 선다 — 경고가 없는 기준 입력이다.
    private func frontPose(kneeAngleDeg: Float, kneeInward: Float = 0,
                           confidence: Float = 0.9) -> Pose {
        let halfWidth: Float = 0.10
        let ankleY: Float = 0.90
        let kneeY: Float = 0.70
        let thigh: Float = 0.20

        /// `sign`은 화면 x의 방향. 회전 방향도 같이 뒤집어야 대칭이 된다.
        ///
        /// 🔴 **`.left`가 화면 오른쪽(x가 큰 쪽)이다.** 피험자가 카메라를 마주 보므로
        ///    그 사람의 왼쪽은 보는 쪽의 오른쪽에 찍힌다. `FrameFeatures`의
        ///    `inwardSign = (side == .left ? -1 : 1)`이 그 전제 위에 있다 — 뒤집어 두면
        ///    무릎을 **안으로** 말았는데 `kneeFlared`가 나온다. 실제로 그렇게 나왔다.
        func leg(sign: Float) -> (hip: (x: Float, y: Float), knee: Float, ankle: Float) {
            let ankleX = 0.50 + sign * halfWidth
            let kneeX = ankleX - sign * kneeInward
            let dx = ankleX - kneeX
            let dy = ankleY - kneeY
            let length = (dx * dx + dy * dy).squareRoot()
            let ux = dx / length
            let uy = dy / length
            let theta = kneeAngleDeg * .pi / 180
            let c = cos(theta)
            let s = sin(theta) * sign
            return ((kneeX + thigh * (ux * c - uy * s),
                     kneeY + thigh * (ux * s + uy * c)), kneeX, ankleX)
        }

        let left = leg(sign: 1)
        let right = leg(sign: -1)
        let hipY = (left.hip.y + right.hip.y) / 2
        // 몸통은 굳은 채로 따라 내려간다.
        let shoulderY = hipY - 0.20

        var points: [KeypointType: PoseFixtures.Point] = [
            .leftShoulder: (0.32, shoulderY, confidence),
            .rightShoulder: (0.68, shoulderY, confidence),
            .neck: (0.50, shoulderY + 0.02, confidence),
            .leftHip: (left.hip.x, left.hip.y, confidence),
            .rightHip: (right.hip.x, right.hip.y, confidence),
            .leftKnee: (left.knee, kneeY, confidence),
            .rightKnee: (right.knee, kneeY, confidence),
            .leftAnkle: (left.ankle, ankleY, confidence),
            .rightAnkle: (right.ankle, ankleY, confidence),
            .leftHeel: (left.ankle, 0.94, confidence),
            .rightHeel: (right.ankle, 0.94, confidence),
        ]
        // 발끝은 발목 바로 앞. 벌리면 무릎이 발끝 안쪽으로 들어가 valgus가 된다 —
        // 기준 입력은 경고가 없어야 하므로 정면으로 둔다.
        for type in [KeypointType.leftBigToe, .leftSmallToe] {
            points[type] = (left.ankle, 0.94, confidence)
        }
        for type in [KeypointType.rightBigToe, .rightSmallToe] {
            points[type] = (right.ankle, 0.94, confidence)
        }
        return PoseFixtures.pose(points)
    }

    /// 한 번 앉았다 일어나는 무릎 각도 열. `RepStateMachineTests.squat()`과 같은 식이다 —
    /// 그쪽이 통과하는 입력이어야 여기서도 같은 수가 나온다.
    private func squatAngles(bottom: Float, moveFrames: Int = 60, standFrames: Int = 20)
        -> [Float] {
        var out = [Float](repeating: 178, count: standFrames)
        for index in 0..<moveFrames {
            let phase = Double(index) / Double(moveFrames - 1) * Double.pi
            out.append(Float(178.0 - (178.0 - Double(bottom)) * sin(phase)))
        }
        out += [Float](repeating: 178, count: standFrames)
        return out
    }

    // ── 돌리기 ──────────────────────────────────────────────

    /// 콜백이 `@Sendable`이라 지역 변수에 바로 담을 수 없다. 테스트는 한 스레드에서만
    /// 돌므로 상자 하나로 받는다.
    private final class Recorder: @unchecked Sendable {
        var frames: [RepFrame] = []
        var reps: [CompletedRep] = []
        var cues: [AudioCue] = []
        var last = WorkoutSnapshot()
    }

    private let frameMs: Int64 = 33  // 30fps
    private let width = 480
    private let height = 640

    /// 기준 자세를 끝까지 잡고, 그다음 주어진 각도 열을 먹인다.
    private func run(angles: [Float], kneeInward: Float = 0, prepSeconds: Int = 1)
        -> (pipeline: PosePipeline, recorder: Recorder) {
        let pipeline = PosePipeline()
        let recorder = Recorder()
        pipeline.prepSeconds = prepSeconds
        pipeline.onRepCompleted = { recorder.reps.append($0) }
        pipeline.onCue = { recorder.cues.append($0) }
        pipeline.onSnapshot = { recorder.last = $0 }
        pipeline.onRepFrame = { recorder.frames.append($0) }

        var now: Int64 = 0
        pipeline.beginCalibration(nowMs: now)

        // 준비(prepSeconds) + 측정(3초) + 여유 한 프레임.
        let calibrationMs = Int64(prepSeconds) * 1_000 + 3_000 + frameMs
        while now <= calibrationMs {
            pipeline.process(pose: frontPose(kneeAngleDeg: 178),
                             width: width, height: height, timestampMs: now)
            now += frameMs
        }

        for angle in angles {
            pipeline.process(pose: frontPose(kneeAngleDeg: angle, kneeInward: kneeInward),
                             width: width, height: height, timestampMs: now)
            now += frameMs
        }
        return (pipeline, recorder)
    }

    // ── 기준 자세 ────────────────────────────────────────────

    func test_정면_기준_자세가_잡히면_세기_시작한다() {
        let (_, recorder) = run(angles: [])

        XCTAssertEqual(recorder.last.stage, .ready,
                       "기준 자세가 안 잡혔다. 남은 지적: \(recorder.last.readyIssues)")
        XCTAssertTrue(recorder.last.calibrated)
        XCTAssertTrue(recorder.last.countingEnabled)
        XCTAssertTrue(recorder.cues.contains(.calibrated))
    }

    func test_기준_자세_전에는_세지_않는다() {
        // 기준 자세를 아예 시작하지 않고 스쿼트만 먹인다.
        let pipeline = PosePipeline()
        let recorder = Recorder()
        pipeline.onRepCompleted = { recorder.reps.append($0) }
        pipeline.onSnapshot = { recorder.last = $0 }
        pipeline.onRepFrame = { recorder.frames.append($0) }

        var now: Int64 = 0
        for angle in squatAngles(bottom: 80) {
            pipeline.process(pose: frontPose(kneeAngleDeg: angle),
                             width: width, height: height, timestampMs: now)
            now += frameMs
        }

        XCTAssertFalse(recorder.last.countingEnabled)
        XCTAssertEqual(recorder.reps.count, 0,
                       "🔴 기준 자세 전에 센 rep이 있다 — 걸어가며 자리 잡는 동안 유령 rep이 생긴다")
    }

    // ── 카운팅 ──────────────────────────────────────────────

    func test_깊은_스쿼트_한_번은_rep_1개다() {
        let (_, recorder) = run(angles: squatAngles(bottom: 80))

        XCTAssertEqual(recorder.reps.count, 1)
        XCTAssertEqual(recorder.last.repCount, 1)
    }

    func test_연속_세_번은_rep_3개다() {
        var angles = squatAngles(bottom: 80)
        for _ in 0..<2 {
            angles += squatAngles(bottom: 80, standFrames: 15).dropFirst(15)
        }
        let (_, recorder) = run(angles: angles)

        XCTAssertEqual(recorder.reps.count, 3)
        XCTAssertEqual(recorder.last.repCount, 3)
    }

    func test_임계값에_못_미치면_세지_않는다() {
        let (_, recorder) = run(angles: squatAngles(bottom: 140))

        XCTAssertEqual(recorder.reps.count, 0)
    }

    /// 🔴 rep이 끝날 때 **소리 신호가 같이 나가야 한다.** 화면을 못 보는 상태가 기본
    ///    사용 환경이라, 조용히 세면 사용자는 세어졌는지 모른다.
    func test_rep이_끝나면_소리_신호가_나간다() {
        let (_, recorder) = run(angles: squatAngles(bottom: 80))

        XCTAssertTrue(recorder.cues.contains { $0 == .repDone || $0 == .repWarned })
    }

    /// 무릎을 안으로 말면 그 경고가 **rep까지** 실려 나오는가.
    ///
    /// 프레임 판정이 맞는 것과, 그 판정이 유지(hold)·집계를 거쳐 rep 요약까지 살아서
    /// 가는 것은 **다른 문제**다. G3(판정 동등성)이 보는 것이 이 경로다.
    func test_무릎을_안으로_말면_rep_경고로_나온다() {
        let (_, recorder) = run(angles: squatAngles(bottom: 80), kneeInward: 0.04)

        XCTAssertEqual(recorder.reps.count, 1)
        XCTAssertTrue(recorder.reps.first?.warnings.contains(.kneeValgus) == true,
                      "실제 경고: \(recorder.reps.first?.warnings ?? [])")
    }

    // ── G1 기준값 ────────────────────────────────────────────

    /// 두 플랫폼의 CSV를 잇는 키. **이름을 바꾸면 Android 쪽 기준값과 짝이 깨진다.**
    private var sequences: [(name: String, angles: [Float], kneeInward: Float)] {
        var triple = squatAngles(bottom: 80)
        for _ in 0..<2 { triple += squatAngles(bottom: 80, standFrames: 15).dropFirst(15) }
        return [
            ("deep", squatAngles(bottom: 80), 0),
            ("parallel", squatAngles(bottom: 100), 0),
            ("shallow_counted", squatAngles(bottom: 120), 0),
            ("too_shallow", squatAngles(bottom: 140), 0),
            ("valgus", squatAngles(bottom: 80), 0.04),
            ("triple", triple, 0),
        ]
    }

    /// 저장소 루트. `#filePath`는 `PoseEngine/Tests/PoseEngineTests/…`다.
    private static var referenceDir: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // PoseEngineTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // PoseEngine
            .deletingLastPathComponent()   // 저장소 루트
            .appendingPathComponent("tools/android-reference")
    }

    private func csv(_ value: Float?) -> String {
        guard let value else { return "" }   // 🔴 nil은 **빈 칸**이다. 0으로 바꾸지 말 것.
        return String(format: "%.6f", value)
    }

    /// 상태머신에 들어간 **원시 입력**과 iOS가 낸 답을 파일로 남긴다.
    ///
    /// Android는 같은 `g1_frames.csv`를 먹고 `g1_ios.csv`와 맞춰 보면 된다
    /// (`tools/android-reference/G1CountingTest.kt`).
    ///
    /// 🔴 **스무딩된 값은 내보내지 않는다.** 원시 각도만 주고 양쪽이 각자 EMA·중앙값을
    ///    돌려야 비교 범위에 스무딩까지 들어온다. 스무딩 결과를 넘기면 상태머신만 비교된다.
    func test_G1_기준값을_파일로_남긴다() throws {
        var frameRows = ["sequence,frame,timestampMs,rawKneeAngle,leftKneeAngle,rightKneeAngle,"
                         + "hipAngle,torsoLeanDegrees,kneeAsymmetryDegrees,kneeSpreadRatio,"
                         + "minLegConfidence"]
        var resultRows = ["sequence,reps,warnings"]

        for sequence in sequences {
            let (_, recorder) = run(angles: sequence.angles, kneeInward: sequence.kneeInward)
            for (index, frame) in recorder.frames.enumerated() {
                frameRows.append([
                    sequence.name, "\(index)", "\(frame.timestampMs)",
                    csv(frame.rawKneeAngle), csv(frame.leftKneeAngle), csv(frame.rightKneeAngle),
                    csv(frame.hipAngle), csv(frame.torsoLeanDegrees),
                    csv(frame.kneeAsymmetryDegrees), csv(frame.kneeSpreadRatio),
                    csv(frame.minLegConfidence),
                ].joined(separator: ","))
            }
            let warnings = recorder.reps
                .map { $0.warnings.map(\.rawValue).sorted().joined(separator: "|") }
                .joined(separator: ";")
            resultRows.append("\(sequence.name),\(recorder.reps.count),\(warnings)")
            print("G1,\(sequence.name),reps=\(recorder.reps.count),warnings=[\(warnings)]")
        }

        let dir = Self.referenceDir
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try (frameRows.joined(separator: "\n") + "\n")
            .write(to: dir.appendingPathComponent("g1_frames.csv"),
                   atomically: true, encoding: .utf8)
        try (resultRows.joined(separator: "\n") + "\n")
            .write(to: dir.appendingPathComponent("g1_ios.csv"),
                   atomically: true, encoding: .utf8)
    }

    /// 🔴 **최소 체인이 전체 파이프라인과 같은 수를 세는지 못 박는다.**
    ///
    /// Android 쪽 생성기는 `pose-engine`의 순수 조각(EMA·중앙값·상태머신)만 돌린다.
    /// 그 조각 묶음이 **실제 운동 화면이 타는 경로와 다른 답**을 내면, 두 플랫폼을
    /// 비교한 결과가 무엇을 뜻하는지 알 수 없어진다. 그래서 iOS 쪽에서 둘이 같다는 것을
    /// 먼저 묶어 둔다 — 이게 깨지면 G1 비교 자체가 무효다.
    func test_최소_체인이_전체_파이프라인과_같은_수를_센다() {
        for sequence in sequences {
            let (_, recorder) = run(angles: sequence.angles, kneeInward: sequence.kneeInward)
            XCTAssertEqual(minimalChainCount(recorder.frames), recorder.reps.count,
                           "시퀀스 \(sequence.name)에서 최소 체인과 파이프라인이 갈렸다")
        }
    }

    /// Android `G1CountingTest`가 하는 것과 **같은 계산**. 원시 각도만 먹는다.
    private func minimalChainCount(_ frames: [RepFrame]) -> Int {
        let smoothing = SmoothingConfig()
        let ema = AngleEma(timeConstantMs: smoothing.emaTimeConstantMs)
        var median = MedianWindow(size: MedianWindow.sizeFor(
            targetSpanMs: smoothing.medianWindowMs, fps: 30))
        let machine = RepStateMachine(thresholds: .default) { .front }

        var count = 0
        for frame in frames {
            let rebuilt = RepFrame(
                timestampMs: frame.timestampMs,
                rawKneeAngle: frame.rawKneeAngle,
                smoothedKneeAngle: ema.update(frame.rawKneeAngle, timestampMs: frame.timestampMs),
                medianKneeAngle: median.push(frame.rawKneeAngle),
                leftKneeAngle: frame.leftKneeAngle,
                rightKneeAngle: frame.rightKneeAngle,
                hipAngle: frame.hipAngle,
                torsoLeanDegrees: frame.torsoLeanDegrees,
                kneeAsymmetryDegrees: frame.kneeAsymmetryDegrees,
                kneeSpreadRatio: frame.kneeSpreadRatio,
                minLegConfidence: frame.minLegConfidence
            )
            if case .completed = machine.update(rebuilt) { count += 1 }
        }
        return count
    }
}

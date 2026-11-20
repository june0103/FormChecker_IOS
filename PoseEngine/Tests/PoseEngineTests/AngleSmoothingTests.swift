import XCTest
@testable import PoseEngine

final class AngleEmaTests: XCTestCase {

    private let frameMs: Int64 = 33

    func test_첫_유효_입력은_그대로_통과한다() throws {
        let ema = AngleEma(timeConstantMs: 120)
        XCTAssertEqual(try XCTUnwrap(ema.update(170, timestampMs: 0)), 170, accuracy: 0.001)
    }

    func test_유효_입력이_없으면_nil을_유지한다() {
        let ema = AngleEma(timeConstantMs: 120)
        XCTAssertNil(ema.update(nil, timestampMs: 0))
        XCTAssertNil(ema.current)
    }

    /// 🔴 가림 한두 프레임으로 rep이 끊기지 않게 하려면 이 동결이 필요하다.
    func test_저신뢰_프레임에서는_직전_값을_유지한다() throws {
        let ema = AngleEma(timeConstantMs: 120)
        ema.update(100, timestampMs: 0)
        let held = try XCTUnwrap(ema.update(nil, timestampMs: frameMs))
        XCTAssertEqual(held, 100, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(ema.current), 100, accuracy: 0.001)
    }

    func test_계단_입력을_시간에_걸쳐_따라간다() throws {
        let ema = AngleEma(timeConstantMs: 120)
        ema.update(0, timestampMs: 0)
        let after1Tau = try XCTUnwrap(ema.update(100, timestampMs: 120))
        XCTAssertEqual(after1Tau, 63, accuracy: 4)
        let after3Tau = try XCTUnwrap(ema.update(100, timestampMs: 480))
        XCTAssertGreaterThan(after3Tau, 90, "실제: \(after3Tau)")
    }

    /// **시간 기반 계수의 핵심 근거** — fps가 변해도 같은 시간에 같은 만큼 따라가야 한다.
    func test_분석_fps가_달라도_같은_시간에_같은_만큼_따라간다() throws {
        func trackAfter(stepMs: Int64) throws -> Float {
            let ema = AngleEma(timeConstantMs: 120)
            ema.update(0, timestampMs: 0)
            var t: Int64 = 0
            while t < 240 {
                t += stepMs
                ema.update(100, timestampMs: t)
            }
            return try XCTUnwrap(ema.current)
        }
        let at30fps = try trackAfter(stepMs: 33)   // 약 7프레임
        let at15fps = try trackAfter(stepMs: 66)   // 약 4프레임
        XCTAssertEqual(at30fps, at15fps, accuracy: 3, "fps가 달라도 240ms 후 값이 비슷해야 한다")
    }

    func test_노이즈를_완화한다() throws {
        let ema = AngleEma(timeConstantMs: 120)
        var t: Int64 = 0
        var maxDeviation: Float = 0
        for i in 0..<40 {
            let noisy: Float = 100 + (i % 2 == 0 ? 15 : -15)
            let smoothed = try XCTUnwrap(ema.update(noisy, timestampMs: t))
            if i > 5 { maxDeviation = max(maxDeviation, abs(smoothed - 100)) }
            t += frameMs
        }
        XCTAssertLessThan(maxDeviation, 7.5, "노이즈가 절반 이하로 줄어야 한다 (실제 \(maxDeviation))")
    }

    func test_reset하면_초기_상태로_돌아간다() throws {
        let ema = AngleEma(timeConstantMs: 120)
        ema.update(150, timestampMs: 0)
        ema.reset()
        XCTAssertNil(ema.current)
        XCTAssertEqual(try XCTUnwrap(ema.update(80, timestampMs: frameMs)), 80, accuracy: 0.001)
    }
}

final class MedianWindowTests: XCTestCase {

    func test_창이_비어_있으면_nil이다() {
        XCTAssertNil(MedianWindow(size: 5).median())
    }

    func test_홀수_창은_중앙값을_돌려준다() throws {
        let w = MedianWindow(size: 5)
        for v in [Float(10), 50, 20, 40, 30] { w.push(v) }
        XCTAssertEqual(try XCTUnwrap(w.median()), 30, accuracy: 0.001)
    }

    func test_창이_가득_차기_전에도_값이_나온다() throws {
        let w = MedianWindow(size: 5)
        w.push(10); w.push(20)
        XCTAssertEqual(w.count, 2)
        XCTAssertEqual(try XCTUnwrap(w.median()), 15, accuracy: 0.001)
    }

    func test_창_크기를_넘으면_오래된_값이_밀려난다() throws {
        let w = MedianWindow(size: 3)
        for v in [Float(100), 100, 100, 1, 1, 1] { w.push(v) }
        XCTAssertEqual(w.count, 3)
        XCTAssertEqual(try XCTUnwrap(w.median()), 1, accuracy: 0.001)
    }

    func test_한_프레임_튐을_제거한다() throws {
        let w = MedianWindow(size: 5)
        for v in [Float(100), 101, 999, 99, 100] { w.push(v) }
        XCTAssertEqual(try XCTUnwrap(w.median()), 100, accuracy: 1.5)
    }

    func test_nil은_창에_들어가지_않는다() throws {
        let w = MedianWindow(size: 5)
        w.push(100); w.push(nil); w.push(102)
        XCTAssertEqual(w.count, 2, "nil은 개수에 반영되지 않는다")
        XCTAssertEqual(try XCTUnwrap(w.median()), 101, accuracy: 0.001)
    }

    func test_시간_폭에서_창_크기를_계산한다() {
        XCTAssertEqual(MedianWindow.sizeFor(targetSpanMs: 133, fps: 30), 5)
        XCTAssertEqual(MedianWindow.sizeFor(targetSpanMs: 133, fps: 15), 3)
        XCTAssertEqual(MedianWindow.sizeFor(targetSpanMs: 133, fps: 0), 1)
        XCTAssertEqual(MedianWindow.sizeFor(targetSpanMs: 0, fps: 30), 1)
    }
}

/// **두 스무딩을 나눠 쓰는 이유를 숫자로 붙든다.**
final class SmoothingPhaseLagTests: XCTestCase {

    private func sineSignal(frames: Int) -> [Float] {
        (0..<frames).map { i in
            let phase = Double.pi * Double(i) / Double(frames - 1)
            return Float(170.0 - 100.0 * sin(phase))
        }
    }

    func test_EMA는_최저점을_뒤로_밀지만_median은_밀지_않는다() throws {
        let frames = 90                      // 30fps 기준 3초
        let trueBottom = frames / 2
        let signal = sineSignal(frames: frames)

        let ema = AngleEma(timeConstantMs: 120)
        let median = MedianWindow(size: 5)
        var emaBottomIdx = 0, medBottomIdx = 0
        var emaBottomVal = Float.greatestFiniteMagnitude
        var medBottomVal = Float.greatestFiniteMagnitude

        for (i, v) in signal.enumerated() {
            let e = try XCTUnwrap(ema.update(v, timestampMs: Int64(i) * 33))
            if e < emaBottomVal { emaBottomVal = e; emaBottomIdx = i }
            let m = try XCTUnwrap(median.push(v))
            if m < medBottomVal { medBottomVal = m; medBottomIdx = i }
        }
        let emaLag = emaBottomIdx - trueBottom
        let medLag = medBottomIdx - trueBottom
        XCTAssertGreaterThan(emaLag, 0, "EMA 최저점이 뒤로 밀려야 한다 (지연 \(emaLag) 프레임)")
        XCTAssertLessThan(medLag, emaLag,
                          "median 최저점 지연이 EMA보다 작아야 한다 (median \(medLag), EMA \(emaLag))")
    }

    func test_EMA는_최저_각도를_실제보다_얕게_만든다() throws {
        let signal = sineSignal(frames: 60)
        let trueMin = try XCTUnwrap(signal.min())
        let ema = AngleEma(timeConstantMs: 120)
        var emaMin = Float.greatestFiniteMagnitude
        for (i, v) in signal.enumerated() {
            emaMin = min(emaMin, try XCTUnwrap(ema.update(v, timestampMs: Int64(i) * 33)))
        }
        XCTAssertGreaterThan(emaMin, trueMin,
                             "EMA 최저값(\(emaMin))이 실제 최저값(\(trueMin))보다 얕아야 한다")
    }
}

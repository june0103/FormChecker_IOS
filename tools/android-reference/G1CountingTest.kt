package com.mist.formchecker.poseengine

import java.io.InputStream
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * **G1(rep 카운팅 동등성) 기준값 생성기** — iOS가 센 수와 Android가 센 수를 맞춘다.
 *
 * PRD §3.1 G1은 "동일 입력을 양 플랫폼 파이프라인에 주입 → 카운트 **완전 일치**"다.
 * iOS 쪽은 `PosePipelineSequenceTests.test_G1_기준값을_파일로_남긴다`가 두 파일을 뽑는다.
 *
 * ## 무엇을 비교하고 무엇을 비교하지 않는가
 *
 * | | |
 * |---|---|
 * | ✅ 비교한다 | **원시 무릎 각도 → EMA·중앙값 → 상태머신 → rep 수** |
 * | ❌ 아직 아니다 | 경고 집합(G3). `SquatFormAnalyzer`는 자세가 필요한데 이 CSV에는 각도만 있다 |
 * | ❌ 아직 아니다 | 추론. Phase 0에서 따로 닫혔다(최대 좌표차 7.16e-07) |
 *
 * 🔴 **스무딩된 값을 받지 않는다.** CSV에는 원시 각도만 있고 EMA·중앙값은 양쪽이 각자
 *    돌린다. 스무딩 결과를 넘겨받으면 상태머신만 비교되고, **스무딩 차이가 그대로
 *    숨는다** — 위상 지연이 한 프레임만 달라도 경계에서 rep 수가 갈린다.
 *
 * ## ⚠ 이 테스트가 증명하지 못하는 것
 * 여기서 돌리는 것은 `pose-engine`의 **순수 조각**(EMA·중앙값·상태머신)이고,
 * 실제 운동 화면은 `app` 모듈의 `WorkoutViewModel.onResult`(1661줄 `AndroidViewModel`)가
 * 같은 조각을 엮어 돌린다. **그 둘이 같다는 보장이 Android 쪽에는 없다.**
 *
 * iOS는 이 문제를 파이프라인을 패키지로 꺼내 풀었고
 * (`PoseEngine/PosePipeline.swift`), 최소 체인과 전체 파이프라인이 같은 수를 센다는 것을
 * 테스트로 못 박아 뒀다(`test_최소_체인이_전체_파이프라인과_같은_수를_센다`).
 * **Android도 같은 추출을 하면 이 간극이 닫힌다** — `onResult`의 프레임 처리부를
 * `pose-engine`으로 옮기고 ViewModel은 그것을 부르기만 하면 된다.
 *
 * ## 놓을 자리
 * ```
 * pose-engine/src/test/java/com/mist/formchecker/poseengine/G1CountingTest.kt
 * pose-engine/src/test/resources/g1/g1_frames.csv   ← iOS 저장소 tools/android-reference/
 * pose-engine/src/test/resources/g1/g1_ios.csv      ← 같은 곳
 * ```
 *
 * ## 실행
 * ```
 * ./gradlew :pose-engine:test --tests '*G1CountingTest*'
 * ```
 * 기기가 필요 없다 — 순수 JVM 테스트다.
 */
class G1CountingTest {

    /** `g1_frames.csv` 한 줄. 상태머신에 들어가기 **전**의 값이다. */
    private data class FrameRow(
        val sequence: String,
        val timestampMs: Long,
        val rawKneeAngle: Float?,
        val leftKneeAngle: Float?,
        val rightKneeAngle: Float?,
        val hipAngle: Float?,
        val torsoLeanDegrees: Float?,
        val kneeAsymmetryDegrees: Float?,
        val kneeSpreadRatio: Float?,
        val minLegConfidence: Float,
    )

    @Test
    fun countsMatchIos() {
        val frames = readFrames()
        val iosReps = readIosReps()

        // ⚠ JUnit4는 (message, expected, actual) 순서다 — `kotlin.test`와 반대다.
        assertEquals(
            "두 CSV의 시퀀스 이름이 다르다. 같은 실행에서 나온 짝인지 확인할 것",
            iosReps.keys, frames.keys,
        )

        val mismatches = mutableListOf<String>()
        for ((sequence, rows) in frames) {
            val android = count(rows)
            val ios = iosReps.getValue(sequence)
            println("G1,$sequence,android=$android,ios=$ios")
            if (android != ios) mismatches += "$sequence: Android=$android iOS=$ios"
        }

        // 🔴 하나라도 어긋나면 **전부** 보여준다. 첫 실패에서 멈추면 그것 하나만 고치고
        //    다시 돌리게 되는데, 보통 원인이 하나라 한 번에 보는 편이 빠르다.
        if (mismatches.isNotEmpty()) {
            error(
                buildString {
                    appendLine("🔴 G1 불일치 ${mismatches.size}건 — 같은 입력에서 수가 다르다.")
                    mismatches.forEach { appendLine("  $it") }
                    appendLine()
                    appendLine("임계값을 건드리기 전에 확인할 것:")
                    appendLine("  1. SmoothingConfig (EMA 시정수 / 중앙값 창)가 양쪽 같은가")
                    appendLine("  2. MedianWindow.sizeFor에 넘기는 fps가 양쪽 30인가")
                    appendLine("  3. CountingThresholds 기본값이 양쪽 같은가")
                    appendLine("임계값은 실측 15세션에서 나온 값이다. 한쪽만 고치지 말 것.")
                },
            )
        }
    }

    /** iOS `minimalChainCount`와 **같은 계산**이어야 한다. 한쪽만 고치면 비교가 무의미해진다. */
    private fun count(rows: List<FrameRow>): Int {
        val smoothing = SmoothingConfig()
        val ema = AngleEma(smoothing.emaTimeConstantMs)
        val median = MedianWindow(
            MedianWindow.sizeFor(smoothing.medianWindowMs, ASSUMED_FPS),
        )
        val machine = RepStateMachine(
            thresholds = CountingThresholds(),
            cameraAngle = { CameraAngle.FRONT },
        )

        for (row in rows) {
            machine.update(
                RepFrame(
                    timestampMs = row.timestampMs,
                    rawKneeAngle = row.rawKneeAngle,
                    smoothedKneeAngle = ema.update(row.rawKneeAngle, row.timestampMs),
                    medianKneeAngle = median.push(row.rawKneeAngle),
                    leftKneeAngle = row.leftKneeAngle,
                    rightKneeAngle = row.rightKneeAngle,
                    hipAngle = row.hipAngle,
                    torsoLeanDegrees = row.torsoLeanDegrees,
                    kneeAsymmetryDegrees = row.kneeAsymmetryDegrees,
                    kneeSpreadRatio = row.kneeSpreadRatio,
                    // iOS도 null을 넣는다. 발 표본은 수집 기록에만 쓰이고 카운팅은 읽지 않는다.
                    leftFoot = null,
                    rightFoot = null,
                    minLegConfidence = row.minLegConfidence,
                ),
            )
        }
        return machine.completedReps
    }

    // ── CSV ────────────────────────────────────────────────

    /** 🔴 빈 칸은 **null**이다. 0으로 읽으면 판정 불가가 "문제 없음"이 된다. */
    private fun String.toFloatOrNullIfBlank(): Float? =
        takeIf { it.isNotEmpty() }?.toFloat()

    private fun open(name: String): InputStream =
        javaClass.getResourceAsStream("/g1/$name")
            ?: error(
                "기준값 파일이 없다: /g1/$name\n" +
                    "iOS 저장소 tools/android-reference/ 에서 복사할 것 " +
                    "(PosePipelineSequenceTests가 만든다).",
            )

    private fun readFrames(): Map<String, List<FrameRow>> =
        open("g1_frames.csv").bufferedReader().useLines { lines ->
            lines.drop(1).filter { it.isNotBlank() }.map { line ->
                val c = line.split(",")
                FrameRow(
                    sequence = c[0],
                    timestampMs = c[2].toLong(),
                    rawKneeAngle = c[3].toFloatOrNullIfBlank(),
                    leftKneeAngle = c[4].toFloatOrNullIfBlank(),
                    rightKneeAngle = c[5].toFloatOrNullIfBlank(),
                    hipAngle = c[6].toFloatOrNullIfBlank(),
                    torsoLeanDegrees = c[7].toFloatOrNullIfBlank(),
                    kneeAsymmetryDegrees = c[8].toFloatOrNullIfBlank(),
                    kneeSpreadRatio = c[9].toFloatOrNullIfBlank(),
                    minLegConfidence = c[10].toFloat(),
                )
            }.toList()
        }.groupBy { it.sequence }

    private fun readIosReps(): Map<String, Int> =
        open("g1_ios.csv").bufferedReader().useLines { lines ->
            lines.drop(1).filter { it.isNotBlank() }.map { line ->
                val c = line.split(",")
                c[0] to c[1].toInt()
            }.toMap()
        }

    private companion object {
        /** iOS 하네스가 33ms 간격으로 먹인다. 여기도 같아야 중앙값 창 크기가 같다. */
        const val ASSUMED_FPS = 30.0
    }
}

package com.mist.formchecker.poseengine

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import org.junit.Test
import org.junit.runner.RunWith

/**
 * **Phase 0 기준값 생성기** — iOS 이식의 정답지를 만든다.
 *
 * 고정 PNG 4장을 프로덕션과 **같은 경로**(`RtmPoseEngine.analyze(Bitmap)`)에 넣고
 * 키포인트 26개를 CSV로 떨군다. iOS `KeypointDumpTests`의 출력과 대조해
 * ±0.01 안에 드는지 본다.
 *
 * 이 테스트는 판정을 검증하지 않는다. **두 플랫폼이 같은 숫자를 내는지만** 본다.
 *
 * 놓을 자리:
 *   app/src/androidTest/java/com/mist/formchecker/poseengine/KeypointDumpTest.kt
 * 이미지:
 *   app/src/androidTest/assets/images 에 PNG 4장 (iOS 저장소와 같은 파일 — sha256 대조)
 *
 * 실행:
 *   ./gradlew connectedDebugAndroidTest \
 *     -Pandroid.testInstrumentationRunnerArguments.class=com.mist.formchecker.poseengine.KeypointDumpTest
 *   adb logcat -d -s KeypointDump:I | sed -n 's/.*KPDUMP,//p'
 *
 * ⚠ 파일도 함께 쓰지만, Android 11+의 스코프드 스토리지 때문에 `adb pull`로는 꺼낼 수
 * 없다(shell 사용자가 다른 앱의 외부 디렉터리를 볼 수 없다). **logcat이 1차 경로다.**
 */
@RunWith(AndroidJUnit4::class)
class KeypointDumpTest {

    private val images = listOf(
        "squat_bottom_192x256",   // 리사이즈·패딩 없음 → 색 순서·정규화만 검증
        "squat_bottom_480x640",   // 리사이즈만 (패딩 0) → 실제 카메라 경로
        "squat_bottom_500x500",   // 리사이즈 + 상하 패딩
        "standing_480x640",
    )

    @Test
    fun dumpKeypoints() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        // 모델은 **앱** assets에, 테스트 이미지는 **테스트 APK** assets에 있다.
        val appAssets = instrumentation.targetContext.assets
        val testAssets = instrumentation.context.assets

        val engine = RtmPoseEngine.create(appAssets)
        val rows = StringBuilder("image,index,name,x,y,confidence\n")

        try {
            for (name in images) {
                val options = BitmapFactory.Options().apply {
                    inScaled = false                        // 밀도 스케일링 금지 — 켜지면 크기가 변한다
                    inPreferredConfig = Bitmap.Config.ARGB_8888
                }
                val bitmap = testAssets.open("images/$name.png").use {
                    BitmapFactory.decodeStream(it, null, options)
                } ?: error("이미지를 읽지 못했습니다: $name")

                Log.i(TAG, "META,image,$name,${bitmap.width}x${bitmap.height},config=${bitmap.config}")

                val pose = engine.analyze(bitmap) ?: error("추론 실패: $name")
                Log.i(TAG, "META,infer,$name,ms=%.2f".format(pose.inferenceTimeNanos / 1e6))

                for (kp in pose.keypoints) {
                    val line = "%s,%d,%s,%.6f,%.6f,%.6f".format(
                        name, kp.type.index, kp.type.name, kp.x, kp.y, kp.confidence,
                    )
                    rows.append(line).append('\n')
                    Log.i(TAG, "KPDUMP,$line")
                }
                bitmap.recycle()
            }
        } finally {
            engine.close()
        }

        val dir = instrumentation.targetContext.getExternalFilesDir(null)
            ?: error("외부 파일 디렉터리가 없습니다")
        val out = File(dir, "keypoints_android.csv")
        out.writeText(rows.toString())
        Log.i(TAG, "META,written,${out.absolutePath},${out.length()}")
    }

    private companion object {
        const val TAG = "KeypointDump"
    }
}

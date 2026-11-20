#!/usr/bin/env bash
# Phase 0 게이트를 처음부터 끝까지 재현한다.
#
#   iOS 덤프 → CSV 추출 → Android 덤프 → CSV 내려받기 → 대조
#
# Android 쪽은 이 저장소에 없다. 환경변수로 Android 저장소 경로를 준다:
#   FORMCHECKER_AOS=~/Developer/FormChecker tools/phase0.sh
#
# Android 저장소에 먼저 넣어야 하는 것 (tools/android-reference/ 참고):
#   app/src/androidTest/java/com/mist/formchecker/poseengine/KeypointDumpTest.kt
#   app/src/androidTest/assets/images/*.png   ← 이 저장소의 테스트 이미지와 같은 파일
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/TestData/out"
# ⚠ 같은 이름의 시뮬레이터가 런타임별로 여러 대 있으면 name만으로는 어느 쪽이 잡힐지
#   보장되지 않는다. OS까지 지정하거나 UDID를 쓴다.
SIM="${FORMCHECKER_SIM:-iPhone 17}"
SIM_OS="${FORMCHECKER_SIM_OS:-latest}"
mkdir -p "$OUT"

echo "── 1/4  iOS 키포인트 덤프 ──────────────────────────────"
"$ROOT/tools/fetch_litert.sh"
(
  cd "$ROOT/PoseEngine"
  xcodebuild test -scheme PoseEngine \
    -destination "platform=iOS Simulator,name=$SIM,OS=$SIM_OS" \
    > "$OUT/ios_test.log" 2>&1
)
echo "image,mode,index,name,x,y,confidence" > "$OUT/keypoints_ios.csv"
grep -o "KPDUMP,[^\"]*" "$OUT/ios_test.log" \
  | sed 's/^KPDUMP,//; s/[[:space:]]*$//' \
  | sort -u -t, -k1,1 -k2,2 -k3,3n >> "$OUT/keypoints_ios.csv"
echo "   $(($(wc -l < "$OUT/keypoints_ios.csv") - 1))개 행"
grep -o "META,runtime,[^\"]*" "$OUT/ios_test.log" | sort -u | sed 's/^/   /' 

if [ -z "${FORMCHECKER_AOS:-}" ]; then
  echo
  echo "FORMCHECKER_AOS 가 없어 Android 덤프를 건너뜁니다."
  echo "iOS 덤프만 만들었습니다: $OUT/keypoints_ios.csv"
  exit 0
fi

echo "── 2/4  Android 키포인트 덤프 ──────────────────────────"
export JAVA_HOME="${JAVA_HOME:-/Applications/Android Studio.app/Contents/jbr/Contents/Home}"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
export PATH="$ANDROID_HOME/platform-tools:$PATH"

adb devices | grep -q "device$" || { echo "연결된 기기/에뮬레이터가 없습니다" >&2; exit 1; }
(
  cd "$FORMCHECKER_AOS"
  ./gradlew :app:connectedDebugAndroidTest \
    -Pandroid.testInstrumentationRunnerArguments.class=com.mist.formchecker.poseengine.KeypointDumpTest \
    --console=plain > "$OUT/android_test.log" 2>&1
)

echo "── 3/4  Android CSV 회수 (logcat) ──────────────────────"
# Android 11+ 스코프드 스토리지 때문에 adb pull로는 앱의 외부 디렉터리를 볼 수 없다.
# 테스트가 logcat에도 같은 줄을 남기므로 그쪽에서 회수한다.
echo "image,index,name,x,y,confidence" > "$OUT/keypoints_android.csv"
adb logcat -d -s KeypointDump:I \
  | sed -n 's/.*KPDUMP,//p' | sed 's/[[:space:]]*$//' \
  | sort -u -t, -k1,1 -k2,2n >> "$OUT/keypoints_android.csv"
echo "   $(($(wc -l < "$OUT/keypoints_android.csv") - 1))개 행"

echo "── 4/4  대조 ──────────────────────────────────────────"
python3 "$ROOT/tools/compare_keypoints.py" \
  --android "$OUT/keypoints_android.csv" \
  --ios "$OUT/keypoints_ios.csv" | tee "$OUT/phase0_report.txt"

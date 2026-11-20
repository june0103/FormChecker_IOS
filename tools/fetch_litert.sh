#!/usr/bin/env bash
# LiteRT(TensorFlow Lite) C 프레임워크를 내려받아 PoseEngine/ThirdParty에 둔다.
#
# 왜 저장소에 커밋하지 않는가: xcframework 3개가 180MB가 넘는다.
# 왜 SPM binaryTarget(url:)이 아닌가: SwiftPM은 zip만 받는데 Google은 tar.gz로 배포한다.
#
# 버전은 CocoaPods trunk를 직접 조회해서 고정했다 (검색 요약을 믿지 않는다).
#   curl -s https://trunk.cocoapods.org/api/v1/pods/TensorFlowLiteC
set -euo pipefail

VERSION="2.17.0"
URL="https://dl.google.com/tflite-release/ios/prod/tensorflow/lite/release/ios/release/32/20240729-115310/TensorFlowLiteC/2.17.0/0c10b3543e01f547/TensorFlowLiteC-2.17.0.tar.gz"
SHA256="9667b476015f136e5b332ce040e12822c4ac6d5c58947882ddc809cdff0fb99e"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$ROOT/PoseEngine/ThirdParty"
CACHE="${TMPDIR:-/tmp}/formchecker-litert"

if [ -d "$DEST/TensorFlowLiteC.xcframework" ] && [ "${1:-}" != "--force" ]; then
  echo "이미 있습니다: $DEST (다시 받으려면 --force)"
  exit 0
fi

mkdir -p "$CACHE" "$DEST"
TARBALL="$CACHE/TensorFlowLiteC-$VERSION.tar.gz"

if [ ! -f "$TARBALL" ]; then
  echo "내려받는 중 ($VERSION, 약 80MB)..."
  curl -fL --progress-bar "$URL" -o "$TARBALL"
fi

ACTUAL="$(shasum -a 256 "$TARBALL" | awk '{print $1}')"
if [ "$SHA256" != "PLACEHOLDER" ] && [ "$ACTUAL" != "$SHA256" ]; then
  echo "체크섬 불일치: $ACTUAL" >&2
  exit 1
fi
echo "sha256: $ACTUAL"

rm -rf "$CACHE/extract" && mkdir -p "$CACHE/extract"
tar -xzf "$TARBALL" -C "$CACHE/extract"
SRC="$CACHE/extract/TensorFlowLiteC-$VERSION/Frameworks"

for fw in TensorFlowLiteC TensorFlowLiteCCoreML TensorFlowLiteCMetal; do
  rm -rf "$DEST/$fw.xcframework"
  cp -R "$SRC/$fw.xcframework" "$DEST/"

  # ⚠ Google이 배포하는 프레임워크에는 Info.plist가 없다. CocoaPods는 정적 링크만 하고
  #   번들을 들여다보지 않아 문제가 안 되지만, Xcode 앱 타겟은 빌드 마지막의
  #   `builtin-validationUtility`에서 "did not contain an Info.plist"로 실패한다.
  #   내용은 최소한으로 채운다 — 정적 아카이브라 런타임에 로드되지 않는다.
  for slice in "$DEST/$fw.xcframework"/*/; do
    inner="$slice$fw.framework"
    [ -d "$inner" ] || continue
    [ -f "$inner/Info.plist" ] && continue
    cat > "$inner/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>$fw</string>
  <key>CFBundleIdentifier</key><string>org.tensorflow.$fw</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>$fw</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>MinimumOSVersion</key><string>12.0</string>
</dict>
</plist>
PLIST
  done
  echo "  ✓ $fw.xcframework"
done

echo "완료: $DEST"

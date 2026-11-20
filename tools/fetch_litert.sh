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
  echo "  ✓ $fw.xcframework"
done

echo "완료: $DEST"

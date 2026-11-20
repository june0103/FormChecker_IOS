#!/usr/bin/env swift
//
// 앱 아이콘을 **스플래시와 같은 좌표에서** 그린다.
//
// ## 왜 이미지를 손으로 안 그리고 스크립트로 뽑나
// 아이콘의 체크 모양은 `SplashScreen.swift`의 `JointCheckMotion`이 `progress == 1`에서
// 그리는 것과 **같은 도형**이다. 손으로 그린 PNG를 두면 둘이 조용히 벌어진다 —
// 스플래시 모션이 끝나면서 아이콘과 겹쳐 보이는 자리라 어긋나면 바로 티가 난다.
//
// 좌표를 고치고 싶으면 `SplashScreen.swift`를 먼저 고치고 여기 숫자를 맞춘다.
// 반대로 하지 말 것 — 정본은 화면 쪽이다.
//
// 사용: swift tools/make_app_icon.swift [출력폴더]
//
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size: CGFloat = 1024

func srgb(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1)
}

// Theme.swift의 Palette와 같은 값. 🔴 새 색을 만들지 않는다.
let bgBase = srgb(0x0A0A0F)
let surfaceCard = srgb(0x1A1A22)
let lime = srgb(0xC6FF00)

// ── JointCheckMotion progress=1 상태 ──────────────────────────
let splashPoints = [
    CGPoint(x: 0.22, y: 0.50),
    CGPoint(x: 0.42, y: 0.72),
    CGPoint(x: 0.80, y: 0.26),
]
let rMain: CGFloat = 15.0 / 184.0        // SplashScreen의 radius / symbolSize
let radii: [CGFloat] = [rMain, rMain * 0.9, rMain]
let strokeRatio: CGFloat = 16.0 / 184.0  // SplashScreen의 stroke / symbolSize

// 글리프 bbox는 **점 반지름까지 포함**해서 잡는다. 선만 재면 아래위로 점이 삐져나가
// 아이콘 가장자리에 붙는다.
var minX = CGFloat.greatestFiniteMagnitude, minY = CGFloat.greatestFiniteMagnitude
var maxX = -CGFloat.greatestFiniteMagnitude, maxY = -CGFloat.greatestFiniteMagnitude
for (p, r) in zip(splashPoints, radii) {
    minX = min(minX, p.x - r); maxX = max(maxX, p.x + r)
    minY = min(minY, p.y - r); maxY = max(maxY, p.y + r)
}

/// 글리프가 캔버스에서 차지할 너비. iOS가 둥근 사각형으로 깎아내므로 가장자리를 비운다.
let glyphWidthRatio: CGFloat = 0.62
let k = (size * glyphWidthRatio) / (maxX - minX)
let center = CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)

/// 🔴 Core Graphics는 y가 **아래에서 위로** 간다. SwiftUI 좌표를 그대로 쓰면 체크가
///    뒤집혀서 ✓가 아니라 ✗에 가까운 모양이 된다.
func mapped(_ p: CGPoint) -> CGPoint {
    CGPoint(x: size / 2 + (p.x - center.x) * k,
            y: size / 2 - (p.y - center.y) * k)
}

func render(opaque: Bool, to url: URL) throws {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    // 🔴 기본 아이콘에는 알파 채널이 있으면 안 된다(App Store 심사가 거른다).
    //    다크 변형은 반대로 **배경이 비어 있어야** 시스템이 자기 배경을 깐다.
    let alpha: CGImageAlphaInfo = opaque ? .noneSkipLast : .premultipliedLast
    guard let ctx = CGContext(data: nil, width: Int(size), height: Int(size),
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: space, bitmapInfo: alpha.rawValue) else {
        throw NSError(domain: "icon", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "비트맵 컨텍스트를 못 만들었다"])
    }
    ctx.setShouldAntialias(true)

    if opaque {
        // 위쪽이 살짝 뜬 방사 그라디언트. 평평한 검정이면 어두운 배경화면에서 아이콘
        // 경계가 사라진다.
        let gradient = CGGradient(colorsSpace: space,
                                  colors: [surfaceCard, bgBase] as CFArray,
                                  locations: [0, 1])!
        let origin = CGPoint(x: size / 2, y: size * 0.58)
        ctx.drawRadialGradient(gradient,
                               startCenter: origin, startRadius: 0,
                               endCenter: origin, endRadius: size * 0.78,
                               options: [.drawsAfterEndLocation])
    }

    let points = splashPoints.map(mapped)

    ctx.setStrokeColor(lime)
    ctx.setLineWidth(strokeRatio * k)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.beginPath()
    ctx.move(to: points[0])
    ctx.addLine(to: points[1])
    ctx.addLine(to: points[2])
    ctx.strokePath()

    ctx.setFillColor(lime)
    for (p, r) in zip(points, radii) {
        let rr = r * k
        ctx.fillEllipse(in: CGRect(x: p.x - rr, y: p.y - rr, width: rr * 2, height: rr * 2))
    }

    guard let image = ctx.makeImage(),
          let dest = CGImageDestinationCreateWithURL(
              url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "icon", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "PNG를 못 썼다: \(url.path)"])
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else {
        throw NSError(domain: "icon", code: 3,
                      userInfo: [NSLocalizedDescriptionKey: "PNG 마무리 실패"])
    }
}

let outDir = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : URL(fileURLWithPath: "FormChecker/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

try render(opaque: true, to: outDir.appendingPathComponent("AppIcon-1024.png"))
try render(opaque: false, to: outDir.appendingPathComponent("AppIcon-1024-dark.png"))
print("wrote 2 png → \(outDir.path)")

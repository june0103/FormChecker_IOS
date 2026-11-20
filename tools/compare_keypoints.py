#!/usr/bin/env python3
"""Phase 0 게이트 — Android와 iOS의 키포인트를 대조한다.

사용법:
    python3 tools/compare_keypoints.py \
        --android TestData/out/keypoints_android.csv \
        --ios     TestData/out/keypoints_ios.csv

게이트: 두 플랫폼의 정규화 좌표 차이가 **0.01**을 넘지 않아야 한다.
0.01은 480px 폭에서 약 4.8px이다 — 이보다 벌어지면 임계값 15개의 근거
(자체 수집 15세션)가 더 이상 iOS에 적용된다고 말할 수 없다.

confidence는 게이트가 아니다(기하에 쓰이지 않는다). 다만 0.3 경계를 넘나들면
판정 가능/불가가 갈리므로 따로 보고한다.
"""
from __future__ import annotations

import argparse
import csv
import math
import sys
from collections import defaultdict

GATE = 0.01
CONF_GATE = 0.30  # Pose.minConfidence


def read_rows(path, has_mode):
    out = {}
    with open(path, newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            mode = row["mode"] if has_mode else "-"
            key = (row["image"], mode, int(row["index"]))
            out[key] = (
                row["name"],
                float(row["x"]),
                float(row["y"]),
                float(row["confidence"]),
            )
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--android", required=True)
    ap.add_argument("--ios", required=True)
    ap.add_argument("--gate", type=float, default=GATE)
    ap.add_argument("--top", type=int, default=8, help="이미지당 보여줄 최악 항목 수")
    args = ap.parse_args()

    aos = read_rows(args.android, has_mode=False)
    ios = read_rows(args.ios, has_mode=True)

    modes = sorted({k[1] for k in ios})
    images = sorted({k[0] for k in aos})

    print(f"게이트: 좌표 차이 ≤ {args.gate}  (정규화 좌표)")
    print()

    summary = []
    worst_rows = defaultdict(list)

    for mode in modes:
        for image in images:
            diffs = []
            for index in range(26):
                a = aos.get((image, "-", index))
                i = ios.get((image, mode, index))
                if a is None or i is None:
                    continue
                name, ax, ay, ac = a
                _, ix, iy, ic = i
                dx, dy, dc = abs(ax - ix), abs(ay - iy), abs(ac - ic)
                d = math.hypot(dx, dy)
                diffs.append((d, dx, dy, dc, index, name, ac, ic))
            if not diffs:
                continue
            diffs.sort(reverse=True)
            maxd = diffs[0][0]
            meand = sum(d[0] for d in diffs) / len(diffs)
            exact = sum(1 for d in diffs if d[0] == 0)
            # confidence가 판정 가능/불가 경계를 넘나드는 키포인트
            flipped = [
                d for d in diffs
                if (d[6] >= CONF_GATE) != (d[7] >= CONF_GATE)
            ]
            summary.append((mode, image, len(diffs), maxd, meand, exact, len(flipped)))
            worst_rows[(mode, image)] = diffs[: args.top]

    width = max(len(s[1]) for s in summary)
    print(f"{'mode':9} {'image':{width}} {'n':>3} {'최대':>9} {'평균':>9} {'완전일치':>8} {'conf경계':>8}  판정")
    print("-" * (width + 58))
    failed = []
    for mode, image, n, maxd, meand, exact, flips in summary:
        ok = maxd <= args.gate
        if not ok:
            failed.append((mode, image, maxd))
        print(f"{mode:9} {image:{width}} {n:>3} {maxd:>9.6f} {meand:>9.6f} "
              f"{exact:>8} {flips:>8}  {'통과' if ok else '실패'}")

    print()
    for (mode, image), rows in worst_rows.items():
        if rows[0][0] <= args.gate / 10:
            continue  # 충분히 작으면 자세히 볼 것 없다
        print(f"[{mode} · {image}] 차이가 큰 항목")
        for d, dx, dy, dc, index, name, ac, ic in rows:
            print(f"   {index:>2} {name:<16} d={d:.6f}  dx={dx:.6f} dy={dy:.6f} "
                  f"dconf={dc:.4f} (aos {ac:.3f} / ios {ic:.3f})")
        print()

    if not summary:
        print("비교할 행이 없습니다 — CSV를 확인하세요.")
        return 2

    best = min(summary, key=lambda s: s[3])
    print(f"가장 잘 맞는 조합: mode={best[0]} · {best[1]} (최대 {best[3]:.6f})")
    by_mode = defaultdict(list)
    for mode, image, n, maxd, meand, exact, flips in summary:
        by_mode[mode].append(maxd)
    print()
    print("리샘플링 방식별 최악값:")
    for mode, vals in sorted(by_mode.items()):
        print(f"   {mode:9} {max(vals):.6f}")

    if failed:
        print()
        print(f"게이트 실패 {len(failed)}건 — 의심 순서: ① 색 채널 순서 ② 리샘플링 보간 "
              f"③ letterbox 패딩색 ④ 이중 정규화")
        return 1
    print()
    print("Phase 0 게이트 통과")
    return 0


if __name__ == "__main__":
    sys.exit(main())

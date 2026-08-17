#!/usr/bin/env python3
"""檢查相鄰頁的過場：亮度會不會刺眼，結構差異夠不夠被看見。

這兩件事互相拉扯，必須同時量：

  結構差異太小 → 快速點擊的讀者看不見這一頁，整串等於不存在（規範規則十）
  亮度差異太大 → 瞳孔重新適應，538 次下來眼睛會累

解法是把兩者分開要求：**結構要變，亮度要穩。**
換景別、換角度、換主體（結構變），但維持同一場景的明度與色溫（亮度穩）。

用法：
    python3 tools/check-transitions.py assets/ch/ch01-*.png
    python3 tools/check-transitions.py --json out.json assets/ch/ch08-*.png

門檻是起點，不是定論——真圖出來之後要依實際觀感校正，改 THRESHOLDS 即可。
"""
import argparse
import glob
import json
import sys

import numpy as np
from PIL import Image

# 門檻（待用真圖校正）
THRESHOLDS = {
    "dL_warn": 25.0,    # ΔL*：注意
    "dL_fail": 40.0,    # ΔL*：刺眼
    "dC_warn": 20.0,    # Δ色度：色溫跳動
    "struct_min": 0.08,  # 結構差異下限：低於此值快速點擊看不見
}


def _srgb_to_linear(x):
    return np.where(x <= 0.04045, x / 12.92, ((x + 0.055) / 1.055) ** 2.4)


def load_lab(path, grid=(16, 9)):
    """回傳 (平均 L*, 平均 a*, 平均 b*, 結構向量)。

    結構向量是把畫面降到 16x9 的亮度網格——只留輪廓級的資訊，
    正好對應規範說的「剪影級差異」，不受細節與雜訊影響。
    """
    im = Image.open(path).convert("RGB")
    a = np.asarray(im, dtype=np.float64) / 255.0
    lin = _srgb_to_linear(a)

    # 相對亮度 → L*（感知均勻，ΔL* 才有意義）
    Y = lin @ np.array([0.2126, 0.7152, 0.0722])
    L = np.where(Y > 0.008856, 116.0 * np.cbrt(Y) - 16.0, 903.3 * Y)

    # 粗略色度：用線性 RGB 的對立通道，夠用來抓色溫跳動
    r, g, b = lin[..., 0], lin[..., 1], lin[..., 2]
    ca = (r - g) * 100.0
    cb = ((r + g) / 2.0 - b) * 100.0

    gw, gh = grid
    h, w = L.shape
    ys = np.linspace(0, h, gh + 1).astype(int)
    xs = np.linspace(0, w, gw + 1).astype(int)
    cells = np.array([[L[ys[j]:ys[j + 1], xs[i]:xs[i + 1]].mean()
                       for i in range(gw)] for j in range(gh)])

    return L.mean(), ca.mean(), cb.mean(), cells.ravel()


def compare(p1, p2):
    L1, a1, b1, s1 = load_lab(p1)
    L2, a2, b2, s2 = load_lab(p2)

    dL = abs(L2 - L1)
    dC = float(np.hypot(a2 - a1, b2 - b1))

    # 結構差異：先各自去掉整體明暗（避免亮度差污染結構判定），再比形狀
    n1 = s1 - s1.mean()
    n2 = s2 - s2.mean()
    denom = max(np.abs(n1).max(), np.abs(n2).max(), 1e-6)
    struct = float(np.abs(n2 - n1).mean() / denom)

    flags = []
    if dL >= THRESHOLDS["dL_fail"]:
        flags.append("刺眼")
    elif dL >= THRESHOLDS["dL_warn"]:
        flags.append("亮度跳動")
    if dC >= THRESHOLDS["dC_warn"]:
        flags.append("色溫跳動")
    if struct < THRESHOLDS["struct_min"]:
        flags.append("結構太像")

    return {"a": p1, "b": p2, "dL": round(dL, 1),
            "dC": round(dC, 1), "struct": round(struct, 3), "flags": flags}


def main():
    ap = argparse.ArgumentParser(description="檢查相鄰頁過場的亮度與結構差異")
    ap.add_argument("images", nargs="+", help="依頁序排列的圖檔（可用 glob）")
    ap.add_argument("--json", help="把結果寫成 JSON")
    args = ap.parse_args()

    paths = []
    for pat in args.images:
        hits = sorted(glob.glob(pat))
        paths.extend(hits if hits else [pat])
    if len(paths) < 2:
        sys.exit("至少要兩張圖才能比較過場")

    rows = [compare(paths[i], paths[i + 1]) for i in range(len(paths) - 1)]

    print(f"{'頁':<10}{'ΔL*':>7}{'Δ色度':>8}{'結構':>8}  問題")
    bad = 0
    for i, r in enumerate(rows, 1):
        mark = "、".join(r["flags"]) or "—"
        if r["flags"]:
            bad += 1
        print(f"{i:>3}→{i+1:<6}{r['dL']:>7}{r['dC']:>8}{r['struct']:>8}  {mark}")

    print(f"\n{len(rows)} 個過場，{bad} 個有問題")
    print("ΔL* 越大越刺眼；結構越小越看不出換頁。**兩者要一起看**——"
          "理想是結構大、ΔL* 小。")

    if args.json:
        with open(args.json, "w", encoding="utf-8") as f:
            json.dump(rows, f, ensure_ascii=False, indent=2)
        print(f"已寫入 {args.json}")

    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())

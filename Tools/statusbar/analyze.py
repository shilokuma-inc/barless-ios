#!/usr/bin/env python3
"""Simulator で撮ったスクショから、解像度とステータスバーの要素の位置を測る。
使い方: python3 analyze.py <simshots ディレクトリ> > device-table.json
設定アプリ（背景が単色）のスクショの上端から、背景と違う色の画素（=時刻やアイコン）を拾う。"""
import sys, os, json, glob
from PIL import Image

def scale_of(w):  # 2x は幅 750 / 828 だけ
    return 2 if w in (640, 750, 828) else 3

def measure(path):
    im = Image.open(path).convert('RGB'); W, H = im.size; s = scale_of(W)
    px = im.load()
    bg = px[W // 2, 4 * s]                       # 上端中央は必ず背景
    top_limit = int(70 * s)                       # ステータスバーは 70pt より上にある
    def ink(x, y):
        r, g, b = px[x, y]; return abs(r - bg[0]) + abs(g - bg[1]) + abs(b - bg[2]) > 60
    # Simulator のスクショは四隅の数 px が黒く欠けるので、隅の 4pt 四方は見ない（実機から届いた画像でも 7px 欠けていた）
    _ink = ink
    def ink(x, y): return not (y < 4 * s and (x < 4 * s or x >= W - 4 * s)) and _ink(x, y)
    rows = [y for y in range(top_limit) if any(ink(x, y) for x in range(0, W, 2))]
    if not rows: return None
    # 上から続く最初のかたまり（途切れが 4pt 未満）だけを取る
    band = [rows[0]]
    for y in rows[1:]:
        if y - band[-1] > 4 * s: break
        band.append(y)
    y0, y1 = band[0], band[-1] + 1
    cols = [x for x in range(W) if any(ink(x, y) for y in range(y0, y1))]
    # 横方向に 3pt 以上あいたら別の要素。要素の中のすき間（電波の棒の間・文字の間・電池と突起の間）は 2pt 以下、
    # 要素どうしの間は 4.5pt 以上ある（iPhone 11・13 mini・SE は 4.5〜5pt で、しきい値が 5pt だと 1 かたまりになっていた）
    groups = []
    for x in cols:
        if groups and x - groups[-1][1] <= 3 * s: groups[-1][1] = x
        else: groups.append([x, x])
    def box(g):
        ys = [y for y in range(y0, y1) if any(ink(x, y) for x in range(g[0], g[1] + 1))]
        return {'x': g[0], 'y': ys[0], 'w': g[1] - g[0] + 1, 'h': ys[-1] - ys[0] + 1}
    return {'width': W, 'height': H, 'scale': s, 'ink_top': y0, 'ink_bottom': y1,
            'elements': [box(g) for g in groups]}

def main():
    out = {}
    for p in sorted(glob.glob(os.path.join(sys.argv[1], '*__light-full.png'))):
        dev, rt, _ = os.path.basename(p).split('__')
        m = measure(p)
        low = measure(p.replace('light-full', 'light-low'))
        out[f'{dev}__{rt}'] = {'device': dev, 'runtime': rt, **(m or {}), 'low': low}
    json.dump(out, sys.stdout, ensure_ascii=False, indent=1)

if __name__ == '__main__':  # make-catalog.py から measure() だけを使えるようにする
    main()

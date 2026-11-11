#!/usr/bin/env python3
"""device-table.json から device-table.md を作る。使い方: python3 make-table.py device-table.json > device-table.md"""
import json, sys, collections
d = json.load(open(sys.argv[1]))
def pt(v, s): return f"{v / s:.1f}".rstrip('0').rstrip('.')
rows = collections.defaultdict(list)
for v in d.values(): rows[(v['width'], v['height'])].append(v)
RT = {'iOS-18-6': 'iOS 18.6', 'iOS-26-5': 'iOS 26.5', 'iOS-27-0': 'iOS 27.0', 'iOS-27-1': 'iOS 27.1'}
print("## 1. 解像度ごとの機種\n\n| スクショの大きさ (px) | 倍率 | 画面 (pt) | 撮った機種 |\n| --- | --- | --- | --- |")
for (w, h), vs in sorted(rows.items()):
    s = vs[0]['scale']; devs = sorted({v['device'].replace('iPhone-', 'iPhone ').replace('-', ' ') for v in vs})
    print(f"| {w}×{h} | @{s}x | {pt(w, s)}×{pt(h, s)} | {'、'.join(devs)} |")
print("\n## 2. ステータスバーの要素の位置（pt、左上が原点）\n")
print("「文字とアイコンの上下」は、時刻やアイコンが実際に描かれている範囲。各要素は `x, y, 幅×高さ`。\n")
print("| 機種 | iOS | 大きさ (px) | 文字とアイコンの上下 | 時刻 | 電波 | Wi-Fi | 電池 |\n| --- | --- | --- | --- | --- | --- | --- | --- |")
for k in sorted(d, key=lambda k: (d[k]['width'], d[k]['device'], d[k]['runtime'])):
    v = d[k]; s = v['scale']; e = v['elements']
    b = lambda x: f"{pt(x['x'], s)}, {pt(x['y'], s)}, {pt(x['w'], s)}×{pt(x['h'], s)}"
    if len(e) == 4: cells = [b(x) for x in e]
    elif len(e) == 5: cells = [b(e[3]), b(e[0]), b(e[2]), b(e[4]) + '（ほかにキャリア名 ' + b(e[1]) + '）']  # ホームボタンの機種: 電波・キャリア名・Wi-Fi・時刻・電池の順
    elif len(e) == 1: cells = ['（別の配置。本文を参照）', '', '', '']
    else: cells = [b(e[0])] + ['（分けられなかった）' + b(x) for x in e[1:]] + [''] * (4 - len(e))
    cells = (cells + [''] * 4)[:4]
    print(f"| {v['device'].replace('iPhone-', 'iPhone ').replace('-', ' ')} | {RT.get(v['runtime'], v['runtime'])} | {v['width']}×{v['height']} | {pt(v['ink_top'], s)}〜{pt(v['ink_bottom'], s)} | " + ' | '.join(cells) + " |")

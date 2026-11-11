#!/usr/bin/env python3
"""撮った画像の上端だけを切り出して、テストのフィクスチャと一覧（manifest.json）を作る。
使い方: python3 make-fixtures.py <撮った画像のディレクトリ> <Fixtures ディレクトリ>

- 元の画像は 1 枚 0.5〜2MB あるので、ステータスバーを含む上端 72pt だけを PNG で置く（色はそのまま）
- 元の大きさ（判定に使う）は manifest.json に残す
- Fixtures/realshots/ の画像（実機の上端の切り出し）は手で置いたものをそのまま一覧に足す"""
import glob
import json
import os
import sys

from PIL import Image

STRIP_PT = 72

# capture.sh が simctl status_bar override で指定している値
VARIANTS = {
    'light-full': {'appearance': 'light', 'background': 'solid', 'time': '9:41',
                   'cellularBars': 4, 'wifiBars': 3, 'batteryLevel': 100, 'batteryState': 'charged'},
    'light-low': {'appearance': 'light', 'background': 'solid', 'time': '23:58',
                  'cellularBars': 1, 'wifiBars': 0, 'batteryLevel': 12, 'batteryState': 'discharging'},
    'dark-full': {'appearance': 'dark', 'background': 'solid', 'time': '9:41',
                  'cellularBars': 4, 'wifiBars': 3, 'batteryLevel': 100, 'batteryState': 'charged'},
    'dark-home': {'appearance': 'dark', 'background': 'wallpaper', 'time': '9:41',
                  'cellularBars': 4, 'wifiBars': 3, 'batteryLevel': 100, 'batteryState': 'charged'},
}

# 実機で撮った画像（上端の切り出しだけを置いている）。元の大きさと写っている値は撮影時のメモから
REALSHOTS = {
    '16ProMax_iOS27.2_std-light_top.png': {'device': 'iPhone-16-Pro-Max', 'runtime': 'iOS-27-2', 'variant': 'light-real',
                                           'width': 1320, 'height': 2868, 'scale': 3,
                                           'appearance': 'light', 'background': 'solid', 'time': '3:16'},
    '16ProMax_iOS27.2_std-dark_top.png': {'device': 'iPhone-16-Pro-Max', 'runtime': 'iOS-27-2', 'variant': 'dark-real',
                                          'width': 1320, 'height': 2868, 'scale': 3,
                                          'appearance': 'dark', 'background': 'solid', 'time': '3:16'},
}


def scale_of(width):  # 2x は幅 750 / 828 だけ
    return 2 if width in (640, 750, 828) else 3


def main():
    shots, out = sys.argv[1], sys.argv[2]
    os.makedirs(os.path.join(out, 'simshots'), exist_ok=True)
    entries = []
    for path in sorted(glob.glob(os.path.join(shots, '*.png'))):
        name = os.path.basename(path)
        device, runtime, variant = name[:-4].split('__')
        image = Image.open(path).convert('RGB')
        width, height = image.size
        scale = scale_of(width)
        strip = image.crop((0, 0, width, STRIP_PT * scale))
        strip.save(os.path.join(out, 'simshots', name), optimize=True)
        entries.append({'file': f'simshots/{name}', 'source': 'simulator', 'device': device, 'runtime': runtime,
                        'variant': variant, 'width': width, 'height': height, 'scale': scale, **VARIANTS[variant]})
    for name, meta in sorted(REALSHOTS.items()):
        if os.path.exists(os.path.join(out, 'realshots', name)):
            entries.append({'file': f'realshots/{name}', 'source': 'device', **meta})
    with open(os.path.join(out, 'manifest.json'), 'w') as f:
        json.dump({'stripHeightPt': STRIP_PT, 'fixtures': entries}, f, ensure_ascii=False, indent=1)
        f.write('\n')
    print(f'{len(entries)} 件', file=sys.stderr)


if __name__ == '__main__':
    main()

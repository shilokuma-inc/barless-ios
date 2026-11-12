#!/usr/bin/env python3
"""実測（docs/device-table.json）から DeviceCatalog の JSON を作る。
使い方: python3 make-catalog.py <device-table.json> <Fixtures ディレクトリ> <更新日 YYYY-MM-DD> > device-catalog.json

- 同じ大きさ（px）・同じ iOS の世代で、要素の位置と大きさの差が 1pt 以内の実測を 1 つの配置（layout）にまとめる
- iOS の世代は「iOS 18〜26」と「iOS 27」の 2 つ。位置がほぼ同じ機種（iPhone 11 系・SE）でも、アイコンの形が
  iOS 27 で変わる（電池が枠なしのカプセル形になる など）ので、世代をまたいではまとめない
- 同じ大きさでも配置が違う機種は、別の機種グループにする（例: 1206×2622 の iPhone 17 と iPhone 18 Pro）
- 実機で撮った画像（Fixtures/realshots/）は、manifest.json の情報を使ってここで測って足す
- アイコンを描くための細部（電波の棒 4 本・Wi-Fi の 3 つの帯・電池の本体と突起）も、Fixtures の画像から測って入れる
- 画面の大きさ（インチ）は測れないので、下の SCREEN_INCHES に機種ごとに書く（アプリが「6.3 インチ」のように表示する）
- 単位は px（左上が原点）。pt にするには scale で割る"""
import json
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import analyze  # noqa: E402

GENERATION = {'iOS-18': 'ios18-26', 'iOS-26': 'ios18-26', 'iOS-27': 'ios27'}
GENERATION_ORDER = ['ios18-26', 'ios27']
# 画面の大きさ（対角のインチ。Apple の製品仕様の表記）。新しい機種を足したら、ここにも足す
SCREEN_INCHES = {
    'iPhone-SE-3rd-generation': 4.7,
    'iPhone-13-mini': 5.4,
    'iPhone-11-Pro': 5.8,
    'iPhone-11': 6.1, 'iPhone-12': 6.1, 'iPhone-15': 6.1, 'iPhone-16': 6.1, 'iPhone-16e': 6.1, 'iPhone-17e': 6.1,
    'iPhone-17': 6.3, 'iPhone-18-Pro': 6.3,
    'iPhone-11-Pro-Max': 6.5, 'iPhone-Air': 6.5,
    'iPhone-14-Plus': 6.7, 'iPhone-16-Plus': 6.7,
    'iPhone-16-Pro-Max': 6.9, 'iPhone-18-Pro-Max': 6.9,
}
# 自動判定の対象にしない大きさ（配置が「上端に横 1 列」ではない）
UNSUPPORTED_REASON = {'iPhone-Duo': 'vertical-layout'}


def generation_of(runtime):
    return GENERATION[runtime.rsplit('-', 1)[0]]


def model_name(device):
    return device.replace('iPhone-', 'iPhone ').replace('-', ' ')


def rect(e):
    return {'x': e['x'], 'y': e['y'], 'width': e['w'], 'height': e['h']}


def label(elements, width):
    """測った要素（左から順）に名前を付ける。"""
    if len(elements) == 4:  # ノッチ・Dynamic Island の機種: 時刻が左、アイコンが右
        time, cellular, wifi, battery = elements
        return 'leadingTime', {'time': time, 'cellular': cellular, 'wifi': wifi, 'battery': battery}
    if len(elements) == 5:  # ホームボタンの機種: 電波・キャリア名・Wi-Fi、中央に時刻、右に電池
        cellular, carrier, wifi, time, battery = elements
        assert abs(time['x'] + time['w'] / 2 - width / 2) < width * 0.02, '時刻が中央にない'
        return 'centeredTime', {'time': time, 'cellular': cellular, 'carrier': carrier, 'wifi': wifi, 'battery': battery}
    raise ValueError(f'要素の数が想定と違う: {len(elements)}')


def time_element(elements, width, style):
    if style == 'centeredTime':
        return min(elements, key=lambda e: abs(e['x'] + e['w'] / 2 - width / 2))
    return elements[0]


def runs_of(values):
    """連続する整数をまとめて [最初, 最後] のリストにする。"""
    runs = []
    for value in values:
        if runs and value - runs[-1][1] == 1:
            runs[-1][1] = value
        else:
            runs.append([value, value])
    return runs


def measure_shapes(image_path, parts, scale):
    """アイコンを描くための細部を測る。9:41・電波 4 本・Wi-Fi 3 本の画像（背景は単色）を渡す。"""
    image = Image.open(image_path).convert('RGB')
    px = image.load()
    bg = px[image.width // 2, 4 * scale]

    def ink(x, y):
        return sum(abs(a - b) for a, b in zip(px[x, y], bg)) > 60

    def columns(r):
        return runs_of([x for x in range(r['x'], r['x'] + r['w']) if any(ink(x, y) for y in range(r['y'], r['y'] + r['h']))])

    def rows(r, x0, x1):
        return [y for y in range(r['y'], r['y'] + r['h']) if any(ink(x, y) for x in range(x0, x1 + 1))]

    def box(r, x0, x1, probe=None):
        ys = rows(r, *(probe or (x0, x1)))
        return {'x': x0, 'y': ys[0], 'width': x1 - x0 + 1, 'height': ys[-1] - ys[0] + 1}

    cellular, wifi, battery = parts['cellular'], parts['wifi'], parts['battery']
    bars = columns(cellular)
    assert len(bars) == 4, f'{image_path}: 電波の棒が 4 本に分かれない {bars}'
    center = wifi['x'] + wifi['w'] // 2
    bands = runs_of(rows(wifi, center, center))
    assert len(bands) == 3, f'{image_path}: Wi-Fi の帯が 3 つに分かれない {bands}'
    pieces = columns(battery)
    assert len(pieces) == 2, f'{image_path}: 電池が本体と突起に分かれない {pieces}'
    body, nub = pieces
    # 充電中のマークは本体の上下に 1px はみ出すので、本体の高さは左から 1/4 の列で測る
    quarter = body[0] + (body[1] - body[0]) // 4
    return {
        'cellularBars': [box(cellular, a, b) for a, b in bars],
        'wifiBands': [{'top': a, 'bottom': b + 1} for a, b in bands],
        'batteryBody': box(battery, body[0], body[1], probe=(quarter, quarter)),
        'batteryNub': box(battery, nub[0], nub[1]),
    }


def close(a, b, tolerance):
    """2 つの実測で、名前の付いた要素がすべて tolerance px 以内か。"""
    if a['style'] != b['style'] or a['parts'].keys() != b['parts'].keys():
        return False
    return all(abs(a['parts'][name][key] - b['parts'][name][key]) <= tolerance
               for name in a['parts'] for key in ('x', 'y', 'w', 'h'))


def load_measurements(table_path, fixtures_dir):
    """実測を 1 件ずつの辞書にする（Simulator の表 + 実機の画像）。"""
    measurements, unsupported = [], []
    table = json.load(open(table_path))
    for key, value in sorted(table.items()):
        if value['device'] in UNSUPPORTED_REASON:
            unsupported.append({'pixelWidth': value['width'], 'pixelHeight': value['height'],
                                'models': [model_name(value['device'])], 'reason': UNSUPPORTED_REASON[value['device']]})
            continue
        style, parts = label(value['elements'], value['width'])
        samples = [{'text': '9:41', 'ink': rect(parts['time'])}]
        if value.get('low'):
            samples.append({'text': '23:58', 'ink': rect(time_element(value['low']['elements'], value['width'], style))})
        image = os.path.join(fixtures_dir, 'simshots', f'{key}__light-full.png')
        measurements.append({'source': key, 'device': value['device'], 'generation': generation_of(value['runtime']),
                             'runtime': value['runtime'], 'width': value['width'], 'height': value['height'],
                             'scale': value['scale'], 'inkTop': value['ink_top'], 'inkBottom': value['ink_bottom'],
                             'style': style, 'parts': parts, 'samples': samples,
                             'shapes': measure_shapes(image, parts, value['scale'])})
    manifest = json.load(open(os.path.join(fixtures_dir, 'manifest.json')))
    for fixture in manifest['fixtures']:
        if fixture['source'] != 'device' or fixture['appearance'] != 'light':
            continue
        measured = analyze.measure(os.path.join(fixtures_dir, fixture['file']))
        style, parts = label(measured['elements'], fixture['width'])
        measurements.append({'source': f"{fixture['device']}__{fixture['runtime']}", 'device': fixture['device'],
                             'generation': generation_of(fixture['runtime']), 'runtime': fixture['runtime'],
                             'width': fixture['width'], 'height': fixture['height'], 'scale': fixture['scale'],
                             'inkTop': measured['ink_top'], 'inkBottom': measured['ink_bottom'],
                             'style': style, 'parts': parts, 'samples': [{'text': fixture['time'], 'ink': rect(parts['time'])}],
                             'shapes': measure_shapes(os.path.join(fixtures_dir, fixture['file']), parts, fixture['scale'])})
    return measurements, unsupported


def cluster(measurements):
    """同じ大きさ・同じ iOS の世代・ほぼ同じ配置の実測をまとめる。戻り値は実測のリストのリスト。"""
    clusters = []
    for m in measurements:
        for c in clusters:
            same_screen = (c[0]['width'], c[0]['height'], c[0]['generation']) == (m['width'], m['height'], m['generation'])
            if same_screen and close(c[0], m, m['scale']):
                c.append(m)
                break
        else:
            clusters.append([m])
    return clusters


def device_groups(clusters):
    """同じ大きさの機種を、「共通する iOS の世代ですべて同じ配置」ならば同じ機種グループにする。"""
    cluster_of = {}  # (device, generation) -> cluster の番号
    for index, c in enumerate(clusters):
        for m in c:
            cluster_of[(m['device'], m['generation'])] = index
    by_size = {}
    for c in clusters:
        for m in c:
            by_size.setdefault((m['width'], m['height']), [])
            if m['device'] not in by_size[(m['width'], m['height'])]:
                by_size[(m['width'], m['height'])].append(m['device'])
    group_of = {}
    for (width, height), devices in sorted(by_size.items()):
        groups = []
        for device in sorted(devices):
            mine = {g: cluster_of[(device, g)] for g in GENERATION_ORDER if (device, g) in cluster_of}
            for group in groups:
                other = group['clusters']
                shared = mine.keys() & other.keys()
                if shared and all(mine[g] == other[g] for g in shared):
                    group['devices'].append(device)
                    other.update(mine)
                    break
            else:
                groups.append({'devices': [device], 'clusters': dict(mine)})
        for index, group in enumerate(groups):
            for device in group['devices']:
                group_of[device] = f'{width}x{height}-{chr(ord("a") + index)}'
    return group_of


def main():
    table_path, fixtures_dir, updated_at = sys.argv[1], sys.argv[2], sys.argv[3]
    measurements, unsupported = load_measurements(table_path, fixtures_dir)
    clusters = cluster(measurements)
    group_of = device_groups(clusters)
    layouts = []
    for c in clusters:
        # 同じ配置にまとまった実測を、機種グループごとに 1 件にする
        for group in sorted({group_of[m['device']] for m in c}):
            members = [m for m in c if group_of[m['device']] == group]
            newest = max(members, key=lambda m: [int(n) for n in m['runtime'].split('-')[1:]])
            inches = {SCREEN_INCHES[m['device']] for m in members}
            assert len(inches) == 1, f'{group}: 同じ機種グループに、画面の大きさが違う機種がある {inches}'
            layouts.append({
                'id': f"{group}/{newest['generation']}", 'group': group,
                'models': sorted({model_name(m['device']) for m in members}),
                'generation': newest['generation'],
                'pixelWidth': newest['width'], 'pixelHeight': newest['height'], 'scale': newest['scale'],
                'screenInches': inches.pop(),
                'style': newest['style'], 'inkTop': newest['inkTop'], 'inkBottom': newest['inkBottom'],
                'timeSamples': newest['samples'],
                'cellular': rect(newest['parts']['cellular']), 'wifi': rect(newest['parts']['wifi']),
                'battery': rect(newest['parts']['battery']),
                'carrier': rect(newest['parts']['carrier']) if 'carrier' in newest['parts'] else None,
                **newest['shapes'],
                'sources': sorted(m['source'] for m in members),
            })
    layouts.sort(key=lambda layout: (layout['pixelWidth'], layout['pixelHeight'], layout['id']))
    json.dump({'schemaVersion': 1, 'updatedAt': updated_at, 'unsupported': unsupported, 'layouts': layouts},
              sys.stdout, ensure_ascii=False, indent=1)
    sys.stdout.write('\n')


if __name__ == '__main__':
    main()

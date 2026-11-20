"""Draw a v4 layout (parts, glue links, anchors) to PNG for review. Usage: python Draw-Layout.py layout.json out.png [title]"""
import json, sys
from PIL import Image, ImageDraw
L = json.load(open(sys.argv[1], encoding='utf-8')); out = sys.argv[2]; title = sys.argv[3] if len(sys.argv) > 3 else L['level_id']
pts = [(p['x'], p['y']) for s in L['sources'] for part in s['parts'] for p in part['outline']]
x0, y0 = min(p[0] for p in pts) - 1, min(p[1] for p in pts) - 1; x1, y1 = max(p[0] for p in pts) + 1, max(p[1] for p in pts) + 1
S = 40; W, H = int((x1 - x0) * S), int((y1 - y0) * S) + 30
im = Image.new('RGB', (W, H), (19, 28, 42)); d = ImageDraw.Draw(im)
T = lambda x, y: ((x - x0) * S, H - 30 - (y - y0) * S + 30 - 30)
col = {'wood': (180, 136, 82), 'stone': (131, 145, 152), 'glass': (86, 153, 174), 'rubber': (162, 112, 184)}
for m in L.get('materials', []): col[m['name']] = tuple(m['color'])
cent = {}
for s in L['sources']:
    for part in s['parts']:
        poly = [T(p['x'], p['y']) for p in part['outline']]
        d.polygon(poly, fill=col.get(part['material'], (200, 200, 200)), outline=(230, 236, 240))
        cent[(s['identity'], part['part_id'])] = (sum(p[0] for p in poly) / len(poly), sum(p[1] for p in poly) / len(poly))
        for a in part['anchors']:
            d.line([T(a['a']['x'], a['a']['y']), T(a['b']['x'], a['b']['y'])], fill=(235, 72, 72), width=6)
for g in L['glue']:
    a = cent[(g['a']['source_identity'], g['a']['part_id'])]; b = cent[(g['b']['source_identity'], g['b']['part_id'])]
    d.line([a, b], fill=(110, 231, 183), width=1)
d.text((8, 6), '%s: %d parts, %d glue links (green), anchors red' % (title, sum(len(s['parts']) for s in L['sources']), len(L['glue'])), fill=(230, 236, 240))
im.save(out); print(out, im.size)

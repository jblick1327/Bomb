"""G1 prototype: Darryn's BridgeLevel as an Odin authored layout (opt-in variant; the shipped BridgeLevel.json is untouched).

Principle (ALPHA-SYNC Phase G): every visible tile is a physical part with a real material; overlaps become a partition of
the plane with glue on the shared seam (the continuous member keeps the overlap); front/rear truss duplicates merge onto
the play plane; anchors only where something rests on ground; no visible indestructible piece. Darryn's scene is only read.

Usage: python Build-BridgeG1.py [--out DIR] [--deck wood] [--truss steel] [--band 1.6] [--no-walls|--walls hidden]
Writes DIR/BridgeLevel.json (the G1 layout, named so `--bom-levels DIR` serves it for the BRIDGE entry) and
DIR/BridgeLevel.json.g1-report.json (one row per Darryn tile: which member it became, clipping, glue, anchors).
"""
import argparse, hashlib, json, math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import unity_scene as us

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
SCENE = os.path.join(ROOT, 'Assets', 'Game', 'Scenes', 'BridgeLevel.unity')
C6 = os.path.join(ROOT, 'integration', 'fixtures', 'levels', 'BridgeLevel.json')
GLUE_GAP = 0.2      # native GLUE_FILLET: glue samples bridge a crevice up to 0.2
EPS = 1e-4

# ---------- small convex geometry ----------
def area(p):
    return 0.5 * sum(p[i][0] * p[(i + 1) % len(p)][1] - p[(i + 1) % len(p)][0] * p[i][1] for i in range(len(p)))

def ccw(p):
    return p if area(p) > 0 else p[::-1]

def clip(poly, nx, ny, d):
    """Keep the half-plane nx*x + ny*y <= d (Sutherland-Hodgman, convex input)."""
    out = []
    for i in range(len(poly)):
        a, b = poly[i], poly[(i + 1) % len(poly)]
        fa, fb = nx * a[0] + ny * a[1] - d, nx * b[0] + ny * b[1] - d
        if fa <= 0: out.append(a)
        if (fa < 0 < fb) or (fb < 0 < fa):
            t = fa / (fa - fb); out.append((a[0] + t * (b[0] - a[0]), a[1] + t * (b[1] - a[1])))
    # drop near-duplicate vertices
    res = []
    for v in out:
        if not res or math.hypot(v[0] - res[-1][0], v[1] - res[-1][1]) > 1e-6: res.append(v)
    if len(res) > 1 and math.hypot(res[0][0] - res[-1][0], res[0][1] - res[-1][1]) <= 1e-6: res.pop()
    return res

def seg_dist(p, a, b):
    vx, vy = b[0] - a[0], b[1] - a[1]; L = vx * vx + vy * vy
    t = 0 if L == 0 else max(0, min(1, ((p[0] - a[0]) * vx + (p[1] - a[1]) * vy) / L))
    return math.hypot(p[0] - a[0] - t * vx, p[1] - a[1] - t * vy)

def inside(p, poly):
    return all((poly[(i + 1) % len(poly)][0] - poly[i][0]) * (p[1] - poly[i][1]) - (poly[(i + 1) % len(poly)][1] - poly[i][1]) * (p[0] - poly[i][0]) > EPS for i in range(len(poly)))

def overlap_area(a, b):
    p = a
    for i in range(len(b)):
        x0, y0 = b[i]; x1, y1 = b[(i + 1) % len(b)]
        nx, ny = (y1 - y0), -(x1 - x0)   # outward normal of a CCW edge
        p = clip(p, nx, ny, nx * x0 + ny * y0)
        if len(p) < 3: return 0.0
    return area(p)

def poly_dist(a, b):
    if overlap_area(a, b) > 1e-6: return 0.0
    return min(min(seg_dist(p, b[i], b[(i + 1) % len(b)]) for p in a for i in range(len(b))),
               min(seg_dist(p, a[i], a[(i + 1) % len(a)]) for p in b for i in range(len(a))))

def rect(x0, y0, x1, y1):
    return [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]

def r4(p):
    return [(round(x, 4), round(y, 4)) for x, y in p]

# ---------- read Darryn's bridge ----------
def tiles():
    out = []
    names, transforms = us.load(SCENE)
    for tid, t in transforms.items():
        name = names.get(t['go'], '')
        if not name.startswith('Bridge ') : continue
        m = us.world(transforms, tid)
        c = us.apply(m, (0, 0, 0))
        ax = [us.apply(m, (s, 0, 0)) for s in (-.5, .5)]; ay = [us.apply(m, (0, s, 0)) for s in (-.5, .5)]
        az = [us.apply(m, (0, 0, s)) for s in (-.5, .5)]
        hx = [(ax[1][i] - ax[0][i]) / 2 for i in range(3)]; hy = [(ay[1][i] - ay[0][i]) / 2 for i in range(3)]
        hz = [(az[1][i] - az[0][i]) / 2 for i in range(3)]
        if abs(hx[2]) > 1e-4 or abs(hy[2]) > 1e-4: raise SystemExit('tile rotated out of plane: ' + name)
        xy = ccw([(c[0] + sx * hx[0] + sy * hy[0], c[1] + sx * hx[1] + sy * hy[1]) for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))])
        zs = [c[2] - abs(hz[2]), c[2] + abs(hz[2])]
        out.append({'path': 'Bridge/' + name, 'name': name, 'xy': xy, 'z': zs, 'center': c})
    return out

def also(paths):
    """The other Darryn tiles this part replaces ('|'-joined; native caps the key at 256), so G1 drawing can hide them."""
    text = 'g1-also:' + '|'.join(paths) if paths else ''
    if len(text) > 256: raise SystemExit('cap_key too long: ' + text)
    return text

def bbox(p):
    xs = [v[0] for v in p]; ys = [v[1] for v in p]
    return min(xs), min(ys), max(xs), max(ys)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', default=os.path.join(ROOT, 'integration', 'fixtures', 'levels-g1'))
    ap.add_argument('--deck', default='wood'); ap.add_argument('--truss', default='steel')
    ap.add_argument('--band', type=float, default=1.6)
    ap.add_argument('--steel-toughness', type=float, default=1.25)
    ap.add_argument('--walls', choices=['none', 'hidden'], default='none')
    ap.add_argument('--abutments', action='store_true', help='also anchor the deck ends at x=+-14.5 (bridge rests on banks)')
    args = ap.parse_args()
    c6 = json.load(open(C6, encoding='utf-8'))
    raw = tiles()
    report = []
    # Merge front/rear duplicates: identical XY outline (within 1e-3) -> one member; keep both paths.
    members = []
    for t in sorted(raw, key=lambda t: t['path']):
        key = tuple(round(v, 3) for p in sorted(t['xy']) for v in p)
        for m in members:
            if m['key'] == key: m['paths'].append(t['path']); m['z'].append(t['z']); break
        else:
            members.append({'key': key, 'paths': [t['path']], 'xy': t['xy'], 'z': [t['z']], 'name': t['name']})
    decks = [m for m in members if 'Deck Tile' in m['name']]
    girders = [m for m in members if 'Girder' in m['name']]
    posts = [m for m in members if 'Truss Post' in m['name']]
    braces = [m for m in members if 'Truss Brace' in m['name']]
    assert len(decks) + len(girders) + len(posts) + len(braces) == len(members), 'unclassified bridge tile'
    # Horizontal members are continuous; posts are cut at their faces; braces are clipped to post faces and girder/deck faces.
    horizontals = decks + girders
    # Posts: merge the stacked post segments of one column into runs between horizontals.
    columns = {}
    for p in posts:
        x0, y0, x1, y1 = bbox(p['xy']); columns.setdefault(round((x0 + x1) / 2, 2), []).append(p)
    post_parts = []
    for cx, segs in sorted(columns.items()):
        x0, _, x1, _ = bbox(segs[0]['xy'])
        lo = min(bbox(s['xy'])[1] for s in segs); hi = max(bbox(s['xy'])[3] for s in segs)
        # horizontal bands crossing this column
        bands = sorted((bbox(h['xy'])[1], bbox(h['xy'])[3]) for h in horizontals if bbox(h['xy'])[0] < x1 - EPS and bbox(h['xy'])[2] > x0 + EPS)
        # merge touching bands (deck sits 0.02-0.03 above its girder: treat as one band for cutting)
        merged = []
        for b in bands:
            if merged and b[0] <= merged[-1][1] + GLUE_GAP: merged[-1] = (merged[-1][0], max(merged[-1][1], b[1]))
            else: merged.append(b)
        y = lo; runs = []
        for b0, b1 in merged:
            if b1 <= y or b0 >= hi: continue
            if b0 > y + EPS: runs.append((y, b0))
            y = max(y, b1)
        if hi > y + EPS: runs.append((y, hi))
        for r0, r1 in runs:
            if r1 - r0 < 0.3: continue
            src = [s for s in segs if bbox(s['xy'])[3] > r0 + EPS and bbox(s['xy'])[1] < r1 - EPS]
            post_parts.append({'kind': 'post', 'xy': rect(x0, r0, x1, r1), 'paths': [q for s in src for q in s['paths']],
                               'note': 'post run %.2f..%.2f merged from %d segment tiles (front+rear)' % (r0, r1, len(src))})
    brace_parts = []
    for b in braces:
        poly = b['xy']; notes = []
        bx0, by0, bx1, by1 = bbox(poly)
        # clip between the post faces it spans
        for cx, segs in columns.items():
            px0, _, px1, _ = bbox(segs[0]['xy'])
            if bx0 < px1 and bx1 > px0:
                if (px0 + px1) / 2 < (bx0 + bx1) / 2: poly = clip(poly, -1, 0, -px1); notes.append('x>=%.2f' % px1)
                else: poly = clip(poly, 1, 0, px0); notes.append('x<=%.2f' % px0)
        bx0, by0, bx1, by1 = bbox(poly)
        for h in horizontals:
            hx0, hy0, hx1, hy1 = bbox(h['xy'])
            if overlap_area(ccw(poly), h['xy']) > 1e-6:
                if (hy0 + hy1) / 2 > (by0 + by1) / 2: poly = clip(poly, 0, 1, hy0); notes.append('y<=%.2f' % hy0)
                else: poly = clip(poly, 0, -1, -hy1); notes.append('y>=%.2f' % hy1)
        brace_parts.append({'kind': 'brace', 'xy': ccw(poly), 'paths': b['paths'], 'note': 'diagonal clipped ' + ', '.join(notes)})
    parts = ([{'kind': 'deck', 'xy': d['xy'], 'paths': d['paths'], 'note': 'deck tile kept whole'} for d in decks] +
             [{'kind': 'girder', 'xy': g['xy'], 'paths': g['paths'], 'note': 'girder kept whole (front+rear merged)'} for g in girders] +
             post_parts + brace_parts)
    for p in parts: p['xy'] = r4(ccw(p['xy']))
    # sanity: no overlaps
    for i, a in enumerate(parts):
        for b in parts[:i]:
            ov = overlap_area(a['xy'], b['xy'])
            if ov > 1e-5: raise SystemExit('overlap %.5f between %s and %s' % (ov, a['paths'][0], b['paths'][0]))
    # glue: every pair within the native glue fillet
    glue = []
    for i, a in enumerate(parts):
        for j in range(i):
            if poly_dist(a['xy'], parts[j]['xy']) <= GLUE_GAP - 0.01: glue.append((j, i))
    # anchors: only the post feet that rest on the riverbed (lowest edge of each column), optional abutments
    floor_y = min(bbox(p['xy'])[1] for p in post_parts)
    material = {'deck': args.deck, 'girder': args.truss, 'post': args.truss, 'brace': args.truss}
    sources = []; half = args.band / 2
    for n, p in enumerate(parts, 1):
        x0, y0, x1, y1 = bbox(p['xy'])
        anchors = []
        if p['kind'] == 'post' and abs(y0 - floor_y) < EPS: anchors.append({'a': {'x': x0, 'y': y0}, 'b': {'x': x1, 'y': y0}})
        if args.abutments and p['kind'] == 'deck' and (abs(x0 + 14.5) < EPS or abs(x1 - 14.5) < EPS):
            ex = x0 if abs(x0 + 14.5) < EPS else x1
            anchors.append({'a': {'x': ex, 'y': y0}, 'b': {'x': ex, 'y': y1}} if ex == x1 else {'a': {'x': ex, 'y': y1}, 'b': {'x': ex, 'y': y0}})
        key = 'g1:' + p['paths'][0]
        sources.append({'identity': n, 'asset_key': key, 'visual_hash': hashlib.sha256(key.encode()).hexdigest(),
                        'cap_key': also(p['paths'][1:]),
                        'group_to_rest': [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1],
                        'depth': {'x': -half, 'y': half}, 'motion': 'anchored' if anchors else 'dynamic', 'damage': 'destructible',
                        'parts': [{'part_id': 1, 'material': material[p['kind']], 'outline': [{'x': x, 'y': y} for x, y in p['xy']], 'anchors': anchors}]})
        p['identity'] = n; p['anchors'] = len(anchors)
    level = {k: c6[k] for k in ('kind', 'version', 'seed', 'gameplay_config_id', 'gameplay_config', 'simulation_bounds', 'kill_bounds',
                                'camera_bounds', 'aim_bounds', 'fragment_cull_bounds', 'spawns', 'bombs')}
    level['level_id'] = 'bomb-bridge-g1-v1'; level['catalog_id'] = 'bomb-bridge-g1-v1-visual-v1'
    level['materials'] = [] if args.truss in ('wood', 'stone', 'glass', 'rubber') else [
        {'name': args.truss, 'base': 'stone', 'toughness': args.steel_toughness, 'blast_resistance': 4, 'strip_thickness': 0.2,
         'shock_loss': 4, 'flexibility': 0.5, 'color': [52, 66, 86]}]
    if args.walls == 'hidden':
        for w in [s for s in c6['sources'] if s['motion'] == 'fixed']:
            w = json.loads(json.dumps(w)); w['identity'] = len(sources) + 1; sources.append(w)
    level['sources'] = sources
    level['next_identity'] = len(sources) + 1
    level['glue'] = [{'a': {'source_identity': parts[a]['identity'], 'part_id': 1}, 'b': {'source_identity': parts[b]['identity'], 'part_id': 1}} for a, b in glue]
    level['allowed_overlaps'] = []
    order = ['kind', 'version', 'seed', 'next_identity', 'level_id', 'gameplay_config_id', 'catalog_id', 'gameplay_config', 'simulation_bounds',
             'kill_bounds', 'camera_bounds', 'aim_bounds', 'fragment_cull_bounds', 'spawns', 'bombs', 'materials', 'sources', 'glue', 'allowed_overlaps']
    level = {k: level[k] for k in order}
    os.makedirs(args.out, exist_ok=True)
    out = os.path.join(args.out, 'BridgeLevel.json')
    text = json.dumps(level, separators=(',', ':'))
    if len(text.encode()) > 200000: raise SystemExit('layout exceeds 200000 bytes')
    open(out, 'w', encoding='utf-8', newline='\n').write(text)
    rows = [{'identity': p['identity'], 'kind': p['kind'], 'material': material[p['kind']], 'darryn_tiles': p['paths'], 'note': p['note'],
             'outline': p['xy'], 'area': round(area(p['xy']), 4), 'anchors': p['anchors'],
             'glued_to': sorted(parts[b if a == i else a]['identity'] for a, b in glue if i in (a, b))} for i, p in enumerate(parts)]
    summary = {'scene': os.path.relpath(SCENE, ROOT), 'darryn_tiles': len(raw), 'members_after_merge': len(members), 'parts': len(parts),
               'by_kind': {k: sum(1 for p in parts if p['kind'] == k) for k in ('deck', 'girder', 'post', 'brace')},
               'glue_links': len(glue), 'anchored_parts': sum(1 for p in parts if p['anchors']), 'walls': args.walls,
               'abutments': args.abutments, 'band': args.band, 'materials': material, 'bytes': len(text.encode()),
               'tiles_unused': sorted(set(t['path'] for t in raw) - set(q for p in parts for q in p['paths']))}
    json.dump({'summary': summary, 'parts': rows}, open(out + '.g1-report.json', 'w', encoding='utf-8'), indent=1)
    print(json.dumps(summary, indent=1))

if __name__ == '__main__':
    main()

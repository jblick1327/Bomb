"""Minimal reader for Unity scene YAML: GameObject names and world transforms (read-only; never writes scenes)."""
import re, math

def _vec(s):
    return {k: float(v) for k, v in re.findall(r'(\w+): ([-\d.eE+]+)', s)}

def load(path):
    docs, cur = {}, None
    for line in open(path, encoding='utf-8'):
        m = re.match(r'--- !u!(\d+) &(-?\d+)', line)
        if m:
            cur = {'type': int(m.group(1)), 'id': m.group(2), 'lines': []}
            docs[cur['id']] = cur
        elif cur is not None:
            cur['lines'].append(line.rstrip('\n'))
    names, transforms = {}, {}
    for d in docs.values():
        text = '\n'.join(d['lines'])
        if d['type'] == 1:
            m = re.search(r'^  m_Name: (.*)$', text, re.M)
            names[d['id']] = m.group(1) if m else ''
        elif d['type'] == 4:
            g = re.search(r'm_GameObject: \{fileID: (-?\d+)\}', text).group(1)
            father = re.search(r'm_Father: \{fileID: (-?\d+)\}', text).group(1)
            pos = _vec(re.search(r'm_LocalPosition: \{([^}]*)\}', text).group(1))
            rot = _vec(re.search(r'm_LocalRotation: \{([^}]*)\}', text).group(1))
            scl = _vec(re.search(r'm_LocalScale: \{([^}]*)\}', text).group(1))
            transforms[d['id']] = {'go': g, 'father': father, 'pos': pos, 'rot': rot, 'scale': scl}
    return names, transforms

def _qmat(q):
    x, y, z, w = q['x'], q['y'], q['z'], q['w']
    return [[1-2*(y*y+z*z), 2*(x*y-z*w), 2*(x*z+y*w)],
            [2*(x*y+z*w), 1-2*(x*x+z*z), 2*(y*z-x*w)],
            [2*(x*z-y*w), 2*(y*z+x*w), 1-2*(x*x+y*y)]]

def local_matrix(t):
    r = _qmat(t['rot']); s = t['scale']; p = t['pos']
    m = [[r[i][0]*s['x'], r[i][1]*s['y'], r[i][2]*s['z'], [p['x'], p['y'], p['z']][i]] for i in range(3)]
    return m + [[0, 0, 0, 1]]

def mul(a, b):
    return [[sum(a[i][k]*b[k][j] for k in range(4)) for j in range(4)] for i in range(4)]

def world(transforms, tid):
    t = transforms[tid]; m = local_matrix(t)
    while t['father'] != '0' and t['father'] in transforms:
        t = transforms[t['father']]; m = mul(local_matrix(t), m)
    return m

def apply(m, p):
    return [sum(m[i][k]*v for k, v in enumerate(list(p)+[1])) for i in range(3)]

def objects(path):
    names, transforms = load(path)
    out = {}
    for tid, t in transforms.items():
        n = names.get(t['go'], '')
        out.setdefault(n, []).append(world(transforms, tid))
    return out

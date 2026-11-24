"""Compare freshly generated captures against accepted ones.

Scene-only captures must be byte-identical. World captures changed from v3 to v4 (a
`players` array replaces `player`): their Scene section must be byte-identical, and
players[0], bombs, rain, settings and tick must decode bit-equal to the v3 values.

usage: compare-captures.py ACCEPTED_DIR FRESH_DIR [--manifest out.json] [--label name]
"""
import hashlib
import json
import sys
from pathlib import Path


def scene_section(text):
    key = '"scene":'
    start = text.index(key) + len(key)
    while text[start] in ' \n\t\r':
        start += 1
    assert text[start] == '{'
    depth, in_string, i = 0, False, start
    while i < len(text):
        c = text[i]
        if in_string:
            if c == '\\':
                i += 1
            elif c == '"':
                in_string = False
        elif c == '"':
            in_string = True
        elif c == '{':
            depth += 1
        elif c == '}':
            depth -= 1
            if depth == 0:
                return text[start:i + 1]
        i += 1
    raise ValueError('unterminated scene')


def tokens(text):
    # Numbers stay as their written tokens, so equal text means equal bits.
    return json.loads(text, parse_float=str, parse_int=str, parse_constant=str)


def compare(old_path, new_path):
    old, new = old_path.read_bytes(), new_path.read_bytes()
    if old == new:
        return 'byte-identical', hashlib.sha256(old).hexdigest()
    old_text, new_text = old.decode(), new.decode()
    old_json, new_json = tokens(old_text), tokens(new_text)
    if old_json.get('version') != '3' or new_json.get('version') != '4':
        return 'DIFFERENT (not a v3 -> v4 change)', None
    if scene_section(old_text) != scene_section(new_text):
        return 'DIFFERENT scene section', None
    first = new_json['players'][0]
    player = dict(first)
    index = player.pop('index')
    radius = player.pop('blast_radius')
    if index != '0' or radius != new_json['settings']['blast_radius']:
        return 'DIFFERENT player 0 index/blast_radius', None
    if player != old_json['player']:
        return 'DIFFERENT player 0', None
    # Step 2b added an optional bomb "id" (written only when it is not the sequential default).
    for bomb in new_json['bombs']:
        bomb.pop('id', None)
    for key in ('bombs', 'rain', 'settings', 'tick'):
        if old_json[key] != new_json[key]:
            return 'DIFFERENT ' + key, None
    return 'v3->v4 scene byte-identical, player 0/bombs/rain/settings/tick bit-equal', hashlib.sha256(scene_section(new_text).encode()).hexdigest()


def main():
    accepted, fresh = Path(sys.argv[1]), Path(sys.argv[2])
    manifest, label = None, accepted.name
    if '--manifest' in sys.argv:
        manifest = Path(sys.argv[sys.argv.index('--manifest') + 1])
    if '--label' in sys.argv:
        label = sys.argv[sys.argv.index('--label') + 1]
    rows, bad = [], 0
    for old_path in sorted(accepted.rglob('*.json')):
        relative = old_path.relative_to(accepted)
        new_path = fresh / relative
        if not new_path.exists():
            rows.append(dict(fixture=f'{label}/{relative.as_posix()}', status='MISSING'))
            bad += 1
            continue
        status, digest = compare(old_path, new_path)
        ok = not status.startswith('DIFFERENT')
        bad += 0 if ok else 1
        rows.append(dict(fixture=f'{label}/{relative.as_posix()}', accepted=str(old_path), fresh=str(new_path),
                         bytes_accepted=old_path.stat().st_size, bytes_fresh=new_path.stat().st_size,
                         status=status, ok=ok, scene_sha256=digest))
    for row in rows:
        print(('OK   ' if row.get('ok') else 'FAIL ') + row['fixture'] + '  ' + row['status'])
    print(f'{len(rows) - bad}/{len(rows)} match')
    if manifest:
        manifest.write_text(json.dumps(rows, indent=2) + '\n')
    sys.exit(1 if bad else 0)


main()

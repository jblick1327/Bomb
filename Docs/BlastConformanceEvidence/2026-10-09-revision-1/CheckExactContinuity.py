"""Independent rational clipping of recorded binary64 coordinates and one binary64 ray."""
import json
from fractions import Fraction as F
from pathlib import Path
base=Path(__file__).resolve().parent
data=json.loads((base/'continuity-case.json').read_text(encoding='utf-8-sig'))
dx,dy=map(F.from_float,data['direction'])
def spans(cells):
    out=[]
    for cell in cells:
        p=[tuple(map(F.from_float,q)) for q in cell];lo,hi,miss=F(0),None,False
        for (ax,ay),(bx,by) in zip(p,p[1:]+p[:1]):
            ex,ey=bx-ax,by-ay;den=ex*dy-ey*dx;num=ex*ay-ey*ax
            if den==0:miss|=num>0
            elif den>0:lo=max(lo,num/den)
            else:hi=num/den if hi is None else min(hi,num/den)
        if not miss and hi is not None and hi>lo:out.append((lo,hi))
    merged=[]
    for lo,hi in sorted(out):
        if not merged or lo>merged[-1][1]:merged.append((lo,hi))
        else:merged[-1]=(merged[-1][0],max(merged[-1][1],hi))
    return merged
after={b['id']:spans(b['cells']) for b in data['after']};pieces=[]
for b in data['before']:
    for lo,hi in spans(b['cells']):
        cursor=lo
        for a,z in after[b['id']]:
            a,z=max(a,lo),min(z,hi)
            if z<=a:continue
            if a>cursor:pieces.append((cursor,a,False,b['id']))
            pieces.append((a,z,True,b['id']));cursor=max(cursor,z)
        if hi>cursor:pieces.append((cursor,hi,False,b['id']))
blocked=False;violation=False
for lo,hi,retained,_ in sorted(pieces):
    if retained:blocked=True
    elif blocked:violation=True
report={'exact_rational_buried_removal':violation,'theta':data['theta'],
    'intervals':[{'lo':float(a),'hi':float(b),'length':float(b-a),'retained':c,'id':d} for a,b,c,d in sorted(pieces)]}
(base/'exact-continuity-result.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
print(json.dumps(report,indent=2))

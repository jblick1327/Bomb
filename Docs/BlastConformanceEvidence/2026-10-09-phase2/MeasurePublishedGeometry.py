"""Independent measurements of saved canonical outputs; never imports the evaluator."""
import json, math
from pathlib import Path

base = Path(__file__).parent / 'states'
def load(name): return json.loads((base / name).read_text(encoding='utf-8-sig'))
def area(cell):
    pts = cell['points']
    return abs(sum(p['x'] * q['y'] - p['y'] * q['x'] for p,q in zip(pts,pts[1:]+pts[:1]))) / 2
def intervals(body, theta):
    result, dx, dy = [], math.cos(theta), math.sin(theta)
    c,s = math.cos(body['rotationRadians']),math.sin(body['rotationRadians'])
    for cell in body['cells']:
        pts = [(body['position']['x']+c*p['x']-s*p['y'],body['position']['y']+s*p['x']+c*p['y']) for p in cell['points']]
        lo,hi,miss = 0,math.inf,False
        for a,b in zip(pts,pts[1:]+pts[:1]):
            ex,ey=b[0]-a[0],b[1]-a[1]; den=ex*dy-ey*dx; h=ex*a[1]-ey*a[0]
            if abs(den)<1e-14:
                miss |= h>1e-12
            elif den>0: lo=max(lo,h/den)
            else: hi=min(hi,h/den)
        if not miss and hi>lo+1e-10: result.append((lo,hi))
    return sorted(result)

before,after=load('thin-before.json'),load('thin-after.json')
cover=next(b for b in after['materials'] if b['selection']['material']['id']=='cover')
core=next(b for b in after['materials'] if b['selection']['material']['id']=='core')
old_cover=next(b for b in before['materials'] if b['selection']['material']['id']=='cover')
old_core=next(b for b in before['materials'] if b['selection']['material']['id']=='core')
theta_max=math.acos(1/1.05)
measurements=[]; max_deficit=0; min_deficit=math.inf
for i in range(10001):
    theta=-theta_max+2*theta_max*i/10000
    boundary=min(s[0] for s in intervals(cover,theta))
    expected=0.21+0.8/math.cos(theta)
    deficit=expected-boundary
    max_deficit=max(max_deficit,deficit); min_deficit=min(min_deficit,deficit)
    if i in (0,2500,5000,7500,10000): measurements.append({'degrees':math.degrees(theta),'expected':expected,'actual':boundary,'deficit':deficit})
a,b=0.21,0.8
analytic_area=a*a*theta_max+2*a*b*math.log(1/math.cos(theta_max)+math.tan(theta_max))+(b*b-1)*math.tan(theta_max)
actual_area=sum(map(area,old_cover['cells']))-sum(map(area,cover['cells']))
print(json.dumps({'thin_layer':{
    'probes':10001,'maximum_radial_deficit':max_deficit,'minimum_radial_deficit':min_deficit,
    'independent_analytic_removed_area':analytic_area,'actual_removed_area':actual_area,
    'removed_area_deficit':analytic_area-actual_area,'area_deficit_upper_bound_from_1mm':2*theta_max*1.05*0.001,
    'central_remaining_thickness':max(s[1] for s in intervals(cover,0))-min(s[0] for s in intervals(cover,0)),
    'result_cells':len(cover['cells']),'core_geometry_identical':core['cells']==old_core['cells'],
    'core_id_identical':core['id']==old_core['id'],'core_revision_identical':core['geometryRevision']==old_core['geometryRevision'],
    'selected_probes':measurements}},indent=2))

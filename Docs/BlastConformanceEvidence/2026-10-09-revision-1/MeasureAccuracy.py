"""Independent algebra and ray clipping of published snapshots; no evaluator imports."""
import json,math,struct,statistics
from pathlib import Path
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.patches import Polygon
base=Path(__file__).resolve().parent
def load(name):return json.loads((base/'states'/name).read_text(encoding='utf-8-sig'))
def f32(v):return struct.unpack('f',struct.pack('f',v))[0]
def polygons(bodies,origin=(0,0)):
    out=[]
    for body in bodies:
        c,s=f32(math.cos(f32(body['rotationRadians']))),f32(math.sin(f32(body['rotationRadians'])))
        px,py=f32(body['position']['x'])-origin[0],f32(body['position']['y'])-origin[1]
        for cell in body['cells']:
            out.append([(px+c*f32(p['x'])-s*f32(p['y']),py+s*f32(p['x'])+c*f32(p['y'])) for p in cell['points']])
    return out
def area(poly):return abs(sum(x*v-y*u for (x,y),(u,v) in zip(poly,poly[1:]+poly[:1])))/2
def intervals(polys,theta):
    dx,dy=math.cos(theta),math.sin(theta);spans=[]
    for poly in polys:
        lo,hi,miss=0,math.inf,False
        for (x,y),(u,v) in zip(poly,poly[1:]+poly[:1]):
            ex,ey=u-x,v-y;den=ex*dy-ey*dx;h=ex*y-ey*x
            if abs(den)<1e-14:miss|=h>1e-12
            elif den>0:lo=max(lo,h/den)
            else:hi=min(hi,h/den)
        if not miss and hi>lo+1e-10:spans.append((lo,hi))
    merged=[]
    for lo,hi in sorted(spans):
        if not merged or lo>merged[-1][1]+1e-10:merged.append((lo,hi))
        else:merged[-1]=(merged[-1][0],max(merged[-1][1],hi))
    return merged
def material(snapshot,name):return [b for b in snapshot['materials'] if b['selection']['material']['id']==name]
def probes(polys,a,b,expected,beta=0,count=10001):
    values=[]
    for i in range(count):
        theta=a+(b-a)*(i+0.5)/count;spans=intervals(polys,theta+beta)
        assert spans,(theta,a,b)
        values.append(expected(theta)-spans[0][0])
    result={'probes':count,'maximum_radial_deficit_m':max(values),'minimum_radial_deficit_m':min(values)}
    assert max(values)<=0.001+0.000002,result
    assert min(values)>=-0.000002,result
    return result
def logsec(t):return math.log(1/math.cos(t)+math.tan(t))
def partial_primitive(t,a):return a*a*t+1.6*a*logsec(t)-0.36*math.tan(t)
def cover8_area():
    breach=math.acos(0.75);maximum=math.atan(6);lo,hi=math.atan(3),maximum
    for _ in range(70):
        t=(lo+hi)/2
        if 30/math.sin(t)-4/math.cos(t)>8:lo=t
        else:hi=t
    top=(lo+hi)/2
    def top_primitive(t):return -36/math.tan(t)-math.tan(t)
    return 3*math.tan(breach)+partial_primitive(top,1.6)-partial_primitive(breach,1.6)+top_primitive(maximum)-top_primitive(top),top

def wide_reach(radius,theta):
    # Independent rectangle slab algebra and monotone piecewise-linear inversion.
    c,s=math.cos(theta),abs(math.sin(theta))
    if c<=0:return radius
    spent=0
    for front,back,resistance in ((1,2,4),(2,4,1)):
        lo,hi=front/c,min(back/c,6/s if s else math.inf)
        if hi<=lo:continue
        entry_cost=lo+spent
        if radius<=entry_cost:return radius-spent
        exit_cost=hi+spent+resistance*(hi-lo)
        if radius<=exit_cost:return lo+(radius-entry_cost)/(1+resistance)
        spent+=resistance*(hi-lo)
    return radius-spent

def weighted(spans):return sum((b*b-a*a)/2 for a,b in spans)
def intersection(a,b):return [(max(x,u),min(y,v)) for x,y in a for u,v in b if min(y,v)>max(x,u)]
def symmetric_difference(old,current,radius):
    # Integrate the independent expected and actual radial interval sets. Doubling
    # resolution reports convergence; this is measurement, not an interval proof.
    values=[];limit=math.atan(6)
    for count in (4000,8000,16000):
        deficit=excess=0
        for i in range(count):
            theta=-limit+2*limit*(i+.5)/count
            reach=wide_reach(radius,theta)
            expected=[(max(a,reach),b) for a,b in intervals(old,theta) if b>max(a,reach)]
            actual=intervals(current,theta)
            common=weighted(intersection(expected,actual))
            deficit+=max(0,weighted(actual)-common)
            excess+=max(0,weighted(expected)-common)
        values.append({'rays':count,'undercut_area_m2':deficit*2*limit/count,
            'overcut_area_m2':excess*2*limit/count,'symmetric_difference_area_m2':(deficit+excess)*2*limit/count})
    convergence=abs(values[-1]['symmetric_difference_area_m2']-values[-2]['symmetric_difference_area_m2'])
    assert values[-1]['symmetric_difference_area_m2']+convergence<=2*math.pi*radius*.001,values
    return {'quadrature':values,'last_doubling_difference_m2':convergence,'area_enclosure_m2':2*math.pi*radius*.001}
report={};fig,axes=plt.subplots(1,2,figsize=(11,5),layout='constrained')
for radius in (5,8):
    before,after=load(f'benchmark-wide{radius}-before.json'),load(f'benchmark-wide{radius}-after.json')
    measured={}
    for name in ('cover','core'):
        old=polygons(material(before,name));current=polygons(material(after,name))
        removed=sum(map(area,old))-sum(map(area,current))
        if radius==5:
            t=math.acos(0.2);analytic=partial_primitive(t,1) if name=='cover' else 0
            if name=='cover':p=probes(current,-t,t,lambda t:1+0.8/math.cos(t))
            else:p={'geometry_identical':material(before,name)[0]['cells']==material(after,name)[0]['cells']}
        else:
            t=math.acos(0.75);analytic,top=cover8_area()
            if name=='core':analytic=16*t-8*logsec(t)-3*math.tan(t);p=probes(current,-t,t,lambda t:4-1/math.cos(t))
            else:p=probes(current,t+0.001,top-0.001,lambda t:1.6+0.8/math.cos(t))
        p.update(actual_removed_area_m2=removed,analytic_removed_area_m2=analytic,
            area_deficit_m2=analytic-removed,area_deficit_enclosure_from_1mm_m2=2*math.pi*radius*0.001,
            result_bodies=len(material(after,name)),result_cells=sum(len(b['cells']) for b in material(after,name)))
        p['central_retained_intervals_m']=intervals(current,0)
        if radius==5 and name=='cover':p['central_penetration_m']=p['central_retained_intervals_m'][0][0]-1
        if radius==8 and name=='core':p['central_penetration_m']=p['central_retained_intervals_m'][0][0]-2
        if radius==8 and name=='cover':
            section=[[(x-2,y) for x,y in poly] for poly in current]
            p['cover_back_opening_half_heights_m']=[intervals(section,t)[0][0] for t in (math.pi/2,3*math.pi/2)]
            p['analytic_cover_back_opening_half_height_m']=2*math.sqrt((8/6)**2-1)
        p['symmetric_difference']=symmetric_difference(old,current,radius)
        assert abs(analytic-removed)<=2*math.pi*radius*0.001,p
        measured[name]=p
        ax=axes[0 if radius==5 else 1]
        for poly in current:ax.add_patch(Polygon(poly,facecolor='#89adc8' if name=='cover' else '#e7b669',edgecolor='none'))
        for poly in old:ax.add_patch(Polygon(poly,fill=False,edgecolor='#333333',linewidth=0.8))
    ax.scatter([0],[0],c='#c13b30',s=25);ax.set(xlim=(-0.2,4.4),ylim=(-2.5,2.5),aspect='equal',xlabel='x (m)',ylabel='y (m)',title=f'Published geometry, radius {radius} m')
    ax.grid(alpha=0.2);report[f'wide{radius}']=measured
fig.savefig(base/'published-wide-geometry.png',dpi=180);plt.close(fig)
# Rotated/transformed full world: an independently transformed actual boundary.
before,after=load('benchmark-wide8-rot37-before.json'),load('benchmark-wide8-rot37-after.json')
old=material(before,'core')[0];beta=old['rotationRadians'];origin=(12,-9)
report['rotated37_core']=probes(polygons(material(after,'core'),origin),-math.acos(.75)+.001,math.acos(.75)-.001,lambda t:4-1/math.cos(t),beta)
for degrees in (0,37):
    before,after=load(f'benchmark-narrow{degrees}-before.json'),load(f'benchmark-narrow{degrees}-after.json')
    current=polygons(material(after,'clay'));phi=math.radians(degrees)
    def reach(theta):
        # Oriented rectangle slab algebra, then the closed-form cost for its sole layer.
        dx,dy=math.cos(theta-phi),math.sin(theta-phi);px,py=-3.01*math.cos(phi),3.01*math.sin(phi)
        lo,hi=0,math.inf
        for p,d in ((px,dx),(py,dy)):
            if abs(d)<1e-15:
                if abs(p)>.01:return 5
            else:
                a,b=(-.01-p)/d,(.01-p)/d;lo=max(lo,min(a,b));hi=min(hi,max(a,b))
        if hi<=lo:return 5
        return 5 if lo>=5 else (5+16*lo)/17 if lo+17*(hi-lo)>=5 else 5-16*(hi-lo)
    t=math.atan(.02/4.5)
    values=[];fully_removed=guard_band=actual_retained=0
    for i in range(20001):
        theta=-t+2*t*(i+.5)/20001
        limit=reach(theta)
        front=4.5/math.cos(theta);back=min(5.1/math.cos(theta),.02/abs(math.sin(theta)) if theta else math.inf)
        spans=intervals(current,theta)
        if limit>=back:fully_removed+=1
        if not spans:
            assert limit>=back-.000002,(degrees,theta,limit,back)
            continue
        actual_retained+=1
        if limit>=back:guard_band+=1
        values.append(max(front,limit)-spans[0][0])
    p={'probes':20001,'actual_retained_rays':actual_retained,'analytic_fully_removed_rays':fully_removed,
       'retained_rays_in_permitted_inward_guard_band':guard_band,
       'maximum_radial_deficit_m':max(values),'minimum_radial_deficit_m':min(values),
       'central_front_m':intervals(current,0)[0][0],'analytic_central_front_m':reach(0)}
    assert max(values)<=.001+.000002 and min(values)>=-.000002,p
    report[f'narrow{degrees}']=p
before,after=load('benchmark-thin-before.json'),load('benchmark-thin-after.json');t=math.acos(1/1.05)
report['thin']=probes(polygons(material(after,'cover')),-t,t,lambda t:.21+.8/math.cos(t))
report['thin']['central_retained_thickness_m']=intervals(polygons(material(after,'cover')),0)[0][1]-intervals(polygons(material(after,'cover')),0)[0][0]
# Five host-only samples, fixture construction outside stopwatch; no claimed percentile guarantee.
bench=json.loads((base/'benchmark.json').read_text(encoding='utf-8-sig'));cost={}
for name in sorted({r['name'] for r in bench}):
    rows=[r for r in bench if r['name']==name and not r['warmup']];assert all(r['ok'] for r in rows),rows
    times=sorted(r['milliseconds'] for r in rows)
    cost[name]={'samples':len(rows),'median_ms':statistics.median(times),'maximum_ms':max(times),'minimum_ms':min(times),
        'sectors':rows[-1]['diagnostics']['sectors'],'cells':rows[-1]['diagnostics']['resultCells'],
        'half_plane_clips':rows[-1]['diagnostics']['halfPlaneClips'],'maximum_reported_deficit_m':rows[-1]['diagnostics']['maximumRadialDeficit'],
        'maximum_float_conversion_m':max(r['diagnostics']['maximumFloatError'] for r in rows)}
report['host_cost']=cost
(base/'accuracy-and-cost.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
print(json.dumps(report,indent=2))

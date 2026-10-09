using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using UnityEngine;

namespace Bomb.CanonicalDestruction
{
    internal static class BoundedBlastGeometry
    {
        // Same convex half-plane backend, one batch. Positive-area retained cells
        // are never removed by the old per-cut cleanup threshold.
        public static GeometryEvaluationResult Evaluate(CanonicalMaterialState source, BoundedBlastField field, float minimumArea)
        {
            if (source == null || field == null) return GeometryEvaluationResult.Failure("Missing blast source/field.");
            var clock = Stopwatch.StartNew();
            var pieces = new List<List<BlastPoint>>();
            double originalArea = 0;
            var origin = BlastMath.Local(source, BlastPoint.Zero, field.Origin);
            foreach (var cell in source.Shape.Cells)
            {
                var polygon = cell.Vertices.Select(p => new BlastPoint(p.x, p.y)).ToList();
                originalArea += BlastMath.Area(polygon);
                var retained=new List<List<BlastPoint>>();bool removedArea=false;
                var angles=cell.Vertices.Select(p=>BlastMath.World(source,p,field.Origin)).Select(p=>BlastMath.Angle(Math.Atan2(p.Y,p.X))).OrderBy(a=>a).ToArray();
                double gap=-1,start=0;
                for(int i=0;i<angles.Length;i++)
                { double next=i+1<angles.Length?angles[i+1]:angles[0]+2*Math.PI; if(next-angles[i]>gap){gap=next-angles[i];start=BlastMath.Angle(next);} }
                double end=start+2*Math.PI-gap;
                foreach (var sector in field.Sectors.Where(s=>(s.B>=start-1e-14&&s.A<=Math.Min(end,2*Math.PI)+1e-14)
                    ||(end>2*Math.PI&&s.A<=end-2*Math.PI+1e-14)))
                {
                    if (field.Diagnostics.halfPlaneClips + 4 > 262144)
                        return GeometryEvaluationResult.Failure("Blast subtraction exceeds 262144 half-plane clips.");
                    var rayA = BlastMath.Local(source, BlastPoint.Direction(sector.A), field.Origin);
                    var rayB = BlastMath.Local(source, BlastPoint.Direction(sector.B), field.Origin);
                    var part = BlastMath.Clip(polygon, origin, rayA, true);
                    part = BlastMath.Clip(part, origin, rayB, false);
                    var a = BlastMath.Local(source, BlastPoint.Direction(sector.A) * sector.Left, field.Origin);
                    var b = BlastMath.Local(source, BlastPoint.Direction(sector.B) * sector.Right, field.Origin);
                    var removed=BlastMath.Clip(part,a,b,true);
                    if(removed.Count>=3&&BlastMath.Area(removed)>0)removedArea=true;
                    part = BlastMath.Clip(part, a, b, false);
                    field.Diagnostics.halfPlaneClips += 4;
                    if (part.Count >= 3 && BlastMath.Area(part) > 0) retained.Add(part);
                }
                // If no cutter triangle intersects this cell in positive area, reuse
                // its exact original boundary instead of manufacturing subdivisions.
                if(removedArea)pieces.AddRange(retained);else pieces.Add(polygon);
                if (pieces.Count > 8192) return GeometryEvaluationResult.Failure("Blast retained partition exceeds 8192 pieces per body.");
            }
            double area = pieces.Sum(p => BlastMath.Area(p));
            if (area > originalArea + BlastMath.Roundoff) return GeometryEvaluationResult.Failure("Blast partition increased source area.");
            if (originalArea - area <= BlastMath.Roundoff)
            { field.Diagnostics.subtractionMilliseconds+=clock.Elapsed.TotalMilliseconds; return GeometryEvaluationResult.Success(false, new[] { source.Shape }); }
            if (!Repartition(pieces, minimumArea, field.Diagnostics, out var partitionError)) return GeometryEvaluationResult.Failure(partitionError);
            var cells = new List<CanonicalPolygon2D>();
            foreach (var piece in pieces)
            {
                var points = piece.Select(p => new Vector2((float)p.X, (float)p.Y)).ToArray();
                for (int i = 0; i < points.Length; i++)
                {
                    double drift = (BlastMath.World(source, points[i], field.Origin) - BlastMath.WorldPoint(source, piece[i], field.Origin)).Length;
                    field.Diagnostics.maximumFloatError = Math.Max(field.Diagnostics.maximumFloatError, drift);
                    if (drift > BoundedBlastEvaluator.FloatAllowance) return GeometryEvaluationResult.Failure("Blast float conversion exceeds 0.05 mm.");
                }
                var polygon = new CanonicalPolygon2D(points);
                bool valid = polygon.TryValidate(out var validation);
                if (polygon.Area <= minimumArea || !valid)
                    return GeometryEvaluationResult.Failure("Lossless blast partition cannot represent a retained cell: area="
                        + polygon.Area.ToString("R") + ", selected minimum=" + minimumArea.ToString("R")
                        + ", vertices=" + points.Length + ", minimum edge="
                        + piece.Select((p,i) => (p-piece[(i+1)%piece.Count]).Length).Min().ToString("R")
                        + ", canonical validation=" + validation + ", source=" + source.Id + ", points="
                        + string.Join(";",piece.Select(p=>p.X.ToString("R")+","+p.Y.ToString("R"))) + ".");
                cells.Add(polygon);
            }
            var connected = PolygonConnectivity.GroupConnected(cells);
            foreach (var shape in connected)
            {
                if (shape.Cells.Count > 512) return GeometryEvaluationResult.Failure("Blast result exceeds 512 canonical cells.");
                if (!shape.TryValidate(out var error)) return GeometryEvaluationResult.Failure("Invalid blast result: " + error);
            }
            field.Diagnostics.resultCells += cells.Count;
            field.Diagnostics.subtractionMilliseconds += clock.Elapsed.TotalMilliseconds;
            return GeometryEvaluationResult.Success(true, connected);
        }

        // Cancel shared subdivision edges BEFORE converting to float. Retriangulate
        // the remaining union boundary so an arbitrary ray/source intersection does
        // not become a tiny canonical cell. No positive-area piece is cleaned away.
        private static bool Repartition(List<List<BlastPoint>> pieces, float minimumArea, BlastDiagnostics diagnostics, out string error)
        {
            error = null;
            double before = pieces.Sum(BlastMath.Area);
            const double weld = 1e-11;
            var vertices = new List<BlastPoint>();
            var buckets = new Dictionary<(long,long),List<int>>();
            int Index(BlastPoint p)
            {
                long x=(long)Math.Floor(p.X/weld), y=(long)Math.Floor(p.Y/weld);
                for(int dx=-1;dx<=1;dx++) for(int dy=-1;dy<=1;dy++)
                    if(buckets.TryGetValue((x+dx,y+dy),out var nearby))
                        foreach(int n in nearby) if((vertices[n]-p).Length<=weld) return n;
                int index=vertices.Count; vertices.Add(p);
                if(!buckets.TryGetValue((x,y),out var list)) buckets[(x,y)]=list=new List<int>();
                list.Add(index); return index;
            }
            var polygons=pieces.Select(p=>p.Select(Index).ToArray()).ToArray();
            diagnostics.boundaryVertices += vertices.Count;
            if(vertices.Count>16384) { error="Blast boundary arrangement exceeds 16384 vertices per body."; return false; }
            var edges=new HashSet<(int from,int to)>();
            foreach(var polygon in polygons) for(int i=0;i<polygon.Length;i++)
            {
                int first=polygon[i],last=polygon[(i+1)%polygon.Length];
                if(first==last) continue;
                var a=vertices[first]; var delta=vertices[last]-a; double length=delta.Length;
                var points=new List<(double t,int index)>{(0,first),(length,last)};
                for(int j=0;j<vertices.Count;j++)
                {
                    if(j==first||j==last) continue;
                    var v=vertices[j]-a; double t=BlastPoint.Dot(delta,v)/length;
                    if(t>0&&t<length&&Math.Abs(BlastPoint.Cross(delta,v))/length<=weld) points.Add((t,j));
                }
                points.Sort((p,q)=>p.t.CompareTo(q.t));
                for(int j=0;j+1<points.Count;j++)
                {
                    var e=(points[j].index,points[j+1].index);
                    if(!edges.Remove((e.Item2,e.Item1))&&!edges.Add(e))
                    { error="Blast union has a duplicate oriented edge."; return false; }
                }
            }
            var loops=new List<List<BlastPoint>>();
            var outgoing=edges.GroupBy(e=>e.from).ToDictionary(g=>g.Key,g=>g.Select(e=>e.to).ToList());
            while(edges.Count>0)
            {
                var initial=edges.First(); int start=initial.from,current=start,previous=-1;
                var loop=new List<BlastPoint>();
                do
                {
                    loop.Add(vertices[current]);
                    var next=outgoing[current].Where(n=>edges.Contains((current,n))).ToArray();
                    if(next.Length==0) { error="Blast retained boundary has an open edge at "+vertices[current].X.ToString("R")+","+vertices[current].Y.ToString("R")+"."; return false; }
                    // Canonical cell unions can meet at a point. Follow the left
                    // material face at a junction, leaving the other closed contour
                    // for the next walk; connectivity is still the existing backend's.
                    int selected=previous<0?initial.to:next.OrderByDescending(n=>
                    {
                        var incoming=vertices[current]-vertices[previous];var outgoingEdge=vertices[n]-vertices[current];
                        return Math.Atan2(BlastPoint.Cross(incoming,outgoingEdge),BlastPoint.Dot(incoming,outgoingEdge));
                    }).First();
                    edges.Remove((current,selected)); previous=current;current=selected;
                    if(loop.Count>vertices.Count) { error="Blast retained boundary did not close."; return false; }
                } while(current!=start);
                var contours=new List<List<BlastPoint>>{loop};
                for(int index=0;index<contours.Count;index++)
                {
                    var contour=contours[index];bool split=false;
                    for(int a=0;a<contour.Count&&!split;a++)for(int b=a+1;b<contour.Count;b++)
                        if(contour[a].X==contour[b].X&&contour[a].Y==contour[b].Y)
                        {
                            contours[index]=contour.Take(a).Concat(contour.Skip(b)).ToList();
                            contours.Add(contour.GetRange(a,b-a));index--;split=true;break;
                        }
                }
                foreach(var contour in contours)
                {
                    var clean=BlastMath.Clean(contour);
                    double signed=0;for(int i=0;i<clean.Count;i++)signed+=BlastPoint.Cross(clean[i],clean[(i+1)%clean.Count]);
                    if(signed<0)
                    {
                        // A surviving enclosed cavity needs the original lossless cell
                        // partition; this fallback neither fills the hole nor drops it.
                        Merge(pieces);return true;
                    }
                    if(clean.Count>=3&&BlastMath.Area(clean)>0)loops.Add(clean);
                }
            }
            var triangles=new List<List<BlastPoint>>();
            foreach(var loop in loops)
            {
                while(loop.Count>3)
                {
                    int ear=-1; double largest=0;
                    for(int i=0;i<loop.Count;i++)
                    {
                        var a=loop[(i+loop.Count-1)%loop.Count]; var b=loop[i]; var c=loop[(i+1)%loop.Count];
                        double cross=BlastPoint.Cross(b-a,c-b); if(cross<=largest) continue;
                        bool occupied=false;
                        for(int j=0;j<loop.Count;j++)
                        {
                            if(j==i||j==(i+1)%loop.Count||j==(i+loop.Count-1)%loop.Count) continue;
                            var p=loop[j];
                            if(BlastPoint.Cross(b-a,p-a)>=-1e-14&&BlastPoint.Cross(c-b,p-b)>=-1e-14
                                &&BlastPoint.Cross(a-c,p-c)>=-1e-14) { occupied=true; break; }
                        }
                        if(!occupied) { ear=i; largest=cross; }
                    }
                    if(ear<0) { error="Lossless blast boundary triangulation failed: vertices="+loop.Count+", first points="
                        +string.Join(";",loop.Take(12).Select(p=>p.X.ToString("R")+","+p.Y.ToString("R")))+"."; return false; }
                    triangles.Add(new List<BlastPoint>{loop[(ear+loop.Count-1)%loop.Count],loop[ear],loop[(ear+1)%loop.Count]});
                    loop.RemoveAt(ear);
                }
                if(loop.Count==3) triangles.Add(loop);
            }
            var merged=triangles.Select(p=>p.ToList()).ToList(); Merge(merged);
            if(merged.Any(p=>!Representable(p,minimumArea)))
            { ImproveTriangleAreas(triangles,diagnostics); Merge(triangles); }
            else triangles=merged;
            double after=triangles.Sum(BlastMath.Area);
            if(Math.Abs(after-before)>BlastMath.Roundoff)
            { error="Blast boundary repartition changed retained area by "+(after-before).ToString("R")+"."; return false; }
            pieces.Clear(); pieces.AddRange(triangles); return true;
        }
        private static bool Representable(List<BlastPoint> piece,float minimumArea)
        {
            var p=new CanonicalPolygon2D(piece.Select(v=>new Vector2((float)v.X,(float)v.Y)));
            return p.Area>minimumArea&&p.TryValidate(out _);
        }
        private static void ImproveTriangleAreas(List<List<BlastPoint>> triangles, BlastDiagnostics diagnostics)
        {
            // Lossless diagonal flips redistribute area; a short boundary facet can
            // use a distant interior vertex instead of becoming a cleanup sliver.
            for(int pass=0;pass<512;pass++)
            {
                bool changed=false;
                var points=new Dictionary<(double,double),int>();
                var owners=new Dictionary<(int,int),List<int>>();
                int Vertex(BlastPoint p)
                { if(!points.TryGetValue((p.X,p.Y),out int id)) points[(p.X,p.Y)]=id=points.Count; return id; }
                for(int i=0;i<triangles.Count;i++) for(int k=0;k<3;k++)
                {
                    int a=Vertex(triangles[i][k]),b=Vertex(triangles[i][(k+1)%3]);var e=(Math.Min(a,b),Math.Max(a,b));
                    if(!owners.TryGetValue(e,out var list)) owners[e]=list=new List<int>(); list.Add(i);
                }
                foreach(var pair in owners.Values.Where(p=>p.Count==2))
                {
                    if(++diagnostics.diagonalPairs>1000000) return;
                    int i=pair[0],j=pair[1];
                    var common=triangles[i].Where(p=>triangles[j].Any(q=>(p-q).Length<=1e-12)).ToArray();
                    if(common.Length!=2) continue;
                    var hull=Hull(triangles[i].Concat(triangles[j])); if(hull.Count!=4) continue;
                    int ia=hull.FindIndex(p=>(p-common[0]).Length<=1e-12),ib=hull.FindIndex(p=>(p-common[1]).Length<=1e-12);
                    if(ia<0||ib<0||Math.Abs(ia-ib)!=2) continue;
                    int start=(ia+1)%4;
                    var a=new List<BlastPoint>{hull[start],hull[(start+1)%4],hull[(start+2)%4]};
                    var b=new List<BlastPoint>{hull[start],hull[(start+2)%4],hull[(start+3)%4]};
                    double old=Math.Min(BlastMath.Area(triangles[i]),BlastMath.Area(triangles[j]));
                    if(Math.Min(BlastMath.Area(a),BlastMath.Area(b))<=old+1e-12) continue;
                    triangles[i]=a;triangles[j]=b;changed=true;diagnostics.diagonalFlips++;
                }
                if(!changed) return;
            }
        }

        internal static CanonicalMaterialState RecenterExactly(CanonicalMaterialState source, CanonicalMaterialState result,
            MaterialEntityId resultId, BlastDiagnostics diagnostics)
        {
            // Float centroid subtraction + a separately rounded world position can
            // move an original shared face. Pick the closest dyadic frame shift that
            // is EXACT for every current vertex and both world position components.
            // A body-local origin need not equal its COM (WORLD-006 / DEC-057).
            var centroid=result.Shape.Centroid;
            var points=result.Shape.Cells.SelectMany(c=>c.Vertices).ToArray();
            Vector2 best=Vector2.zero,position=source.Position;
            double bestDistance=centroid.sqrMagnitude;
            double cosine=Mathf.Cos(source.RotationRadians),sine=Mathf.Sin(source.RotationRadians);
            for(int exponent=-12;exponent<=6;exponent++)
            {
                double grid=Math.Pow(2,exponent),cx=Math.Round(centroid.x/grid),cy=Math.Round(centroid.y/grid);
                for(int ix=-2;ix<=2;ix++) for(int iy=-2;iy<=2;iy++)
                {
                    var center=new Vector2((float)((cx+ix)*grid),(float)((cy+iy)*grid));
                    double distance=(center-centroid).sqrMagnitude; if(distance>=bestDistance) continue;
                    double px=source.Position.x+cosine*center.x-sine*center.y,py=source.Position.y+sine*center.x+cosine*center.y;
                    if(px!=(double)(float)px||py!=(double)(float)py||Math.Abs(px)>64||Math.Abs(py)>64) continue;
                    if(points.Any(p=>(double)(float)(p.x-(double)center.x)!=p.x-(double)center.x
                        ||(double)(float)(p.y-(double)center.y)!=p.y-(double)center.y)) continue;
                    best=center;position=new Vector2((float)px,(float)py);bestDistance=distance;
                }
            }
            diagnostics.exactFrameResults++;
            diagnostics.maximumLocalComOffset=Math.Max(diagnostics.maximumLocalComOffset,Math.Sqrt(bestDistance));
            return result.WithGeometry(resultId,CanonicalGeometry.Translate(result.Shape,-best),result.GeometryRevision,
                result.LinearVelocity,result.AngularVelocityRadians,result.BodyMode).WithMotion(position,source.RotationRadians,
                    result.LinearVelocity,result.AngularVelocityRadians);
        }
        private static void Merge(List<List<BlastPoint>> pieces)
        {
            bool changed;
            do
            {
                changed = false;
                for (int i = 0; i < pieces.Count; i++) for (int j = i + 1; j < pieces.Count; j++)
                {
                    if (!ShareSegment(pieces[i], pieces[j])) continue;
                    var hull = Hull(pieces[i].Concat(pieces[j]));
                    if (Math.Abs(BlastMath.Area(hull) - BlastMath.Area(pieces[i]) - BlastMath.Area(pieces[j])) > 1e-12) continue;
                    // A removed collinear vertex may become a T junction on a third
                    // cell. Merge only if it remains EXACTLY collinear after float
                    // conversion; otherwise the float polygons can contain a crack.
                    bool safe=true;
                    foreach(var p in pieces[i].Concat(pieces[j])) for(int k=0;k<hull.Count;k++)
                    {
                        var a=hull[k];var b=hull[(k+1)%hull.Count];var edge=b-a;
                        if(BlastPoint.Dot(p-a,edge)<=0||BlastPoint.Dot(p-b,edge)>=0) continue;
                        if(Math.Abs(BlastPoint.Cross(edge,p-a))/edge.Length>1e-12) continue;
                        var af=new BlastPoint((float)a.X,(float)a.Y);var bf=new BlastPoint((float)b.X,(float)b.Y);var pf=new BlastPoint((float)p.X,(float)p.Y);
                        if(BlastPoint.Cross(bf-af,pf-af)!=0) {safe=false;break;}
                    }
                    for(int k=0;k<hull.Count&&safe;k++)
                    {
                        var a=hull[k];var b=hull[(k+1)%hull.Count];var c=hull[(k+2)%hull.Count];
                        var af=new BlastPoint((float)a.X,(float)a.Y);var bf=new BlastPoint((float)b.X,(float)b.Y);var cf=new BlastPoint((float)c.X,(float)c.Y);
                        if(BlastPoint.Cross(bf-af,cf-bf)<0) safe=false;
                    }
                    if(!safe) continue;
                    pieces[i] = hull; pieces.RemoveAt(j); changed = true; j = i;
                }
            } while (changed);
        }
        private static bool ShareSegment(List<BlastPoint> a, List<BlastPoint> b)
        {
            for (int i = 0; i < a.Count; i++) for (int j = 0; j < b.Count; j++)
            {
                var edge = a[(i + 1) % a.Count] - a[i]; double length = edge.Length;
                var c = b[j] - a[i]; var d = b[(j + 1) % b.Count] - a[i];
                if (Math.Abs(BlastPoint.Cross(edge, c)) / length > 1e-12 || Math.Abs(BlastPoint.Cross(edge, d)) / length > 1e-12) continue;
                double tc = BlastPoint.Dot(edge, c) / length, td = BlastPoint.Dot(edge, d) / length;
                if (Math.Min(length, Math.Max(tc, td)) - Math.Max(0, Math.Min(tc, td)) > 1e-10) return true;
            }
            return false;
        }
        private static List<BlastPoint> Hull(IEnumerable<BlastPoint> input)
        {
            var points = input.OrderBy(p => p.X).ThenBy(p => p.Y).ToList(); var hull = new List<BlastPoint>();
            foreach (var p in points)
            {
                while (hull.Count >= 2 && BlastPoint.Cross(hull[hull.Count - 1] - hull[hull.Count - 2], p - hull[hull.Count - 1]) <= 0) hull.RemoveAt(hull.Count - 1);
                hull.Add(p);
            }
            int lower = hull.Count;
            for (int i = points.Count - 2; i >= 0; i--)
            {
                var p = points[i];
                while (hull.Count > lower && BlastPoint.Cross(hull[hull.Count - 1] - hull[hull.Count - 2], p - hull[hull.Count - 1]) <= 0) hull.RemoveAt(hull.Count - 1);
                hull.Add(p);
            }
            if (hull.Count > 1) hull.RemoveAt(hull.Count - 1);
            return BlastMath.Clean(hull);
        }
    }
}

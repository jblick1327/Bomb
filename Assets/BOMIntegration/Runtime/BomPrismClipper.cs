using System;
using System.Collections.Generic;
using System.Threading;
using UnityEngine;

namespace Bom.Unity {
// Copied value data only: worker code never reads or creates Unity objects.
public struct BomClipVertex {
 public Vector3 Position,Normal;public Vector4 Tangent;public Color Color;
 public Vector4 UV0,UV1,UV2,UV3,UV4,UV5,UV6,UV7;
 public static BomClipVertex Lerp(BomClipVertex a,BomClipVertex b,float t)=>new BomClipVertex{
  Position=Vector3.LerpUnclamped(a.Position,b.Position,t),Normal=Vector3.LerpUnclamped(a.Normal,b.Normal,t),
  Tangent=Vector4.LerpUnclamped(a.Tangent,b.Tangent,t),Color=UnityEngine.Color.LerpUnclamped(a.Color,b.Color,t),
  UV0=Vector4.LerpUnclamped(a.UV0,b.UV0,t),UV1=Vector4.LerpUnclamped(a.UV1,b.UV1,t),UV2=Vector4.LerpUnclamped(a.UV2,b.UV2,t),UV3=Vector4.LerpUnclamped(a.UV3,b.UV3,t),
  UV4=Vector4.LerpUnclamped(a.UV4,b.UV4,t),UV5=Vector4.LerpUnclamped(a.UV5,b.UV5,t),UV6=Vector4.LerpUnclamped(a.UV6,b.UV6,t),UV7=Vector4.LerpUnclamped(a.UV7,b.UV7,t)};
}
public struct BomClipTriangle {public BomClipVertex A,B,C;public int Material;public BomClipTriangle(BomClipVertex a,BomClipVertex b,BomClipVertex c,int material){A=a;B=b;C=c;Material=material;}}
public sealed class BomClipSource {
 public BomClipTriangle[] Triangles;public int[] Components;public int ComponentCount;public int MaterialCount;public float Epsilon;public string Classification,Failure;
 // Uniform XY bins are an immutable spatial index over normalized triangles.
 public long Bytes;public Vector2 Min,Max;public int[][] Bins;public const int BinWidth=16;
 public int Bin(float value,float lo,float hi)=>Math.Min(BinWidth-1,Math.Max(0,(int)((value-lo)/Math.Max(hi-lo,Epsilon)*BinWidth)));
 public int[] Candidates(Vector2 lo,Vector2 hi){
  if(hi.x<Min.x||lo.x>Max.x||hi.y<Min.y||lo.y>Max.y)return Array.Empty<int>();
  var ids=new HashSet<int>();for(int y=Bin(lo.y,Min.y,Max.y);y<=Bin(hi.y,Min.y,Max.y);y++)for(int x=Bin(lo.x,Min.x,Max.x);x<=Bin(hi.x,Min.x,Max.x);x++)foreach(int i in Bins[y*BinWidth+x])ids.Add(i);
  var result=new int[ids.Count];ids.CopyTo(result);Array.Sort(result);return result;
 }
}
public sealed class BomClipPatch {public Vector2 EdgeA,EdgeB;public BomClipTriangle[] Triangles;public bool DecompositionInterior;public int Solid;}
public sealed class BomClipResult {
 public BomClipSource PreparedSource;public bool Supported;public string Reason;public BomClipTriangle[] Exterior=Array.Empty<BomClipTriangle>();public BomClipPatch[] Caps=Array.Empty<BomClipPatch>();public int Candidates;public long Bytes;
}
public static class BomPrismClipper {
 public const int BuilderVersion=2,MaxTriangles=200000,MaxOutputTriangles=10000,MaxPlaneSegments=4096;
 struct PointKey:IEquatable<PointKey> {public long X,Y,Z;public PointKey(Vector3 p,float e){X=(long)Math.Round(p.x/e);Y=(long)Math.Round(p.y/e);Z=(long)Math.Round(p.z/e);}public bool Equals(PointKey b)=>X==b.X&&Y==b.Y&&Z==b.Z;public override bool Equals(object o)=>o is PointKey b&&Equals(b);public override int GetHashCode()=>unchecked((X.GetHashCode()*397^Y.GetHashCode())*397^Z.GetHashCode());}
 struct Plane {public Vector2 A,B,Normal;public int Edge,Index;public double DistanceExact(Vector3 p){double x=(double)B.x-A.x,y=(double)B.y-A.y;return (x*((double)p.y-A.y)-y*((double)p.x-A.x))/Math.Sqrt(x*x+y*y);}public float Distance(Vector3 p)=>(float)DistanceExact(p);}
 struct Segment {public Vector3 A,B;public Segment(Vector3 a,Vector3 b){A=a;B=b;}}
 static Vector2 Unit(Vector2 v){double length=Math.Sqrt((double)v.x*v.x+(double)v.y*v.y);return new Vector2((float)(v.x/length),(float)(v.y/length));}
 static float Cross(Vector2 a,Vector2 b)=>a.x*b.y-a.y*b.x;
 static float Area(IReadOnlyList<Vector2> p){double a=0;for(int i=0;i<p.Count;i++)a+=(double)p[i].x*p[(i+1)%p.Count].y-(double)p[i].y*p[(i+1)%p.Count].x;return (float)(a*.5);}
 static bool Finite(float v)=>!float.IsNaN(v)&&!float.IsInfinity(v);
 public static BomClipSource Prepare(BomClipTriangle[] triangles,int materials,CancellationToken cancellation=default){
  cancellation.ThrowIfCancellationRequested();
  var source=new BomClipSource{Triangles=triangles,MaterialCount=materials,Min=new Vector2(float.MaxValue,float.MaxValue),Max=new Vector2(float.MinValue,float.MinValue)};
  if(triangles.Length==0||triangles.Length>MaxTriangles){source.Failure="empty or oversized source";return source;}
  float zlo=float.MaxValue,zhi=float.MinValue;
  foreach(var triangle in triangles)foreach(var p in new[]{triangle.A.Position,triangle.B.Position,triangle.C.Position}){
   if(!Finite(p.x)||!Finite(p.y)||!Finite(p.z)){source.Failure="nonfinite visual vertex";return source;}
   source.Min=Vector2.Min(source.Min,new Vector2(p.x,p.y));source.Max=Vector2.Max(source.Max,new Vector2(p.x,p.y));zlo=Math.Min(zlo,p.z);zhi=Math.Max(zhi,p.z);
  }
  source.Epsilon=Math.Max(1e-6f,Math.Max((source.Max-source.Min).magnitude,zhi-zlo)*1e-7f);
  if(!ClosedTopology(triangles,source.Epsilon,out string failure,out var components)){source.Classification="open, degenerate or nonmanifold";source.Failure=failure;return source;}
  source.Components=components;foreach(int component in components)source.ComponentCount=Math.Max(source.ComponentCount,component+1);source.Classification="supported closed solid collection";
  var bins=new List<int>[BomClipSource.BinWidth*BomClipSource.BinWidth];for(int i=0;i<bins.Length;i++)bins[i]=new List<int>();
  for(int i=0;i<triangles.Length;i++){
   if((i&255)==0)cancellation.ThrowIfCancellationRequested();
   var t=triangles[i];Vector3 lo=Vector3.Min(t.A.Position,Vector3.Min(t.B.Position,t.C.Position)),hi=Vector3.Max(t.A.Position,Vector3.Max(t.B.Position,t.C.Position));
   for(int y=source.Bin(lo.y,source.Min.y,source.Max.y);y<=source.Bin(hi.y,source.Min.y,source.Max.y);y++)for(int x=source.Bin(lo.x,source.Min.x,source.Max.x);x<=source.Bin(hi.x,source.Min.x,source.Max.x);x++)bins[y*BomClipSource.BinWidth+x].Add(i);
  }
  source.Bytes=(long)triangles.Length*580;source.Bins=new int[bins.Length][];for(int i=0;i<bins.Length;i++){source.Bins[i]=bins[i].ToArray();source.Bytes+=bins[i].Count*4L+32;}return source;
 }
 public static bool Closed(IReadOnlyList<BomClipTriangle> triangles,float epsilon,out string reason)=>ClosedTopology(triangles,epsilon,out reason,out _);
 static bool ClosedTopology(IReadOnlyList<BomClipTriangle> triangles,float epsilon,out string reason,out int[] components){
  components=null;
  var pool=new VertexPool(epsilon);var edges=new Dictionary<(int,int),(int Count,int Triangle)>();var parent=new int[triangles.Count];var volumes=new double[triangles.Count];
  int Root(int i){while(parent[i]!=i){parent[i]=parent[parent[i]];i=parent[i];}return i;}
  for(int index=0;index<triangles.Count;index++){
   parent[index]=index;var t=triangles[index];var a=t.A.Position;var b=t.B.Position;var c=t.C.Position;
   if(Vector3.Cross(b-a,c-a).sqrMagnitude<epsilon*epsilon*epsilon*epsilon){reason="degenerate triangle";return false;}
   var origin=triangles[0].A.Position;double ax=(double)a.x-origin.x,ay=(double)a.y-origin.y,az=(double)a.z-origin.z,bx=(double)b.x-origin.x,by=(double)b.y-origin.y,bz=(double)b.z-origin.z,cx=(double)c.x-origin.x,cy=(double)c.y-origin.y,cz=(double)c.z-origin.z;
   volumes[index]=(ax*(by*cz-bz*cy)+ay*(bz*cx-bx*cz)+az*(bx*cy-by*cx))/6.0;
   var keys=new[]{pool.Find(a),pool.Find(b),pool.Find(c)};
   for(int i=0;i<3;i++){var key=(keys[i],keys[(i+1)%3]);edges.TryGetValue(key,out var old);edges[key]=(old.Count+1,index);}
  }
  foreach(var pair in edges){bool reverseExists=edges.TryGetValue((pair.Key.Item2,pair.Key.Item1),out var reverse);if(pair.Value.Count!=1||!reverseExists||reverse.Count!=1){reason=$"open or nonmanifold welded edge {pool.Points[pair.Key.Item1]} -> {pool.Points[pair.Key.Item2]} counts={pair.Value.Count}/{reverse.Count}";return false;}int a=Root(pair.Value.Triangle),b=Root(reverse.Triangle);if(a!=b)parent[b]=a;}
  var componentVolumes=new Dictionary<int,double>();for(int i=0;i<triangles.Count;i++){int root=Root(i);componentVolumes.TryGetValue(root,out double volume);componentVolumes[root]=volume+volumes[i];}
  foreach(double volume in componentVolumes.Values)if(volume<=epsilon*epsilon*epsilon){reason="thin, inward-facing or zero-volume shell";return false;}
  components=new int[triangles.Count];var labels=new Dictionary<int,int>();for(int i=0;i<triangles.Count;i++){int root=Root(i);if(!labels.TryGetValue(root,out int label)){label=labels.Count;labels.Add(root,label);}components[i]=label;}
  reason="";return true;
 }
 static List<Plane> Planes(Vector2[] polygon,int[] edgeIds){var result=new List<Plane>();for(int i=0;i<polygon.Length;i++){var edge=polygon[(i+1)%polygon.Length]-polygon[i];result.Add(new Plane{A=polygon[i],B=polygon[(i+1)%polygon.Length],Normal=Unit(new Vector2(-edge.y,edge.x)),Edge=edgeIds[i],Index=i});}return result;}
 // Exact cut-plane ownership avoids treating nearby original surface edges as cut contours.
 struct ClipPoint {public BomClipVertex Value;public double X,Y,Z;public ulong Planes0,Planes1;public ClipPoint(BomClipVertex value){Value=value;X=value.Position.x;Y=value.Position.y;Z=value.Position.z;Planes0=Planes1=0;}public void Bind(int index){if(index<64)Planes0|=1UL<<index;else Planes1|=1UL<<(index-64);}public bool On(int index)=>index<64?(Planes0&(1UL<<index))!=0:(Planes1&(1UL<<(index-64)))!=0;public BomClipVertex Finish(){var value=Value;value.Position=new Vector3((float)X,(float)Y,(float)Z);return value;}}
 static List<ClipPoint> Clip(List<ClipPoint> polygon,Plane plane,float epsilon){
  var output=new List<ClipPoint>();if(polygon.Count==0)return output;
  double ex=(double)plane.B.x-plane.A.x,ey=(double)plane.B.y-plane.A.y;
  double Distance(ClipPoint p)=>ex*(p.Y-plane.A.y)-ey*(p.X-plane.A.x);
  var a=polygon[polygon.Count-1];double da=Distance(a);if(Math.Abs(da)<=1e-12)a.Bind(plane.Index);
  foreach(var original in polygon){var b=original;double db=Distance(b);if(Math.Abs(db)<=1e-12)b.Bind(plane.Index);bool ina=da>=0,inb=db>=0;if(ina!=inb){double ratio=da/(da-db);var v=new ClipPoint(BomClipVertex.Lerp(a.Value,b.Value,(float)ratio)){X=a.X+ratio*(b.X-a.X),Y=a.Y+ratio*(b.Y-a.Y),Z=a.Z+ratio*(b.Z-a.Z),Planes0=a.Planes0&b.Planes0,Planes1=a.Planes1&b.Planes1};v.Bind(plane.Index);output.Add(v);}if(inb)output.Add(b);a=b;da=db;}
  // Preserve narrow intermediate polygons until every plane has been applied.
  // Rounding or welding here amplifies errors at almost parallel intersections.
  return output;
 }
 static Vector2[] CleanBoundary(Vector2[] input,float epsilon){
  var points=new List<Vector2>(input);bool changed=true;while(changed&&points.Count>3){changed=false;for(int i=0;i<points.Count;i++){var a=points[i]-points[(i+points.Count-1)%points.Count];var b=points[(i+1)%points.Count]-points[i];double cross=(double)a.x*b.y-(double)a.y*b.x;if(a.sqrMagnitude<=epsilon*epsilon||b.sqrMagnitude<=epsilon*epsilon||(Vector2.Dot(a,b)>0&&Math.Abs(cross)<=epsilon*(a.magnitude+b.magnitude))){points.RemoveAt(i);changed=true;break;}}}return points.ToArray();
 }
 static void Snap(List<BomClipVertex> polygon,Vector2[] corners,List<Plane> planes,float epsilon){
  for(int i=0;i<polygon.Count;i++){var vertex=polygon[i];var xy=new Vector2(vertex.Position.x,vertex.Position.y);int nearest=-1;double nearestDistance=double.MaxValue;for(int j=0;j<corners.Length;j++){double distance=(xy-corners[j]).sqrMagnitude;bool adjacent=Math.Abs(planes[j].DistanceExact(vertex.Position))<=epsilon*4&&Math.Abs(planes[(j+planes.Count-1)%planes.Count].DistanceExact(vertex.Position))<=epsilon*4;if((distance<=epsilon*epsilon*64||(adjacent&&distance<=Math.Pow(Math.Max(epsilon*8,0.00025),2)))&&distance<nearestDistance){nearest=j;nearestDistance=distance;}}if(nearest>=0){xy=corners[nearest];vertex.Position=new Vector3(xy.x,xy.y,vertex.Position.z);polygon[i]=vertex;}}
 }
 static List<BomClipTriangle> WeldTriangles(IReadOnlyList<BomClipTriangle> input,VertexPool pool){var result=new List<BomClipTriangle>();foreach(var t in input){int ia=pool.Find(t.A.Position),ib=pool.Find(t.B.Position),ic=pool.Find(t.C.Position);if(ia==ib||ib==ic||ic==ia)continue;var a=t.A;var b=t.B;var c=t.C;a.Position=pool.Points[ia];b.Position=pool.Points[ib];c.Position=pool.Points[ic];result.Add(new BomClipTriangle(a,b,c,t.Material));}return result;}
 // Welding a narrow wedge can make its opposing faces coincide. Remove
 // those zero-volume folds before validating the remaining closed surface.
 static List<BomClipTriangle> RemoveFoldPairs(List<BomClipTriangle> shell,List<BomClipPatch> caps,VertexPool pool){
  var all=new List<BomClipTriangle>(shell);foreach(var patch in caps)all.AddRange(patch.Triangles);var removed=new bool[all.Count];var unmatched=new Dictionary<(int,int,int),Stack<int>>();
  for(int i=0;i<all.Count;i++){var t=all[i];int a=pool.Find(t.A.Position),b=pool.Find(t.B.Position),c=pool.Find(t.C.Position);if(b<a&&b<c){int old=a;a=b;b=c;c=old;}else if(c<a&&c<b){int old=a;a=c;c=b;b=old;}var key=(a,b,c);var reverse=(a,c,b);if(unmatched.TryGetValue(reverse,out var opposite)&&opposite.Count>0){removed[i]=removed[opposite.Pop()]=true;}else{if(!unmatched.TryGetValue(key,out var own)){own=new Stack<int>();unmatched.Add(key,own);}own.Push(i);}}
  int cursor=0;var cleaned=new List<BomClipTriangle>();foreach(var t in shell){if(!removed[cursor])cleaned.Add(t);cursor++;}foreach(var patch in caps){var triangles=new List<BomClipTriangle>();foreach(var t in patch.Triangles){if(!removed[cursor])triangles.Add(t);cursor++;}patch.Triangles=triangles.ToArray();}return cleaned;
 }
 public static BomClipResult Build(BomClipSource source,Vector2[] cell,CancellationToken cancellation=default){
  var result=new BomClipResult();if(source.Failure!=null){result.Reason=source.Failure;return result;}
  try{
   cell=CleanBoundary(cell,source.Epsilon);
   if(cell.Length<3||cell.Length>128||Area(cell)<=source.Epsilon*source.Epsilon)throw new InvalidOperationException("invalid native cell polygon");
   int outputTriangles=0;var regions=Decompose(cell,source.Epsilon);var exterior=new List<BomClipTriangle>();var caps=new List<BomClipPatch>();var lo=cell[0];var hi=lo;foreach(var p in cell){lo=Vector2.Min(lo,p);hi=Vector2.Max(hi,p);}var candidates=source.Candidates(lo,hi);result.Candidates=candidates.Length;var solids=new SortedDictionary<int,List<int>>();foreach(int index in candidates){int solid=source.Components[index];if(!solids.TryGetValue(solid,out var list)){list=new List<int>();solids.Add(solid,list);}list.Add(index);}
   foreach(var region in regions)foreach(var solid in solids){
    cancellation.ThrowIfCancellationRequested();var planes=Planes(region.Item1,region.Item2);var shell=new List<BomClipTriangle>();var cutEdges=new List<Segment>[planes.Count];for(int i=0;i<cutEdges.Length;i++)cutEdges[i]=new List<Segment>();
    foreach(int candidate in solid.Value){cancellation.ThrowIfCancellationRequested();var triangle=source.Triangles[candidate];var precise=new List<ClipPoint>{new ClipPoint(triangle.A),new ClipPoint(triangle.B),new ClipPoint(triangle.C)};foreach(var plane in planes){precise=Clip(precise,plane,source.Epsilon);if(precise.Count<3)break;}var polygon=new List<BomClipVertex>();foreach(var point in precise)polygon.Add(point.Finish());Snap(polygon,region.Item1,planes,source.Epsilon);for(int j=0;j<polygon.Count;j++){var precisePoint=precise[j];foreach(var plane in planes)if((polygon[j].Position.x==plane.A.x&&polygon[j].Position.y==plane.A.y)||(polygon[j].Position.x==plane.B.x&&polygon[j].Position.y==plane.B.y))precisePoint.Bind(plane.Index);precise[j]=precisePoint;}if(polygon.Count>=3)for(int j=0;j<polygon.Count;j++)foreach(var plane in planes)if(precise[j].On(plane.Index)&&precise[(j+1)%polygon.Count].On(plane.Index))cutEdges[plane.Index].Add(new Segment(polygon[j].Position,polygon[(j+1)%polygon.Count].Position));for(int j=1;j+1<polygon.Count;j++)if(Vector3.Cross(polygon[j].Position-polygon[0].Position,polygon[j+1].Position-polygon[0].Position).sqrMagnitude>Math.Pow(source.Epsilon,4)){if(++outputTriangles>MaxOutputTriangles)throw new InvalidOperationException("clipped output budget exceeded");shell.Add(new BomClipTriangle(polygon[0],polygon[j],polygon[j+1],triangle.Material));}if(shell.Count>MaxOutputTriangles)throw new InvalidOperationException("clipped output budget exceeded");}
    if(shell.Count==0)continue;
    bool tangent=false;foreach(var plane in planes){bool coplanar=true;foreach(var triangle in shell)if(Math.Abs(plane.Distance(triangle.A.Position))>source.Epsilon*4||Math.Abs(plane.Distance(triangle.B.Position))>source.Epsilon*4||Math.Abs(plane.Distance(triangle.C.Position))>source.Epsilon*4){coplanar=false;break;}if(coplanar){tangent=true;break;}}if(tangent)continue;
    var closed=new List<BomClipTriangle>(shell);var regionCaps=new List<BomClipPatch>();
    foreach(var plane in planes){
     cancellation.ThrowIfCancellationRequested();var segments=cutEdges[plane.Index];
     var loops=Contours(segments,source.Epsilon,plane);if(loops.Count==0)continue;
     var triangles=Cap(loops,plane,source.MaterialCount,source.Epsilon);outputTriangles+=triangles.Count;if(outputTriangles>MaxOutputTriangles)throw new InvalidOperationException("clipped output budget exceeded");var patch=new BomClipPatch{EdgeA=plane.A,EdgeB=plane.B,Triangles=triangles.ToArray(),DecompositionInterior=plane.Edge<0,Solid=solid.Key};regionCaps.Add(patch);if(plane.Edge>=0)caps.Add(patch);
    }
    var weld=new VertexPool(source.Epsilon*2);shell=WeldTriangles(shell,weld);closed.Clear();closed.AddRange(shell);foreach(var patch in regionCaps){patch.Triangles=WeldTriangles(patch.Triangles,weld).ToArray();}shell=RemoveFoldPairs(shell,regionCaps,weld);closed.Clear();closed.AddRange(shell);foreach(var patch in regionCaps)closed.AddRange(patch.Triangles);
    if(!Closed(closed,source.Epsilon*2,out string error))throw new InvalidOperationException("clipped shell validation: "+error);
    exterior.AddRange(shell);
   }
   if(exterior.Count==0)throw new InvalidOperationException("physics proxy has no closed visual volume");
   result.Exterior=exterior.ToArray();result.Caps=caps.ToArray();result.Bytes=(long)(exterior.Count)*3*192;foreach(var cap in caps)result.Bytes+=(long)cap.Triangles.Length*3*192;
   if(result.Bytes>64L*1024*1024)throw new InvalidOperationException("single cell exceeds pending geometry budget");result.Supported=true;result.Reason="Tier 2";
  }catch(OperationCanceledException){result.Reason="obsolete generation cancelled";}catch(InvalidOperationException error){result.Reason=error.Message;}
  return result;
 }
 static List<(Vector2[],int[])> Decompose(Vector2[] cell,float epsilon){
  bool convex=true;for(int i=0;i<cell.Length;i++)if(Cross(cell[(i+1)%cell.Length]-cell[i],cell[(i+2)%cell.Length]-cell[(i+1)%cell.Length])<-epsilon*epsilon){convex=false;break;}
  var result=new List<(Vector2[],int[])>();if(convex){var ids=new int[cell.Length];for(int i=0;i<ids.Length;i++)ids[i]=i;result.Add((cell,ids));return result;}
  foreach(var triangle in Triangulate(new List<Vector2>(cell),epsilon)){
   var p=new[]{cell[triangle.Item1],cell[triangle.Item2],cell[triangle.Item3]};var ids=new[]{-1,-1,-1};for(int i=0;i<3;i++)for(int j=0;j<cell.Length;j++)if((p[i]-cell[j]).sqrMagnitude<epsilon*epsilon&&(p[(i+1)%3]-cell[(j+1)%cell.Length]).sqrMagnitude<epsilon*epsilon)ids[i]=j;result.Add((p,ids));
  }return result;
 }
 sealed class VertexPool {
  public readonly List<Vector3> Points=new List<Vector3>();readonly Dictionary<PointKey,List<int>> buckets=new Dictionary<PointKey,List<int>>();readonly float epsilon;
  public VertexPool(float e){epsilon=e;}
  public int Find(Vector3 point){var key=new PointKey(point,epsilon);for(int z=-1;z<=1;z++)for(int y=-1;y<=1;y++)for(int x=-1;x<=1;x++){var neighbor=new PointKey{X=key.X+x,Y=key.Y+y,Z=key.Z+z};if(buckets.TryGetValue(neighbor,out var ids))foreach(int id in ids)if((Points[id]-point).sqrMagnitude<=epsilon*epsilon)return id;}int result=Points.Count;Points.Add(point);if(!buckets.TryGetValue(key,out var bucket)){bucket=new List<int>();buckets.Add(key,bucket);}bucket.Add(result);return result;}
 }
 static List<List<Vector3>> Contours(List<Segment> input,float epsilon,Plane plane){
  if(input.Count>MaxPlaneSegments)throw new InvalidOperationException("cut contour segment budget exceeded");
  var pool=new VertexPool(epsilon*2);foreach(var edge in input){pool.Find(edge.A);pool.Find(edge.B);}var edges=new Dictionary<(int,int),int>();
  foreach(var segment in input){double dx=(double)segment.B.x-segment.A.x,dy=(double)segment.B.y-segment.A.y,dz=(double)segment.B.z-segment.A.z;double length=dx*dx+dy*dy+dz*dz;if(length<epsilon*epsilon)continue;var split=new List<(float,int)>();// Welding moves endpoints in world units; convert that tolerance to this segment parameter.
   double parameterTolerance=epsilon*2/Math.Sqrt(length);
   for(int i=0;i<pool.Points.Count;i++){double x=(double)pool.Points[i].x-segment.A.x,y=(double)pool.Points[i].y-segment.A.y,z=(double)pool.Points[i].z-segment.A.z,t=(x*dx+y*dy+z*dz)/length;double ex=x-dx*t,ey=y-dy*t,ez=z-dz*t;if(t>=-parameterTolerance&&t<=1+parameterTolerance&&ex*ex+ey*ey+ez*ez<=epsilon*epsilon*4)split.Add(((float)Math.Max(0,Math.Min(1,t)),i));}
   split.Sort((a,b)=>a.Item1.CompareTo(b.Item1));for(int i=0;i+1<split.Count;i++){int a=split[i].Item2,b=split[i+1].Item2;if(a==b||(pool.Points[a]-pool.Points[b]).sqrMagnitude<epsilon*epsilon)continue;edges.TryGetValue((a,b),out int count);edges[(a,b)]=count+1;}
  }
  var next=new Dictionary<int,int>();foreach(var edge in edges){edges.TryGetValue((edge.Key.Item2,edge.Key.Item1),out int reverse);int count=edge.Value-reverse;if(count<=0)continue;if(count!=1||next.ContainsKey(edge.Key.Item1))throw new InvalidOperationException("nonmanifold or touching cut contours");next.Add(edge.Key.Item1,edge.Key.Item2);}
  // Clipping against several prism planes leaves vertical seams at their
  // intersections. Pair source-shell endpoints along each prism corner;
  // closed-solid crossing parity determines the occupied Z intervals.
  var balance=new Dictionary<int,int>();foreach(var edge in next){balance.TryGetValue(edge.Key,out int a);balance[edge.Key]=a+1;balance.TryGetValue(edge.Value,out int b);balance[edge.Value]=b-1;}
  var cornerA=new List<int>();var cornerB=new List<int>();
  foreach(var pair in balance){if(pair.Value==0)continue;if(Math.Abs(pair.Value)!=1)throw new InvalidOperationException("nonmanifold prism corner");var p=pool.Points[pair.Key];var xy=new Vector2(p.x,p.y);if((xy-plane.A).sqrMagnitude<=epsilon*epsilon*16)cornerA.Add(pair.Key);else if((xy-plane.B).sqrMagnitude<=epsilon*epsilon*16)cornerB.Add(pair.Key);else throw new InvalidOperationException($"open source contour away from prism corner point={p} plane={plane.A}/{plane.B} distances={(xy-plane.A).magnitude}/{(xy-plane.B).magnitude}");}
  foreach(var corner in new[]{cornerA,cornerB}){corner.Sort((a,b)=>pool.Points[a].z.CompareTo(pool.Points[b].z));if(corner.Count%2!=0)throw new InvalidOperationException("unpaired prism corner crossing");for(int i=0;i<corner.Count;i+=2){int a=corner[i],b=corner[i+1];if(balance[a]+balance[b]!=0)throw new InvalidOperationException("inconsistent closed-solid corner winding");if(balance[a]>0){int swap=a;a=b;b=swap;}if(next.ContainsKey(a))throw new InvalidOperationException("duplicate prism corner seam");next.Add(a,b);}}
  var loops=new List<List<Vector3>>();while(next.Count>0){int start=int.MaxValue;foreach(int key in next.Keys)start=Math.Min(start,key);int current=start;var loop=new List<Vector3>();do{loop.Add(pool.Points[current]);if(!next.TryGetValue(current,out int target))throw new InvalidOperationException("open cut contour");next.Remove(current);current=target;if(loop.Count>MaxPlaneSegments)throw new InvalidOperationException("cut contour traversal budget exceeded");}while(current!=start);if(loop.Count>=3)loops.Add(loop);}
  return loops;
 }
 static bool Contains(List<Vector2> polygon,Vector2 p){bool inside=false;for(int i=0;i<polygon.Count;i++){var a=polygon[i];var b=polygon[(i+1)%polygon.Count];if((a.y>p.y)!=(b.y>p.y)&&p.x<(b.x-a.x)*(p.y-a.y)/(b.y-a.y)+a.x)inside=!inside;}return inside;}
 static bool Intersects(Vector2 a,Vector2 b,Vector2 c,Vector2 d,float e){float x=Cross(b-a,c-a),y=Cross(b-a,d-a),u=Cross(d-c,a-c),v=Cross(d-c,b-c);return (x>e&&y<-e||x<-e&&y>e)&&(u>e&&v<-e||u<-e&&v>e);}
 static List<Vector2> Bridge(List<Vector2> outer,List<Vector2> hole,List<List<Vector2>> allHoles,float epsilon){
  int h=0;for(int i=1;i<hole.Count;i++)if(hole[i].x>hole[h].x||hole[i].x==hole[h].x&&hole[i].y<hole[h].y)h=i;
  int chosen=-1;float distance=float.MaxValue;for(int o=0;o<outer.Count;o++){
   var a=hole[h];var b=outer[o];if((a-b).sqrMagnitude>=distance)continue;bool blocked=false;
   foreach(var polygon in allHoles){for(int i=0;i<polygon.Count;i++)if(Intersects(a,b,polygon[i],polygon[(i+1)%polygon.Count],epsilon*epsilon)){blocked=true;break;}if(blocked)break;}
   for(int i=0;i<outer.Count&&!blocked;i++)if(Intersects(a,b,outer[i],outer[(i+1)%outer.Count],epsilon*epsilon))blocked=true;
   var midpoint=(a+b)/2;if(!Contains(outer,midpoint))blocked=true;foreach(var polygon in allHoles)if(Contains(polygon,midpoint))blocked=true;
   if(!blocked){chosen=o;distance=(a-b).sqrMagnitude;}
  }
  if(chosen<0)throw new InvalidOperationException("no valid cap hole bridge");
  var result=new List<Vector2>();for(int i=0;i<=chosen;i++)result.Add(outer[i]);for(int i=0;i<=hole.Count;i++)result.Add(hole[(h+i)%hole.Count]);result.Add(outer[chosen]);for(int i=chosen+1;i<outer.Count;i++)result.Add(outer[i]);return result;
 }
 static List<BomClipTriangle> Cap(List<List<Vector3>> contours,Plane plane,int material,float epsilon){
  var direction=Unit(plane.B-plane.A);var u=new Vector3(direction.x,direction.y,0);var origin=new Vector3(plane.A.x,plane.A.y,0);var normal=new Vector3(-plane.Normal.x,-plane.Normal.y,0);var loops=new List<List<Vector2>>();
  foreach(var loop in contours){var points=new List<Vector2>();foreach(var p in loop)points.Add(new Vector2(Vector3.Dot(p-origin,u),p.z));if(Math.Abs(Area(points))>epsilon*epsilon)loops.Add(points);}
  var depth=new int[loops.Count];for(int i=0;i<loops.Count;i++)for(int j=0;j<loops.Count;j++)if(i!=j&&Contains(loops[j],loops[i][0]))depth[i]++;
  var result=new List<BomClipTriangle>();for(int i=0;i<loops.Count;i++){
   if(depth[i]%2!=0)continue;var outer=new List<Vector2>(loops[i]);if(Area(outer)<0)outer.Reverse();var holes=new List<List<Vector2>>();for(int j=0;j<loops.Count;j++)if(depth[j]==depth[i]+1&&Contains(loops[i],loops[j][0])){var hole=new List<Vector2>(loops[j]);if(Area(hole)>0)hole.Reverse();holes.Add(hole);}
   holes.Sort((a,b)=>{float ax=float.MinValue,bx=float.MinValue;foreach(var p in a)ax=Math.Max(ax,p.x);foreach(var p in b)bx=Math.Max(bx,p.x);return bx.CompareTo(ax);});foreach(var hole in holes)outer=Bridge(outer,hole,holes,epsilon);
   BomClipVertex Vertex(Vector2 p)=>new BomClipVertex{Position=origin+u*p.x+Vector3.forward*p.y,Normal=normal,Tangent=new Vector4(u.x,u.y,u.z,1),Color=Color.white,UV0=new Vector4(p.x,p.y,0,0)};
   foreach(var triangle in Triangulate(outer,epsilon))result.Add(new BomClipTriangle(Vertex(outer[triangle.Item1]),Vertex(outer[triangle.Item2]),Vertex(outer[triangle.Item3]),material));
  }return result;
 }
 static List<(int,int,int)> Triangulate(List<Vector2> polygon,float epsilon){
  var remaining=new List<int>();for(int i=0;i<polygon.Count;i++)remaining.Add(i);var result=new List<(int,int,int)>();int budget=polygon.Count*polygon.Count;
  float threshold=epsilon*epsilon;
  while(remaining.Count>3){bool found=false;for(int j=0;j<remaining.Count;j++){
   int a=remaining[(j+remaining.Count-1)%remaining.Count],b=remaining[j],c=remaining[(j+1)%remaining.Count];if(Cross(polygon[b]-polygon[a],polygon[c]-polygon[b])<=threshold)continue;
   if(remaining.Count==4){int other=remaining[(j+2)%remaining.Count];if(Cross(polygon[c]-polygon[a],polygon[other]-polygon[c])<=threshold)continue;}
   bool occupied=false;foreach(int p in remaining){if(p==a||p==b||p==c||(polygon[p]-polygon[a]).sqrMagnitude<=threshold||(polygon[p]-polygon[b]).sqrMagnitude<=threshold||(polygon[p]-polygon[c]).sqrMagnitude<=threshold)continue;if(Cross(polygon[b]-polygon[a],polygon[p]-polygon[a])>=-threshold&&Cross(polygon[c]-polygon[b],polygon[p]-polygon[b])>=-threshold&&Cross(polygon[a]-polygon[c],polygon[p]-polygon[c])>=-threshold){occupied=true;break;}}
   if(occupied)continue;result.Add((a,b,c));remaining.RemoveAt(j);found=true;break;
  }if(!found||--budget<0)throw new InvalidOperationException("cap or concave-cell triangulation failed");}
  if(remaining.Count==3&&Cross(polygon[remaining[1]]-polygon[remaining[0]],polygon[remaining[2]]-polygon[remaining[1]])>threshold)result.Add((remaining[0],remaining[1],remaining[2]));else throw new InvalidOperationException("degenerate final cap triangle");return result;
 }
}
}

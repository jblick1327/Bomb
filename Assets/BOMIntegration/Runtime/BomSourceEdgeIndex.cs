using System;
using System.Collections.Generic;
using UnityEngine;
namespace Bom.Unity {
public class BomVisualCellRegion {
 public ulong Id,Source,Piece;public uint PoseKind;public Vector2[] Outline;public BomClipResult Geometry;
}
public sealed class BomSourceEdgeIndex {
 struct Edge {public ulong Cell;public int Index;public Vector2 A,B;}
 readonly Dictionary<(int,int),List<Edge>> grid=new Dictionary<(int,int),List<Edge>>();readonly Dictionary<ulong,BomVisualCellRegion> cells=new Dictionary<ulong,BomVisualCellRegion>();
 public string Failure{get;private set;}public int Entries{get;private set;}
 public BomSourceEdgeIndex(IEnumerable<BomVisualCellRegion> regions){
  foreach(var cell in regions){cells.Add(cell.Id,cell);for(int i=0;i<cell.Outline.Length;i++){var a=cell.Outline[i];var b=cell.Outline[(i+1)%cell.Outline.Length];int x0=(int)Math.Floor(Math.Min(a.x,b.x)-.0001f),x1=(int)Math.Floor(Math.Max(a.x,b.x)+.0001f),y0=(int)Math.Floor(Math.Min(a.y,b.y)-.0001f),y1=(int)Math.Floor(Math.Max(a.y,b.y)+.0001f);if((long)(x1-x0+1)*(y1-y0+1)>4096){Failure="one edge exceeds the bounded cap-visibility index";grid.Clear();return;}for(int y=y0;y<=y1;y++)for(int x=x0;x<=x1;x++){if(++Entries>500000){Failure="cap-visibility index exceeds its entry budget";grid.Clear();return;}if(!grid.TryGetValue((x,y),out var bucket)){bucket=new List<Edge>();grid.Add((x,y),bucket);}bucket.Add(new Edge{Cell=cell.Id,Index=i,A=a,B=b});}}}
 }
 static float Cross(Vector2 a,Vector2 b)=>a.x*b.y-a.y*b.x;
 public List<BomBoundaryInterval> Occupied(BomVisualCellRegion cell,BomClipPatch patch,float epsilon){
  var result=new List<BomBoundaryInterval>();if(Failure!=null||cell.PoseKind!=0||patch.DecompositionInterior)return result;var direction=patch.EdgeB-patch.EdgeA;float length=direction.magnitude;if(length<=epsilon)return result;direction/=length;epsilon=Math.Max(epsilon,1e-5f);
  int x0=(int)Math.Floor(Math.Min(patch.EdgeA.x,patch.EdgeB.x)-epsilon),x1=(int)Math.Floor(Math.Max(patch.EdgeA.x,patch.EdgeB.x)+epsilon),y0=(int)Math.Floor(Math.Min(patch.EdgeA.y,patch.EdgeB.y)-epsilon),y1=(int)Math.Floor(Math.Max(patch.EdgeA.y,patch.EdgeB.y)+epsilon);var seen=new HashSet<(ulong,int)>();
  for(int y=y0;y<=y1;y++)for(int x=x0;x<=x1;x++)if(grid.TryGetValue((x,y),out var bucket))foreach(var edge in bucket){
   if(edge.Cell==cell.Id||!seen.Add((edge.Cell,edge.Index))||!cells.TryGetValue(edge.Cell,out var other)||other.Source!=cell.Source||other.Piece!=cell.Piece||other.PoseKind!=0||other.Geometry==null||!other.Geometry.Supported)continue;
   if(Vector2.Dot(edge.B-edge.A,direction)>=-epsilon||Math.Abs(Cross(direction,edge.A-patch.EdgeA))>epsilon||Math.Abs(Cross(direction,edge.B-patch.EdgeA))>epsilon)continue;
   float lo=Math.Max(0,Math.Min(Vector2.Dot(edge.A-patch.EdgeA,direction),Vector2.Dot(edge.B-patch.EdgeA,direction))),hi=Math.Min(length,Math.Max(Vector2.Dot(edge.A-patch.EdgeA,direction),Vector2.Dot(edge.B-patch.EdgeA,direction)));if(hi-lo<=epsilon)continue;
   // Verify the neighboring clipped source solid has its corresponding cut.
   // Native occupancy alone cannot hide an original or unrelated asset face.
   foreach(var cap in other.Geometry.Caps){if(cap.Solid!=patch.Solid||cap.DecompositionInterior||cap.Triangles.Length==0)continue;if(Math.Abs(Cross(direction,cap.EdgeA-patch.EdgeA))>epsilon||Math.Abs(Cross(direction,cap.EdgeB-patch.EdgeA))>epsilon)continue;float a=Math.Max(lo,Math.Min(Vector2.Dot(cap.EdgeA-patch.EdgeA,direction),Vector2.Dot(cap.EdgeB-patch.EdgeA,direction))),b=Math.Min(hi,Math.Max(Vector2.Dot(cap.EdgeA-patch.EdgeA,direction),Vector2.Dot(cap.EdgeB-patch.EdgeA,direction)));if(b-a>epsilon)result.Add(new BomBoundaryInterval(a,b));}
  }
  result.Sort((a,b)=>a.Lo!=b.Lo?a.Lo.CompareTo(b.Lo):a.Hi.CompareTo(b.Hi));return result;
 }
}
}

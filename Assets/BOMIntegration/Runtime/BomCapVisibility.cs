using System;
using System.Collections.Generic;
using UnityEngine;
namespace Bom.Unity {
public struct BomBoundaryInterval {public float Lo,Hi;public BomBoundaryInterval(float lo,float hi){Lo=lo;Hi=hi;}}
public static class BomCapVisibility {
 // Callers supply only occupied intervals belonging to the same source solid
 // and one rigid transform. Flexible-cell poses never suppress one another.
 public static BomClipTriangle[] Visible(BomClipPatch patch,IReadOnlyList<BomBoundaryInterval> occupied,float epsilon=1e-5f){
  if(occupied.Count>BomPrismClipper.MaxPlaneSegments)throw new InvalidOperationException("cap visibility interval budget exceeded");
  if(patch.DecompositionInterior)return Array.Empty<BomClipTriangle>();
  if(occupied.Count==0)return patch.Triangles;
  float length=(patch.EdgeB-patch.EdgeA).magnitude;if(length<=epsilon)return patch.Triangles;
  var intervals=new List<BomBoundaryInterval>();foreach(var interval in occupied){float lo=Math.Max(0,Math.Min(interval.Lo,interval.Hi)),hi=Math.Min(length,Math.Max(interval.Lo,interval.Hi));if(hi-lo>epsilon)intervals.Add(new BomBoundaryInterval(lo,hi));}intervals.Sort((a,b)=>a.Lo.CompareTo(b.Lo));
  var visible=new List<BomBoundaryInterval>();float cursor=0;foreach(var interval in intervals){if(interval.Lo>cursor+epsilon)visible.Add(new BomBoundaryInterval(cursor,interval.Lo));cursor=Math.Max(cursor,interval.Hi);}if(cursor<length-epsilon)visible.Add(new BomBoundaryInterval(cursor,length));
  var direction=(patch.EdgeB-patch.EdgeA)/length;float Coordinate(BomClipVertex v)=>Vector2.Dot(new Vector2(v.Position.x,v.Position.y)-patch.EdgeA,direction);
  List<BomClipVertex> Half(List<BomClipVertex> polygon,float limit,bool lower){var result=new List<BomClipVertex>();if(polygon.Count==0)return result;var a=polygon[polygon.Count-1];float da=Coordinate(a)-limit;if(!lower)da=-da;foreach(var b in polygon){float db=Coordinate(b)-limit;if(!lower)db=-db;bool ia=da>=-epsilon,ib=db>=-epsilon;if(ia!=ib)result.Add(BomClipVertex.Lerp(a,b,da/(da-db)));if(ib)result.Add(b);a=b;da=db;}return result;}
  var triangles=new List<BomClipTriangle>();foreach(var interval in visible)foreach(var triangle in patch.Triangles){var polygon=Half(Half(new List<BomClipVertex>{triangle.A,triangle.B,triangle.C},interval.Lo,true),interval.Hi,false);for(int i=1;i+1<polygon.Count;i++)if(Vector3.Cross(polygon[i].Position-polygon[0].Position,polygon[i+1].Position-polygon[0].Position).sqrMagnitude>epsilon*epsilon*epsilon*epsilon){if(triangles.Count>=BomPrismClipper.MaxOutputTriangles)throw new InvalidOperationException("cap visibility output budget exceeded");triangles.Add(new BomClipTriangle(polygon[0],polygon[i],polygon[i+1],triangle.Material));}}return triangles.ToArray();
 }
}
}
